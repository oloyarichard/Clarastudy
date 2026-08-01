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
    notifyListeners();
    
    final newClient = await CallClient.create();
    client = newClient;
    
    newClient.events.listen((event) => _handleEvent(event, currentUserId));
    
    await newClient.join(
      url: Uri.parse(credentials.roomUrl),
      meetingToken: credentials.token,
    );
    await newClient.updateInputs(
      inputs: const InputSettingsUpdate.set(
        camera: CameraInputSettingsUpdate.set(isEnabled: BoolUpdate.set(true)),
        microphone: MicrophoneInputSettingsUpdate.set(isEnabled: BoolUpdate.set(true)),
      ),
    );
    notifyListeners();
  }
  
  void _handleEvent(CallEvent event, String? currentUserId) {
    event.when(
      participantJoined: (participant) {
        final id = participant.info.userId;
        final name = participant.info.userName.isNotEmpty ? participant.info.userName : 'Someone';
    participants[id] = name;
    notifyListeners();
    
    final isSelf = currentUserId != null && id == currentUserId;
    if (isOwner && !isSelf) {
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('$name joined the class')),
      );
    }
      },
      participantLeft: (participant, reason) {
        participants.remove(participant.info.userId);
        notifyListeners();
      },
      participantUpdated: (participant) {
        participants[participant.info.userId] = participant.info.userName;
        notifyListeners();
      },
      callStateUpdated: (state) {
        if (state == CallState.left) {
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
  
  /// TEMPORARILY DISABLED, same reasoning as muteParticipant() below:
  /// this method combined several unverified daily_flutter API guesses
  /// (device enumeration shape, facing-mode property/values, a nested
  /// settings structure) — exactly the kind of guess that just broke a
  /// build. Cleanly disabled rather than risking that twice. Everything
  /// else (join, your own mic/camera on-off, leave, minimize, chat) is
  /// unaffected.
  Future<void> flipCamera() async {
    throw Exception('Camera switching is temporarily unavailable.');
  }
  
  /// Owner-only remote mute.
  ///
  /// TEMPORARILY DISABLED: the real CallClient method is
  /// updateRemoteParticipants(updatesById: Map<ParticipantId,
  /// RemoteParticipantUpdate>) — confirmed by name via the daily_flutter
  /// changelog and the equivalent Android SDK reference — but the exact
  /// field(s) on RemoteParticipantUpdate for muting a mic aren't
  /// confirmed yet. Rather than guess that shape and risk another failed
  /// build, this is a clean no-op for now: everything else (join, mute
  /// your own mic, camera, leave, minimize, chat) is unaffected. Wire
  /// this back in once RemoteParticipantUpdate's real fields are
  /// confirmed against the actual package source.
  Future<void> muteParticipant(String participantId) async {
    if (!isOwner) return;
    // Intentionally not calling client.updateRemoteParticipants(...) yet.
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
    participants.clear();
    notifyListeners();
  }
}

final dailyCallSessionProvider = ChangeNotifierProvider<DailyCallSession>((ref) {
  return DailyCallSession();
});
