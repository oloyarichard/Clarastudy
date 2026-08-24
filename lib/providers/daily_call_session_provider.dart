import 'dart:async';

import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/utils/call_permissions.dart';
import '../core/utils/global_keys.dart';
import '../data/live_class_repository.dart';
import '../models/live_class_models.dart';
import 'core_providers.dart';

/// Owns the Daily [CallClient] for the whole app.
///
/// CRITICAL LIFECYCLE DECISION — read before changing this file:
///
/// Daily's own reference app (daily-flutter-demo, daily-co/daily-flutter-demo
/// on GitHub) creates exactly ONE CallClient for the entire app session, at
/// startup, and never disposes it until the app itself shuts down. Leaving a
/// call is `client.leave()`. Joining the next one is `client.join()` on that
/// SAME instance. `CallClient.dispose()` is called exactly once, ever.
///
/// This provider used to call `CallClient.create()` fresh for every class and
/// `.dispose()` it on every hang-up. That create-then-dispose-then-create
/// cycle is NOT the pattern the SDK is built and tested around, and it is
/// the actual cause of the delayed crash after hang-up: popping the call
/// screen would succeed, then a moment later — while `dispose()` ran on the
/// native client in the background — the app would crash. Repeated
/// create()/dispose() cycling of the native object is what triggered it.
///
/// The fix: create the client ONCE (lazily, on first use — Daily's demo can
/// create it at main() because it has permission by then; we can't assume
/// that, so we create it on the first `start()` call instead) and reuse it
/// for every class via leave()/join(). Never dispose it between calls.
///
/// Other lifecycle rules (still true):
///  * Runtime camera/mic permission is checked BEFORE the client is used.
///  * Every VideoViewController that renders a Daily track must register a
///    release callback here, so tracks are detached BEFORE the client
///    leaves the room — disposing/leaving while a renderer still holds a
///    track is a use-after-free.
///  * Native leave is time-boxed — a wedged native call must never wedge
///    the Dart side.
class DailyCallSession extends ChangeNotifier {
  DailyCallSession(this._repository);

  final LiveClassRepository _repository;

  // Created once, lazily, on the first start(). Reused for every call via
  // leave()/join(). Only ever disposed in this provider's own dispose(),
  // which in practice means "the app is shutting down."
  CallClient? _persistentClient;

  // True only while actually joined to a room. `client` below is exposed
  // as null whenever this is false, so every existing check in the UI
  // (`session.client != null`, `session.hasActiveCall`) keeps working
  // exactly as before even though the underlying CallClient object now
  // persists across calls.
  bool _inCall = false;

  /// Public view of the client — null unless actually in a call, even
  /// though the real CallClient underneath may already exist from a
  /// previous call. Every existing UI reference to `session.client`
  /// continues to behave identically to before this rewrite.
  CallClient? get client => _inCall ? _persistentClient : null;

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

  // Only one leave operation may run at once.
  Future<void>? _leaveOperation;

  List<RaisedHandEntry> raisedHands = [];
  bool myHandRaised = false;

  Timer? _handsPollTimer;
  String? _currentUserId;

  bool _disposed = false;

  // Bumped by leave() (and by a new start()). A join in flight checks this
  // after every await — if it changed underneath it, that join has been
  // superseded and must leave the room it may have half-joined instead of
  // presenting it as active. This is what protects hang-up/cancel tapped
  // while the call is still connecting.
  int _joinGeneration = 0;

  /// Views register a callback that detaches their VideoViewControllers from
  /// Daily tracks. Invoked immediately before the client leaves the room.
  final Set<VoidCallback> _trackReleaseCallbacks = <VoidCallback>{};

  bool get hasActiveCall => _inCall;

  /// True while a leave is in progress. Views should stop touching tracks
  /// entirely once this flips.
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

  /// Returns the one persistent CallClient, creating it on first use.
  Future<CallClient> _ensureClient() async {
    final existing = _persistentClient;
    if (existing != null) return existing;

    final created = await CallClient.create();
    _persistentClient = created;
    return created;
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
    // Permission FIRST. Daily does not ask on your behalf, and using the
    // client without camera/mic access is what kills the app on the very
    // first call.
    await CallPermissions.ensureGranted();

    // If a leave is still in progress, wait it out.
    if (_leaveOperation != null) {
      await _leaveOperation;
    }

    // Never be "in" two calls at once — leave the current room first.
    if (_inCall) {
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

    // Claim this join attempt. Any leave() (including one that races in
    // while we're still awaiting below) bumps this and makes our attempt
    // stale.
    final myGeneration = ++_joinGeneration;

    notifyListeners();

    const maxAttempts = 2;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _attemptJoin(credentials, currentUserId, myGeneration);
        return;
      } catch (e) {
        final isLastAttempt = attempt == maxAttempts;

        await _teardownFailedJoin();

        if (isLastAttempt) {
          _reset();
          rethrow;
        }

        // A superseded join (leave() raced in) should not blindly retry.
        if (myGeneration != _joinGeneration) {
          return;
        }

        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
  }

  Future<void> _attemptJoin(
    DailyCallCredentials credentials,
    String? currentUserId,
    int myGeneration,
  ) async {
    final callClient = await _ensureClient();

    // If leave() (or a newer start()) ran while we were awaiting
    // CallClient creation/reuse, this attempt is stale.
    if (myGeneration != _joinGeneration) {
      throw StateError('Join superseded by leave()');
    }

    _eventSubscription = callClient.events.listen(
      (event) => _handleEvent(event, currentUserId),
    );

    await callClient.join(
      url: Uri.parse(credentials.roomUrl),
      token: credentials.token,
    );

    if (myGeneration != _joinGeneration) {
      await _eventSubscription?.cancel();
      _eventSubscription = null;

      // We half-joined a room nobody wants anymore — leave it, but the
      // CLIENT itself stays alive for whatever join comes next.
      try {
        await callClient.leave().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Leave (superseded join) error: $e');
      }

      throw StateError('Join superseded by leave()');
    }

    await callClient.updateInputs(
      inputs: const InputSettingsUpdate.set(
        camera: CameraInputSettingsUpdate.set(
          isEnabled: BoolUpdate.set(true),
        ),
        microphone: MicrophoneInputSettingsUpdate.set(
          isEnabled: BoolUpdate.set(true),
        ),
      ),
    );

    if (myGeneration != _joinGeneration) {
      await _eventSubscription?.cancel();
      _eventSubscription = null;

      try {
        await callClient.leave().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Leave (superseded join) error: $e');
      }

      throw StateError('Join superseded by leave()');
    }

    _inCall = true;

    // Keep the screen from dimming/locking for as long as the call is
    // actually live — a locked screen during a lesson is exactly the
    // "phone went idle mid-call" problem. Paired with WakelockPlus.disable()
    // everywhere the call ends (see _reset, _teardownFailedJoin, dispose).
    unawaited(
      WakelockPlus.enable().catchError((Object e, StackTrace stackTrace) {
        debugPrint('Wakelock enable failed: $e');
      }),
    );

    _handsPollTimer?.cancel();

    _handsPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollRaisedHands(),
    );

    notifyListeners();
  }

  Future<void> _teardownFailedJoin() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    _releaseAllTracks();

    _inCall = false;

    unawaited(WakelockPlus.disable().catchError((Object e, StackTrace stackTrace) {
      debugPrint('Wakelock disable failed: $e');
    }));

    notifyListeners();
    final callClient = _persistentClient;
    if (callClient == null) return;

    try {
      await callClient.leave().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Leave (failed join cleanup) error: $e');
    }
  }

  // --------------------------------------------------------------------------
  // RAISED HANDS
  // --------------------------------------------------------------------------

  Future<void> _pollRaisedHands() async {
    final id = liveClassId;

    if (id == null || !_inCall || _leaveOperation != null) {
      return;
    }

    try {
      final fresh = await _repository.getRaisedHands(id);

      if (!_inCall || _leaveOperation != null) return;

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
      // constantly — a real source of switching jank.
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

    if (id == null || !_inCall || _leaveOperation != null) return;

    try {
      myHandRaised = await _repository.toggleRaisedHand(id);
      notifyListeners();
      await _pollRaisedHands();
    } catch (_) {}
  }

  Future<void> lowerHand(String userId) async {
    final id = liveClassId;

    if (id == null || !isOwner || !_inCall || _leaveOperation != null) {
      return;
    }

    try {
      await _repository.toggleRaisedHand(id, userId: userId);
      await _pollRaisedHands();
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // EVENTS
  // ----------------------------------------------------------------------
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
          // ejected, network gave up). Leave cleanly on our side too — but
          // the underlying client object is left alone, ready for the next
          // join.
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
    if (!_inCall || isMinimized) return;
    isMinimized = true;
    notifyListeners();
  }

  void maximize() {
    if (!_inCall || !isMinimized) return;
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
  /// instant, they share ONE leave.
  ///
  /// IMPORTANT: this leaves the ROOM. It does NOT dispose the CallClient —
  /// the client is reused for the next call. See the class doc comment for
  /// why that distinction is the actual fix for the crash-after-hang-up bug.
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
    final callClient = _persistentClient;
    final wasInCall = _inCall;

    // 1. Stop Daily callbacks.
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    // 2. Stop REST polling.
    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    // 3. Detach every renderer from its track BEFORE the client leaves the
    //    room. Nulling `_inCall` hides the VideoView widgets, but the
    //    VideoViewControllers were still holding native track handles if
    //    this step was skipped.
    _releaseAllTracks();

    // 4. Now flip the flag so no widget can re-attach or think it's live.
    _inCall = false;
    isMinimized = false;
    participants.clear();
    raisedHands = [];
    myHandRaised = false;

    notifyListeners();

    // 5. Let Flutter render one frame without any VideoView. endOfFrame can
    //    hang if no frame is ever scheduled, so it is raced against a
    //    deadline rather than awaited blindly.
    await _nextFrame();

    if (!wasInCall || callClient == null) {
      _reset();
      return;
    }

    // 6. Leave the room. The CallClient object itself is deliberately NOT
    //    disposed — it stays alive, ready for the next join(). Time-boxed
    //    so a wedged native call can never wedge the app.
    try {
      await callClient.leave().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Daily client leave error: $e');
    }

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
    _inCall = false;

    unawaited(WakelockPlus.disable().catchError((Object e, StackTrace stackTrace) {
      debugPrint('Wakelock disable failed: $e');
    }));

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
    // This is genuine app shutdown — the one place the persistent client
    // actually gets disposed, matching Daily's own reference app calling
    // dispose() exactly once, at the very end of the app's life.
    _disposed = true;

    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    final sub = _eventSubscription;
    _eventSubscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }

    _trackReleaseCallbacks.clear();

    final callClient = _persistentClient;
    _persistentClient = null;
    _inCall = false;

    unawaited(WakelockPlus.disable().catchError((Object e, StackTrace stackTrace) {
      debugPrint('Wakelock disable failed: $e');
    }));

    if (callClient != null) {
      unawaited(callClient.dispose());
    }

    super.dispose();
  }
}

final dailyCallSessionProvider =
    ChangeNotifierProvider<DailyCallSession>((ref) {
  return DailyCallSession(ref.watch(liveClassRepositoryProvider));
});
