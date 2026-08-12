import 'dart:async';

import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/call_permissions.dart';
import '../core/utils/global_keys.dart';
import '../data/live_class_repository.dart';
import '../models/live_class_models.dart';
import 'core_providers.dart';

/// Owns the one and only native Daily [CallClient] for the whole app.
///
/// Lifecycle rules (do not break these):
///  * Runtime camera/mic permission is checked BEFORE CallClient.create().
///  * Every VideoViewController that renders a Daily track must register a
///    release callback here, so tracks are detached BEFORE native dispose().
///    Disposing the native client while a renderer still holds a track is a
///    use-after-free and takes the whole app down.
///  * Native leave/dispose is time-boxed — a wedged native call must never
///    wedge the Dart side.
class DailyCallSession extends ChangeNotifier {
  DailyCallSession(this._repository);

  final LiveClassRepository _repository;

  CallClient? client;

  String? liveClassId;
  String? liveClassTitle;

  bool isOwner = false;
  bool isMinimized = false;
  bool micEnabled = true;
  bool cameraEnabled = true;
  bool usingFrontCamera = true;

  bool allMuted = false;

  final Map<String, String> participants = {};

  StreamSubscription<Event>? _eventSubscription;

  // Only one native leave/dispose operation may run at once.
  Future<void>? _leaveOperation;

  List<RaisedHandEntry> raisedHands = [];
  bool myHandRaised = false;

  Timer? _handsPollTimer;
  String? _currentUserId;

  bool _disposed = false;

  /// Views register a callback that detaches their VideoViewControllers from
  /// Daily tracks. Invoked immediately before the native client is destroyed.
  final Set<VoidCallback> _trackReleaseCallbacks = <VoidCallback>{};

  bool get hasActiveCall => client != null;

  /// True while the native client is being torn down. Views should stop
  /// touching tracks entirely once this flips.
  bool get isTearingDown => _leaveOperation != null;

  void addTrackReleaseCallback(VoidCallback callback) {
    _trackReleaseCallbacks.add(callback);
  }

  void removeTrackReleaseCallback(VoidCallback callback) {
    _trackReleaseCallbacks.remove(callback);
  }

  void _releaseAllTracks() {
    // Copy first — a callback may unregister itself while running.
    for (final callback in _trackReleaseCallbacks.toList()) {
      try {
        callback();
      } catch (e) {
        debugPrint('Track release callback failed: $e');
      }
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // --------------------------------------------------------------------------
  // START
  // --------------------------------------------------------------------------

  Future<void> start({
    required String liveClassId,
    required String liveClassTitle,
    required DailyCallCredentials credentials,
    required String? currentUserId,
  }) async {
    // Permission FIRST. Daily does not ask on your behalf, and creating a
    // client without camera/mic access is what kills the app on the very
    // first call.
    await CallPermissions.ensureGranted();

    // If another leave is still shutting down the native client, wait it out.
    if (_leaveOperation != null) {
      await _leaveOperation;
    }

    // Never have two Daily clients active.
    if (client != null) {
      await leave();
    }

    this.liveClassId = liveClassId;
    this.liveClassTitle = liveClassTitle;

    isOwner = credentials.isOwner;

    participants.clear();

    micEnabled = true;
    cameraEnabled = true;
    usingFrontCamera = true;

    isMinimized = false;
    allMuted = false;

    raisedHands = [];
    myHandRaised = false;

    _currentUserId = currentUserId;

    notifyListeners();

    const maxAttempts = 2;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _attemptJoin(credentials, currentUserId);
        return;
      } catch (e) {
        final isLastAttempt = attempt == maxAttempts;

        await _teardownFailedClient();

        if (isLastAttempt) {
          _reset();
          rethrow;
        }

        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
  }

  Future<void> _attemptJoin(
    DailyCallCredentials credentials,
    String? currentUserId,
  ) async {
    final newClient = await CallClient.create();

    client = newClient;

    _eventSubscription = newClient.events.listen(
      (event) => _handleEvent(event, currentUserId),
    );

    await newClient.join(
      url: Uri.parse(credentials.roomUrl),
      token: credentials.token,
    );

    await newClient.updateInputs(
      inputs: const InputSettingsUpdate.set(
        camera: CameraInputSettingsUpdate.set(
          isEnabled: BoolUpdate.set(true),
        ),
        microphone: MicrophoneInputSettingsUpdate.set(
          isEnabled: BoolUpdate.set(true),
        ),
      ),
    );

    _handsPollTimer?.cancel();

    _handsPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollRaisedHands(),
    );

    notifyListeners();
  }

  Future<void> _teardownFailedClient() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    final failedClient = client;

    _releaseAllTracks();

    client = null;

    notifyListeners();

    if (failedClient == null) return;

    await _destroyClient(failedClient);
  }

  /// Native leave + dispose, each time-boxed so a hung native call can never
  /// wedge the app. This is the difference between "hang up" and "hangs".
  Future<void> _destroyClient(CallClient target) async {
    try {
      await target.leave().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Daily client leave error: $e');
    }

    try {
      await target.dispose().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Daily client dispose error: $e');
    }
  }

  // --------------------------------------------------------------------------
  // RAISED HANDS
  // --------------------------------------------------------------------------

  Future<void> _pollRaisedHands() async {
    final id = liveClassId;

    if (id == null || client == null || _leaveOperation != null) {
      return;
    }

    try {
      final fresh = await _repository.getRaisedHands(id);

      if (client == null || _leaveOperation != null) return;

      final previousIds = raisedHands.map((h) => h.userId).toSet();
      final freshIds = fresh.map((h) => h.userId).toSet();

      final newlyRaised = fresh.where(
        (h) =>
            !previousIds.contains(h.userId) && h.userId != _currentUserId,
      );

      for (final entry in newlyRaised) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('${entry.userName} raised their hand ✋')),
        );
      }

      final nextMyHandRaised = fresh.any((h) => h.userId == _currentUserId);

      // Only rebuild the UI when something actually changed. This poll used
      // to notify every 2s, rebuilding the call screen and the bubble
      // constantly — a real source of the switching jank.
      final unchanged = previousIds.length == freshIds.length &&
          previousIds.containsAll(freshIds) &&
          myHandRaised == nextMyHandRaised;

      raisedHands = fresh;
      myHandRaised = nextMyHandRaised;

      if (!unchanged) {
        notifyListeners();
      }
    } catch (_) {
      // Ignore one failed poll.
    }
  }

  Future<void> toggleMyHand() async {
    final id = liveClassId;

    if (id == null || client == null || _leaveOperation != null) return;

    try {
      myHandRaised = await _repository.toggleRaisedHand(id);
      notifyListeners();
      await _pollRaisedHands();
    } catch (_) {}
  }

  Future<void> lowerHand(String userId) async {
    final id = liveClassId;

    if (id == null || !isOwner || client == null || _leaveOperation != null) {
      return;
    }

    try {
      await _repository.toggleRaisedHand(id, userId: userId);
      await _pollRaisedHands();
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // EVENTS
  // --------------------------------------------------------------------------

  void _handleEvent(Event event, String? currentUserId) {
    // Once teardown starts, Daily callbacks must not touch our state.
    if (_leaveOperation != null || _disposed) return;

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
        participants[participant.info.userId ?? ''] =
            participant.info.username ?? '';
        notifyListeners();
      },
      callStateUpdated: (stateData) {
        if (stateData.state == CallState.left) {
          // The call ended from the outside (host ended the meeting, we were
          // ejected, network gave up). The old code just nulled the client
          // and LEAKED it — the native object stayed alive holding the
          // camera, so the *next* CallClient.create() fought with a zombie.
          // Tear it down properly instead.
          if (_leaveOperation == null) {
            unawaited(leave());
          }
        }
      },
      inputsUpdated: (inputs) {
        micEnabled = inputs.microphone.isEnabled;
        cameraEnabled = inputs.camera.isEnabled;
        notifyListeners();
      },
      orElse: () {},
    );
  }

  // --------------------------------------------------------------------------
  // MINIMIZE / MAXIMIZE
  // --------------------------------------------------------------------------

  void minimize() {
    if (client == null || isMinimized) return;
    isMinimized = true;
    notifyListeners();
  }

  void maximize() {
    if (client == null || !isMinimized) return;
    isMinimized = false;
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // MICROPHONE / CAMERA
  // --------------------------------------------------------------------------

  Future<void> toggleMic() async {
    final c = client;
    if (c == null || _leaveOperation != null) return;

    final next = !micEnabled;

    try {
      await c.updateInputs(
        inputs: InputSettingsUpdate.set(
          microphone: MicrophoneInputSettingsUpdate.set(
            isEnabled: BoolUpdate.set(next),
          ),
        ),
      );

      micEnabled = next;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleCamera() async {
    final c = client;
    if (c == null || _leaveOperation != null) return;

    final next = !cameraEnabled;

    try {
      await c.updateInputs(
        inputs: InputSettingsUpdate.set(
          camera: CameraInputSettingsUpdate.set(
            isEnabled: BoolUpdate.set(next),
          ),
        ),
      );

      cameraEnabled = next;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> flipCamera() async {
    final c = client;
    if (c == null || _leaveOperation != null) return;

    final nextFacing = usingFrontCamera
        ? MediaTrackFacingMode.environment
        : MediaTrackFacingMode.user;

    try {
      await c.setCameraFacingMode(facingMode: nextFacing);
      usingFrontCamera = !usingFrontCamera;
      notifyListeners();
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // REMOTE PARTICIPANTS
  // --------------------------------------------------------------------------

  Future<void> _updateRemoteParticipants(
    Map<String, RemoteParticipantUpdate> byId,
  ) async {
    final c = client;

    if (!isOwner || c == null || byId.isEmpty || _leaveOperation != null) {
      return;
    }

    await c.updateRemoteParticipants(
      updates: RemoteParticipantSettingsUpdatesById.set(
        updates: {
          for (final entry in byId.entries)
            ParticipantId(entry.key): entry.value,
        },
      ),
    );
  }

  Future<void> muteParticipant(String participantId) async {
    await _updateRemoteParticipants({
      participantId: RemoteParticipantUpdate.set(
        inputsEnabled: RemoteInputsEnabledUpdate.set(microphone: false),
      ),
    });
  }

  Future<void> _setAllMicrophones(bool enabled) async {
    await _updateRemoteParticipants({
      for (final id in participants.keys)
        id: RemoteParticipantUpdate.set(
          inputsEnabled: RemoteInputsEnabledUpdate.set(microphone: enabled),
        ),
    });
  }

  Future<void> muteAllParticipants() async {
    await _setAllMicrophones(false);
    allMuted = true;
    notifyListeners();
  }

  Future<void> unmuteAllParticipants() async {
    await _setAllMicrophones(true);
    allMuted = false;
    notifyListeners();
  }

  Future<void> toggleMuteAll() async {
    if (allMuted) {
      await unmuteAllParticipants();
    } else {
      await muteAllParticipants();
    }
  }

  // --------------------------------------------------------------------------
  // LEAVE
  // --------------------------------------------------------------------------

  /// Idempotent. If the full screen and the bubble both hang up at the same
  /// instant, they share ONE leave and ONE dispose.
  Future<void> leave() {
    final existing = _leaveOperation;
    if (existing != null) return existing;

    final operation = _performLeave();

    _leaveOperation = operation;

    operation.whenComplete(() {
      if (identical(_leaveOperation, operation)) {
        _leaveOperation = null;
      }
    });

    return operation;
  }

  Future<void> _performLeave() async {
    final clientToLeave = client;

    // 1. Stop Daily callbacks.
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    // 2. Stop REST polling.
    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    // 3. Detach every renderer from its track BEFORE the native client dies.
    //    This is the step that was missing. Nulling `client` hides the
    //    VideoView widgets, but the VideoViewControllers were still holding
    //    native track handles when dispose() ran underneath them.
    _releaseAllTracks();

    // 4. Now drop the client reference so no widget can re-attach.
    client = null;
    isMinimized = false;
    participants.clear();
    raisedHands = [];
    myHandRaised = false;

    notifyListeners();

    // 5. Let Flutter render one frame without any VideoView. endOfFrame can
    //    hang if no frame is ever scheduled, so it is raced against a
    //    deadline rather than awaited blindly.
    await _nextFrame();

    if (clientToLeave == null) {
      _reset();
      return;
    }

    await _destroyClient(clientToLeave);

    _reset();
  }

  Future<void> _nextFrame() async {
    try {
      await WidgetsBinding.instance.endOfFrame
          .timeout(const Duration(milliseconds: 250));
    } catch (_) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // --------------------------------------------------------------------------
  // RESET
  // --------------------------------------------------------------------------

  void _reset() {
    client = null;

    liveClassId = null;
    liveClassTitle = null;

    isOwner = false;
    isMinimized = false;
    allMuted = false;

    raisedHands = [];
    myHandRaised = false;

    _currentUserId = null;

    participants.clear();

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;

    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    final sub = _eventSubscription;
    _eventSubscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }

    _trackReleaseCallbacks.clear();

    final orphan = client;
    client = null;

    if (orphan != null) {
      // Provider is going away with a live call — don't leak the camera.
      unawaited(_destroyClient(orphan));
    }

    super.dispose();
  }
}

final dailyCallSessionProvider =
    ChangeNotifierProvider<DailyCallSession>((ref) {
  return DailyCallSession(ref.watch(liveClassRepositoryProvider));
});
