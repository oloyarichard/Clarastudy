import 'dart:async';

import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/global_keys.dart';
import '../data/live_class_repository.dart';
import '../models/live_class_models.dart';
import 'core_providers.dart';

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

  bool get hasActiveCall => client != null;

  Future<void> start({
    required String liveClassId,
    required String liveClassTitle,
    required DailyCallCredentials credentials,
    required String? currentUserId,
  }) async {
    // If another leave is still shutting down the native client,
    // wait for it completely.
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

    for (
      var attempt = 1;
      attempt <= maxAttempts;
      attempt++
    ) {
      try {
        await _attemptJoin(
          credentials,
          currentUserId,
        );

        return;
      } catch (e) {
        final isLastAttempt =
            attempt == maxAttempts;

        await _teardownFailedClient();

        if (isLastAttempt) {
          _reset();
          rethrow;
        }

        await Future.delayed(
          const Duration(
            milliseconds: 800,
          ),
        );
      }
    }
  }

  Future<void> _attemptJoin(
    DailyCallCredentials credentials,
    String? currentUserId,
  ) async {
    final newClient =
        await CallClient.create();

    client = newClient;

    _eventSubscription =
        newClient.events.listen(
      (event) {
        _handleEvent(
          event,
          currentUserId,
        );
      },
    );

    await newClient.join(
      url: Uri.parse(
        credentials.roomUrl,
      ),
      token: credentials.token,
    );

    await newClient.updateInputs(
      inputs:
          const InputSettingsUpdate.set(
        camera:
            CameraInputSettingsUpdate.set(
          isEnabled:
              BoolUpdate.set(true),
        ),
        microphone:
            MicrophoneInputSettingsUpdate
                .set(
          isEnabled:
              BoolUpdate.set(true),
        ),
      ),
    );

    _handsPollTimer?.cancel();

    _handsPollTimer =
        Timer.periodic(
      const Duration(seconds: 2),
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

    client = null;

    notifyListeners();

    if (failedClient == null) {
      return;
    }

    try {
      await failedClient.leave();
    } catch (_) {}

    try {
      await failedClient.dispose();
    } catch (_) {}
  }

  Future<void> _pollRaisedHands() async {
    final id = liveClassId;

    if (id == null || client == null) {
      return;
    }

    try {
      final fresh =
          await _repository.getRaisedHands(
        id,
      );

      final previousIds = raisedHands
          .map((h) => h.userId)
          .toSet();

      final newlyRaised =
          fresh.where(
        (h) =>
            !previousIds.contains(
              h.userId,
            ) &&
            h.userId != _currentUserId,
      );

      for (final entry
          in newlyRaised) {
        appScaffoldMessengerKey
            .currentState
            ?.showSnackBar(
          SnackBar(
            content: Text(
              '${entry.userName} raised their hand ✋',
            ),
          ),
        );
      }

      raisedHands = fresh;

      myHandRaised = fresh.any(
        (h) =>
            h.userId ==
            _currentUserId,
      );

      notifyListeners();
    } catch (_) {
      // Ignore one failed poll.
    }
  }

  Future<void> toggleMyHand() async {
    final id = liveClassId;

    if (id == null ||
        client == null) {
      return;
    }

    try {
      myHandRaised =
          await _repository
              .toggleRaisedHand(id);

      notifyListeners();

      await _pollRaisedHands();
    } catch (_) {}
  }

  Future<void> lowerHand(
    String userId,
  ) async {
    final id = liveClassId;

    if (id == null ||
        !isOwner ||
        client == null) {
      return;
    }

    try {
      await _repository
          .toggleRaisedHand(
        id,
        userId: userId,
      );

      await _pollRaisedHands();
    } catch (_) {}
  }

  void _handleEvent(
    Event event,
    String? currentUserId,
  ) {
    event.maybeWhen(
      participantJoined:
          (participant) {
        final id =
            participant.info.userId ??
                '';

        final name =
            (participant.info.username
                        ?.isNotEmpty ??
                    false)
                ? participant
                    .info
                    .username!
                : 'Someone';

        participants[id] = name;

        notifyListeners();

        final isSelf =
            currentUserId != null &&
            id == currentUserId;

        if (isOwner && !isSelf) {
          appScaffoldMessengerKey
              .currentState
              ?.showSnackBar(
            SnackBar(
              content: Text(
                '$name joined the class',
              ),
            ),
          );
        }
      },

      participantLeft:
          (participant) {
        participants.remove(
          participant.info.userId ??
              '',
        );

        notifyListeners();
      },

      participantUpdated:
          (participant) {
        participants[
                participant.info.userId ??
                    ''] =
            participant.info
                    .username ??
                '';

        notifyListeners();
      },

      callStateUpdated:
          (stateData) {
        if (stateData.state ==
            CallState.left) {
          // If leave() is already running,
          // leave() itself owns cleanup.
          //
          // This prevents the Daily callback from
          // racing with the explicit leave operation.
          if (_leaveOperation ==
              null) {
            _reset();
          }
        }
      },

      inputsUpdated:
          (inputs) {
        micEnabled =
            inputs.microphone
                .isEnabled;

        cameraEnabled =
            inputs.camera
                .isEnabled;

        notifyListeners();
      },

      orElse: () {},
    );
  }

  // ------------------------------------------------------------
  // MINIMIZE / MAXIMIZE
  // ------------------------------------------------------------

  void minimize() {
    if (client == null) {
      return;
    }

    isMinimized = true;

    notifyListeners();
  }

  void maximize() {
    if (client == null) {
      return;
    }

    isMinimized = false;

    notifyListeners();
  }

  // ------------------------------------------------------------
  // MICROPHONE
  // ------------------------------------------------------------

  Future<void> toggleMic() async {
    final c = client;

    if (c == null ||
        _leaveOperation != null) {
      return;
    }

    final next =
        !micEnabled;

    try {
      await c.updateInputs(
        inputs:
            InputSettingsUpdate.set(
          microphone:
              MicrophoneInputSettingsUpdate
                  .set(
            isEnabled:
                BoolUpdate.set(next),
          ),
        ),
      );

      micEnabled = next;

      notifyListeners();
    } catch (_) {}
  }

  // ------------------------------------------------------------
  // CAMERA
  // ------------------------------------------------------------

  Future<void> toggleCamera() async {
    final c = client;

    if (c == null ||
        _leaveOperation != null) {
      return;
    }

    final next =
        !cameraEnabled;

    try {
      await c.updateInputs(
        inputs:
            InputSettingsUpdate.set(
          camera:
              CameraInputSettingsUpdate
                  .set(
            isEnabled:
                BoolUpdate.set(next),
          ),
        ),
      );

      cameraEnabled = next;

      notifyListeners();
    } catch (_) {}
  }

  // ------------------------------------------------------------
  // CAMERA FLIP
  // ------------------------------------------------------------

  Future<void> flipCamera() async {
    final c = client;

    if (c == null ||
        _leaveOperation != null) {
      return;
    }

    final nextFacing =
        usingFrontCamera
            ? MediaTrackFacingMode
                .environment
            : MediaTrackFacingMode.user;

    try {
      await c.setCameraFacingMode(
        facingMode: nextFacing,
      );

      usingFrontCamera =
          !usingFrontCamera;

      notifyListeners();
    } catch (_) {}
  }

  // ------------------------------------------------------------
  // REMOTE PARTICIPANTS
  // ------------------------------------------------------------

  Future<void>
      _updateRemoteParticipants(
    Map<String,
            RemoteParticipantUpdate>
        byId,
  ) async {
    final c = client;

    if (!isOwner ||
        c == null ||
        byId.isEmpty ||
        _leaveOperation != null) {
      return;
    }

    await c.updateRemoteParticipants(
      updates:
          RemoteParticipantSettingsUpdatesById
              .set(
        updates: {
          for (final entry
              in byId.entries)
            ParticipantId(entry.key):
                entry.value,
        },
      ),
    );
  }

  Future<void> muteParticipant(
    String participantId,
  ) async {
    await _updateRemoteParticipants({
      participantId:
          RemoteParticipantUpdate.set(
        inputsEnabled:
            RemoteInputsEnabledUpdate.set(
          microphone: false,
        ),
      ),
    });
  }

  Future<void>
      _setAllMicrophones(
    bool enabled,
  ) async {
    await _updateRemoteParticipants({
      for (final id
          in participants.keys)
        id:
            RemoteParticipantUpdate.set(
          inputsEnabled:
              RemoteInputsEnabledUpdate.set(
            microphone: enabled,
          ),
        ),
    });
  }

  Future<void>
      muteAllParticipants() async {
    await _setAllMicrophones(false);

    allMuted = true;

    notifyListeners();
  }

  Future<void>
      unmuteAllParticipants() async {
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

  // ------------------------------------------------------------
  // LEAVE
  // ------------------------------------------------------------

  Future<void> leave() {
    // IMPORTANT:
    //
    // If both the full screen and bubble call leave()
    // at almost the same time, return the SAME Future.
    //
    // This means Daily receives exactly one leave()
    // and exactly one dispose().
    final existing =
        _leaveOperation;

    if (existing != null) {
      return existing;
    }

    final operation =
        _performLeave();

    _leaveOperation =
        operation;

    operation.whenComplete(() {
      if (identical(
        _leaveOperation,
        operation,
      )) {
        _leaveOperation = null;
      }
    });

    return operation;
  }

  Future<void> _performLeave() async {
    final clientToLeave =
        client;

    // Stop Daily callbacks first.
    await _eventSubscription
        ?.cancel();

    _eventSubscription = null;

    // Stop REST polling.
    _handsPollTimer?.cancel();

    _handsPollTimer = null;

    // ----------------------------------------------------------
    // IMPORTANT:
    //
    // Detach the Daily client from the provider BEFORE calling
    // native leave/dispose.
    //
    // This makes both the full-screen VideoView and bubble stop
    // rendering the client.
    // ----------------------------------------------------------

    client = null;

    isMinimized = false;

    participants.clear();

    raisedHands = [];

    myHandRaised = false;

    notifyListeners();

    // Give Flutter a frame to remove all VideoViews before
    // destroying the native CallClient.
    try {
      await WidgetsBinding
          .instance.endOfFrame;
    } catch (_) {
      await Future<void>.delayed(
        Duration.zero,
      );
    }

    if (clientToLeave == null) {
      _reset();

      return;
    }

    // ----------------------------------------------------------
    // Native Daily shutdown
    // ----------------------------------------------------------

    try {
      await clientToLeave
          .leave();
    } catch (e, stackTrace) {
      debugPrint(
        'Daily client leave error: $e',
      );

      debugPrint(
        'Daily client leave stack trace:\n$stackTrace',
      );
    }

    try {
      await clientToLeave
          .dispose();
    } catch (e, stackTrace) {
      debugPrint(
        'Daily client dispose error: $e',
      );

      debugPrint(
        'Daily client dispose stack trace:\n$stackTrace',
      );
    }

    _reset();
  }

  // ------------------------------------------------------------
  // RESET
  // ------------------------------------------------------------

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
}

final dailyCallSessionProvider =
    ChangeNotifierProvider<
        DailyCallSession>(
  (ref) {
    return DailyCallSession(
      ref.watch(
        liveClassRepositoryProvider,
      ),
    );
  },
);
