import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/global_keys.dart';
import '../models/live_class_models.dart';

/// Holds the active Daily call's live state at the APP level, not inside
/// DailyCallScreen's local state. This is what makes "minimize" actually
/// work: minimizing just pops the full-screen route, but the CallClient
/// living here is untouched and keeps the call running. Re-opening the
/// full-screen view re-attaches to this same client instead of joining
/// again from scratch.
class DailyCallSession extends ChangeNotifier {
  CallClient? client;
  String? liveClassId;
  String? liveClassTitle;
  bool isOwner = false;
  bool isMinimized = false;
  bool micEnabled = true;
  bool cameraEnabled = true;
  bool usingFrontCamera = true;
  /// Teacher-facing toggle state — true after "Mute all" was last
  /// pressed, false after "Unmute all". This is just a UI hint for
  /// which label/icon to show next; it's not an enforced lock, since
  /// "Unmute all" resets everyone's mic to on but each participant can
  /// still freely mute/unmute themselves afterward (an open meeting),
  /// same as "Mute all" doesn't prevent someone from unmuting themselves.
  bool allMuted = false;
  final Map<String, String> participants = {};

  bool get hasActiveCall => client != null;

  Future<void> start({
    required String liveClassId,
    required String liveClassTitle,
    required DailyCallCredentials credentials,
    required String? currentUserId,
  }) async {
    if (client != null) {
      // Already in a call (this one or another) — caller is responsible
      // for checking hasActiveCall / liveClassId first and confirming
      // with the user before calling start() again.
      await leave();
    }

    this.liveClassId = liveClassId;
    this.liveClassTitle = liveClassTitle;
    isOwner = credentials.isOwner;
    participants.clear();
    micEnabled = true;
    cameraEnabled = true;
    isMinimized = false;
    allMuted = false;
    notifyListeners();

    final newClient = await CallClient.create();
    client = newClient;

    newClient.events.listen((event) => _handleEvent(event, currentUserId));

    try {
      await newClient.join(
        url: Uri.parse(credentials.roomUrl),
        token: credentials.token,
      );
    } catch (e) {
      // join() failed (timeout, network issue, etc.) — reset back to no
      // active call so a retry from the UI actually attempts a fresh
      // join, instead of _ensureJoined() thinking we're already
      // connected because `client` was non-null.
      _reset();
      rethrow;
    }
    await newClient.updateInputs(
      inputs: const InputSettingsUpdate.set(
        camera: CameraInputSettingsUpdate.set(isEnabled: BoolUpdate.set(true)),
        microphone: MicrophoneInputSettingsUpdate.set(isEnabled: BoolUpdate.set(true)),
      ),
    );
    notifyListeners();
  }

  void _handleEvent(Event event, String? currentUserId) {
    event.maybeWhen(
      participantJoined: (participant) {
        final id = participant.info.userId ?? '';
        final name = (participant.info.username?.isNotEmpty ?? false)
            ? participant.info.username!
            : 'Someone';
        participants[id] = name;
        notifyListeners();

        final isSelf = currentUserId != null && id == currentUserId;
        if (isOwner && !isSelf) {
          appScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('$name joined the class')),
          );
        }
      },
      participantLeft: (participant) {
        participants.remove(participant.info.userId ?? '');
        notifyListeners();
      },
      participantUpdated: (participant) {
        participants[participant.info.userId ?? ''] = participant.info.username ?? '';
        notifyListeners();
      },
      callStateUpdated: (stateData) {
        if (stateData.state == CallState.left) {
          _reset();
        }
      },
      orElse: () {},
    );
  }

  void minimize() {
    isMinimized = true;
    notifyListeners();
  }

  void maximize() {
    isMinimized = false;
    notifyListeners();
  }

  Future<void> toggleMic() async {
    micEnabled = !micEnabled;
    await client?.updateInputs(
      inputs: InputSettingsUpdate.set(
        microphone: MicrophoneInputSettingsUpdate.set(isEnabled: BoolUpdate.set(micEnabled)),
      ),
    );
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    cameraEnabled = !cameraEnabled;
    await client?.updateInputs(
      inputs: InputSettingsUpdate.set(
        camera: CameraInputSettingsUpdate.set(isEnabled: BoolUpdate.set(cameraEnabled)),
      ),
    );
    notifyListeners();
  }

  /// Confirmed via pub.dev class docs (CameraInputSettingsUpdate,
  /// VideoMediaTrackSettingsUpdate, MediaTrackFacingModeUpdate) — facing
  /// mode is a plain enum (.user / .environment), no device list needed.
  /// The one remaining unverified detail is the exact construction of the
  /// generic Update<T>.set(...) wrapper for the nested settings field —
  /// everything else here is confirmed against real class signatures.
  Future<void> flipCamera() async {
    final c = client;
    if (c == null) return;
    final nextFacing = usingFrontCamera
        ? MediaTrackFacingModeUpdate.environment
        : MediaTrackFacingModeUpdate.user;
    await c.updateInputs(
      inputs: InputSettingsUpdate.set(
        camera: CameraInputSettingsUpdate.set(
          settings: Update<VideoMediaTrackSettingsUpdate>.set(
            VideoMediaTrackSettingsUpdate.set(facingMode: nextFacing),
          ),
        ),
      ),
    );
    usingFrontCamera = !usingFrontCamera;
    notifyListeners();
  }

  /// Owner-only remote mute — confirmed via pub.dev class docs
  /// (RemoteParticipantUpdate, RemoteInputsEnabledUpdate). The one
  /// unverified detail is ParticipantId's exact constructor — everything
  /// else here (method name, argument shape, field names) is confirmed.
  Future<void> muteParticipant(String participantId) async {
    if (!isOwner) return;
    await client?.updateRemoteParticipants(
      updatesById: {
        ParticipantId(participantId): RemoteParticipantUpdate.set(
          inputsEnabled: RemoteInputsEnabledUpdate.set(microphone: false),
        ),
      },
    );
  }

  /// Owner-only: sets every current participant's microphone to the
  /// given state in one call. Shared by muteAllParticipants() and
  /// unmuteAllParticipants() below.
  Future<void> _setAllMicrophones(bool enabled) async {
    if (!isOwner || client == null) return;
    final updates = <ParticipantId, RemoteParticipantUpdate>{
      for (final id in participants.keys)
        ParticipantId(id): RemoteParticipantUpdate.set(
          inputsEnabled: RemoteInputsEnabledUpdate.set(microphone: enabled),
        ),
    };
    if (updates.isEmpty) return;
    await client!.updateRemoteParticipants(updatesById: updates);
  }

  /// Owner-only: mutes every current participant's microphone — a
  /// noise-free meeting where only the teacher (and whoever they
  /// individually unmute) can be heard.
  Future<void> muteAllParticipants() async {
    await _setAllMicrophones(false);
    allMuted = true;
    notifyListeners();
  }

  /// Owner-only: resets every current participant's microphone to on —
  /// an open meeting where each participant can then freely mute or
  /// unmute themselves as they choose. This doesn't lock anyone's mic
  /// on; it's a one-time reset, same as muteAllParticipants() is a
  /// one-time reset the other direction.
  Future<void> unmuteAllParticipants() async {
    await _setAllMicrophones(true);
    allMuted = false;
    notifyListeners();
  }

  /// What the teacher's toggle button should do next, based on the
  /// current mode.
  Future<void> toggleMuteAll() async {
    if (allMuted) {
      await unmuteAllParticipants();
    } else {
      await muteAllParticipants();
    }
  }

  Future<void> leave() async {
    // NOTE: intentionally NOT calling client.dispose() — the official
    // daily-flutter-demo README states the CallClient is meant to
    // persist and be reusable after leaving a call ("the CallClient
    // remains and can be re-used for further calls... it is not
    // destroyed until the application exits"). dispose() was only ever
    // confirmed to exist on VideoViewController, never on CallClient
    // itself — calling a nonexistent method here would have broken
    // every single "leave call" action in the app.
    await client?.leave();
    _reset();
  }

  void _reset() {
    client = null;
    liveClassId = null;
    liveClassTitle = null;
    isOwner = false;
    isMinimized = false;
    allMuted = false;
    participants.clear();
    notifyListeners();
  }
}

final dailyCallSessionProvider = ChangeNotifierProvider<DailyCallSession>((ref) {
  return DailyCallSession();
});
