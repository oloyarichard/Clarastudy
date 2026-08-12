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

  List<RaisedHandEntry> raisedHands = [];
  bool myHandRaised = false;

  Timer? _handsPollTimer;
  String? _currentUserId;

  // ------------------------------------------------------------
  // Native Daily lifecycle protection
  // ------------------------------------------------------------

  bool _leaving = false;
  bool _clientJoined = false;

  bool get hasActiveCall => client != null;

  // ------------------------------------------------------------
  // START / JOIN
  // ------------------------------------------------------------

  Future<void> start({
    required String liveClassId,
    required String liveClassTitle,
    required DailyCallCredentials credentials,
    required String? currentUserId,
  }) async {
    if (_leaving) {
      return;
    }

    // If another call exists, clean it up first.
    if (client != null) {
      await leave();
    }

    if (_leaving) {
      return;
    }

    this.liveClassId = liveClassId;
    this.liveClassTitle = liveClassTitle;

    isOwner = credentials.isOwner;
    isMinimized = false;

    participants.clear();

    micEnabled = true;
    cameraEnabled = true;
    usingFrontCamera = true;
    allMuted = false;

    raisedHands = [];
    myHandRaised = false;

    _currentUserId = currentUserId;

    notifyListeners();

    const maxAttempts = 2;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_leaving) {
        return;
      }

      try {
        await _attemptJoin(
          credentials,
          currentUserId,
        );

        return;
      } catch (e, stackTrace) {
        debugPrint(
          'Daily join attempt $attempt failed: $e',
        );

        debugPrint(
          'Daily join stack trace:\n$stackTrace',
        );

        await _teardownFailedClient();

        if (attempt == maxAttempts) {
          _reset();

          rethrow;
        }

        // Give the native/network stack a short moment to settle
        // before creating a completely new CallClient.
        await Future.delayed(
          const Duration(milliseconds: 800),
        );
      }
    }
  }

  Future<void> _attemptJoin(
    DailyCallCredentials credentials,
    String? currentUserId,
  ) async {
    CallClient? newClient;

    try {
      // IMPORTANT:
      // Every attempt gets a completely fresh CallClient.
      newClient = await CallClient.create();

      if (_leaving) {
        await newClient.dispose();
        return;
      }

      client = newClient;
      _clientJoined = false;

      _eventSubscription = newClient.events.listen(
        (event) {
          _handleEvent(
            event,
            currentUserId,
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            'Daily event error: $error',
          );

          debugPrint(
            'Daily event stack trace:\n$stackTrace',
          );
        },
      );

      await newClient.join(
        url: Uri.parse(credentials.roomUrl),
        token: credentials.token,
      );

      // VERY IMPORTANT:
      // Only mark the client as joined after join() succeeds.
      _clientJoined = true;

      if (_leaving) {
        await _safeLeaveAndDispose(newClient);
        return;
      }

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

      if (_leaving) {
        return;
      }

      _handsPollTimer?.cancel();

      _handsPollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) {
          if (!_leaving && client != null) {
            _pollRaisedHands();
          }
        },
      );

      notifyListeners();
    } catch (e) {
      // The caller will perform retry cleanup.
      rethrow;
    }
  }

  // ------------------------------------------------------------
  // FAILED JOIN CLEANUP
  // ------------------------------------------------------------

  Future<void> _teardownFailedClient() async {
    final failedClient = client;

    client = null;

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    if (failedClient == null) {
      _clientJoined = false;
      return;
    }

    // DO NOT call leave() if join() never succeeded.
    //
    // This is important for the first-attempt crash. A CallClient
    // that failed during native initialization may not be in a state
    // where Daily's leave() is safe to call.

    if (_clientJoined) {
      try {
        await failedClient.leave();
      } catch (e, stackTrace) {
        debugPrint(
          'Failed-client leave error: $e',
        );

        debugPrint(
          'Failed-client leave stack trace:\n$stackTrace',
        );
      }
    }

    try {
      await failedClient.dispose();
    } catch (e, stackTrace) {
      debugPrint(
        'Failed-client dispose error: $e',
      );

      debugPrint(
        'Failed-client dispose stack trace:\n$stackTrace',
      );
    }

    _clientJoined = false;
  }

  // ------------------------------------------------------------
  // SAFE NATIVE CLEANUP
  // ------------------------------------------------------------

  Future<void> _safeLeaveAndDispose(
    CallClient callClient,
  ) async {
    if (_clientJoined) {
      try {
        await callClient.leave();
      } catch (e, stackTrace) {
        debugPrint(
          'Daily leave error: $e',
        );

        debugPrint(
          'Daily leave stack trace:\n$stackTrace',
        );
      }
    }

    try {
      await callClient.dispose();
    } catch (e, stackTrace) {
      debugPrint(
        'Daily dispose error: $e',
      );

      debugPrint(
        'Daily dispose stack trace:\n$stackTrace',
      );
    }

    _clientJoined = false;
  }

  // ------------------------------------------------------------
  // RAISED HANDS
  // ------------------------------------------------------------

  Future<void> _pollRaisedHands() async {
    final id = liveClassId;

    if (id == null || _leaving) {
      return;
    }

    try {
      final fresh = await _repository.getRaisedHands(id);

      if (_leaving) {
        return;
      }

      final previousIds =
          raisedHands.map((h) => h.userId).toSet();

      final newlyRaised = fresh.where(
        (h) =>
            !previousIds.contains(h.userId) &&
            h.userId != _currentUserId,
      );

      for (final entry in newlyRaised) {
        appScaffoldMessengerKey.currentState
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
        (h) => h.userId == _currentUserId,
      );

      notifyListeners();
    } catch (_) {
      // Ignore individual polling failures.
    }
  }

  Future<void> toggleMyHand() async {
    final id = liveClassId;

    if (id == null || _leaving) {
      return;
    }

    try {
      myHandRaised =
          await _repository.toggleRaisedHand(id);

      if (_leaving) {
        return;
      }

      notifyListeners();

      await _pollRaisedHands();
    } catch (_) {}
  }

  Future<void> lowerHand(String userId) async {
    final id = liveClassId;

    if (id == null || !isOwner || _leaving) {
      return;
    }

    try {
      await _repository.toggleRaisedHand(
        id,
        userId: userId,
      );

      await _pollRaisedHands();
    } catch (_) {}
  }

  // ------------------------------------------------------------
  // DAILY EVENTS
  // ------------------------------------------------------------

  void _handleEvent(
    Event event,
    String? currentUserId,
  ) {
    // Once leave starts, ignore late native callbacks.
    //
    // This is important because Daily can emit events while
    // leave()/dispose() is running.
    if (_leaving) {
      return;
    }

    event.maybeWhen(
      participantJoined: (participant) {
        if (_leaving) return;

        final id = participant.info.userId ?? '';

        final name =
            (participant.info.username?.isNotEmpty ?? false)
                ? participant.info.username!
                : 'Someone';

        participants[id] = name;

        notifyListeners();

        final isSelf =
            currentUserId != null &&
            id == currentUserId;

        if (isOwner && !isSelf) {
          appScaffoldMessengerKey.currentState
              ?.showSnackBar(
            SnackBar(
              content: Text(
                '$name joined the class',
              ),
            ),
          );
        }
      },

      participantLeft: (participant) {
        if (_leaving) return;

        participants.remove(
          participant.info.userId ?? '',
        );

        notifyListeners();
      },

      participantUpdated: (participant) {
        if (_leaving) return;

        participants[
            participant.info.userId ?? ''] =
            participant.info.username ?? '';

        notifyListeners();
      },

      callStateUpdated: (stateData) {
        if (_leaving) {
          return;
        }

        if (stateData.state == CallState.left) {
          _handleRemoteLeave();
        }
      },

      inputsUpdated: (inputs) {
        if (_leaving) {
          return;
        }

        micEnabled =
            inputs.microphone.isEnabled;

        cameraEnabled =
            inputs.camera.isEnabled;

        notifyListeners();
      },

      orElse: () {},
    );
  }

  void _handleRemoteLeave() {
    if (_leaving) {
      return;
    }

    _eventSubscription?.cancel();
    _eventSubscription = null;

    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    client = null;
    _clientJoined = false;

    _reset(
      preserveClient: true,
    );
  }

  // ------------------------------------------------------------
  // MINIMIZE / MAXIMIZE
  // ------------------------------------------------------------

  void minimize() {
    if (_leaving || client == null) {
      return;
    }

    isMinimized = true;

    notifyListeners();
  }

  void maximize() {
    if (_leaving || client == null) {
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

    if (c == null || _leaving) {
      return;
    }

    final nextValue = !micEnabled;

    try {
      await c.updateInputs(
        inputs: InputSettingsUpdate.set(
          microphone:
              MicrophoneInputSettingsUpdate.set(
            isEnabled:
                BoolUpdate.set(nextValue),
          ),
        ),
      );

      if (_leaving) {
        return;
      }

      micEnabled = nextValue;

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Toggle microphone error: $e',
      );
    }
  }

  // ------------------------------------------------------------
  // CAMERA
  // ------------------------------------------------------------

  Future<void> toggleCamera() async {
    final c = client;

    if (c == null || _leaving) {
      return;
    }

    final nextValue = !cameraEnabled;

    try {
      await c.updateInputs(
        inputs: InputSettingsUpdate.set(
          camera:
              CameraInputSettingsUpdate.set(
            isEnabled:
                BoolUpdate.set(nextValue),
          ),
        ),
      );

      if (_leaving) {
        return;
      }

      cameraEnabled = nextValue;

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Toggle camera error: $e',
      );
    }
  }

  // ------------------------------------------------------------
  // FLIP CAMERA
  // ------------------------------------------------------------

  Future<void> flipCamera() async {
    final c = client;

    if (c == null || _leaving) {
      return;
    }

    final nextFacing =
        usingFrontCamera
            ? MediaTrackFacingMode.environment
            : MediaTrackFacingMode.user;

    try {
      await c.setCameraFacingMode(
        facingMode: nextFacing,
      );

      if (_leaving) {
        return;
      }

      usingFrontCamera = !usingFrontCamera;

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Flip camera error: $e',
      );
    }
  }

  // ------------------------------------------------------------
  // REMOTE PARTICIPANTS
  // ------------------------------------------------------------

  Future<void> _updateRemoteParticipants(
    Map<String, RemoteParticipantUpdate> byId,
  ) async {
    final c = client;

    if (!isOwner ||
        c == null ||
        byId.isEmpty ||
        _leaving) {
      return;
    }

    await c.updateRemoteParticipants(
      updates:
          RemoteParticipantSettingsUpdatesById.set(
        updates: {
          for (final entry in byId.entries)
            ParticipantId(entry.key): entry.value,
        },
      ),
    );
  }

  Future<void> muteParticipant(
    String participantId,
  ) async {
    if (_leaving) {
      return;
    }

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

  Future<void> _setAllMicrophones(
    bool enabled,
  ) async {
    if (_leaving) {
      return;
    }

    await _updateRemoteParticipants({
      for (final id in participants.keys)
        id: RemoteParticipantUpdate.set(
          inputsEnabled:
              RemoteInputsEnabledUpdate.set(
            microphone: enabled,
          ),
        ),
    });
  }

  Future<void> muteAllParticipants() async {
    if (_leaving) {
      return;
    }

    await _setAllMicrophones(false);

    if (_leaving) {
      return;
    }

    allMuted = true;

    notifyListeners();
  }

  Future<void> unmuteAllParticipants() async {
    if (_leaving) {
      return;
    }

    await _setAllMicrophones(true);

    if (_leaving) {
      return;
    }

    allMuted = false;

    notifyListeners();
  }

  Future<void> toggleMuteAll() async {
    if (_leaving) {
      return;
    }

    if (allMuted) {
      await unmuteAllParticipants();
    } else {
      await muteAllParticipants();
    }
  }

  // ------------------------------------------------------------
  // LEAVE
  // ------------------------------------------------------------

  Future<void> leave() async {
    // Prevent the main screen and bubble from both starting
    // native teardown at the same time.
    if (_leaving) {
      return;
    }

    _leaving = true;

    // Capture the client BEFORE clearing state.
    final oldClient = client;

    // Stop all Dart-side callbacks first.
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    _handsPollTimer?.cancel();
    _handsPollTimer = null;

    // Detach the client from Flutter BEFORE touching the native
    // Daily client. This causes VideoViews in both the full screen
    // and bubble to disappear before native resources are destroyed.
    client = null;

    notifyListeners();

    // Give Flutter a chance to rebuild and remove VideoViews.
    await Future<void>.delayed(
      const Duration(milliseconds: 50),
    );

    if (oldClient != null) {
      // Only call leave() when join() actually succeeded.
      if (_clientJoined) {
        try {
          await oldClient.leave();
        } catch (e, stackTrace) {
          debugPrint(
            'Daily leave error: $e',
          );

          debugPrint(
            'Daily leave stack trace:\n$stackTrace',
          );
        }
      }

      try {
        await oldClient.dispose();
      } catch (e, stackTrace) {
        debugPrint(
          'Daily dispose error: $e',
        );

        debugPrint(
          'Daily dispose stack trace:\n$stackTrace',
        );
      }
    }

    _clientJoined = false;

    _reset(
      preserveClient: true,
    );

    _leaving = false;

    notifyListeners();
  }

  // ------------------------------------------------------------
  // RESET
  // ------------------------------------------------------------

  void _reset({
    bool preserveClient = false,
  }) {
    if (!preserveClient) {
      client = null;
    }

    liveClassId = null;
    liveClassTitle = null;

    isOwner = false;
    isMinimized = false;

    micEnabled = true;
    cameraEnabled = true;
    usingFrontCamera = true;

    allMuted = false;

    raisedHands = [];
    myHandRaised = false;

    _currentUserId = null;

    participants.clear();

    _clientJoined = false;

    notifyListeners();
  }
}

final dailyCallSessionProvider =
    ChangeNotifierProvider<DailyCallSession>(
  (ref) {
    return DailyCallSession(
      ref.watch(liveClassRepositoryProvider),
    );
  },
);
