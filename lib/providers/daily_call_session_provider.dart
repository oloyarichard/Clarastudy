import 'dart:async';

import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/global_keys.dart';
import '../data/live_class_repository.dart';
import '../models/live_class_models.dart';
import 'core_providers.dart';

/// Holds the active Daily call's live state at the APP level, not inside
/// DailyCallScreen's local state. This is what makes "minimize" actually
/// work: minimizing just pops the full-screen route, but the CallClient
/// living here is untouched and keeps the call running. Re-opening the
/// full-screen view re-attaches to this same client instead of joining
/// again from scratch.
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
  
  bool get hasActiveCall => client != null;
  
  Future<void> start({
    required String liveClassId,
    required String liveClassTitle,
    required DailyCallCredentials credentials,
    required String? currentUserId,
  }) async {
    if (client != null) {
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
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
  }
  
  Future<void> _attemptJoin(DailyCallCredentials credentials, String? currentUserId) async {
    final newClient = await CallClient.create();
    client = newClient;
    
    _eventSubscription = newClient.events.listen((event) => _handleEvent(event, currentUserId));
    
    await newClient.join(
      url: Uri.parse(credentials.roomUrl),
      token: credentials.token,
    );
    await newClient.updateInputs(
      inputs: const InputSettingsUpdate.set(
        camera: CameraInputSettingsUpdate.set(isEnabled: BoolUpdate.set(true)),
        microphone: MicrophoneInputSettingsUpdate.set(isEnabled: BoolUpdate.set(true)),
      ),
    );
    _handsPollTimer?.cancel();
    _handsPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollRaisedHands());
    notifyListeners();
  }
  
  Future<void> _teardownFailedClient() async {
    await _eventSubscription?.cancel();
    await client?.leave();
    await client?.dispose();
    client = null;
  }
  
  Future<void> _pollRaisedHands() async {
    final id = liveClassId;
    if (id == null) return;
    try {
      final fresh = await _repository.getRaisedHands(id);
      final previousIds = raisedHands.map((h) => h.userId).toSet();
      final newlyRaised = fresh.where((h) => !previousIds.contains(h.userId) && h.userId != _currentUserId);
      
      for (final entry in newlyRaised) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('${entry.userName} raised their hand ✋')),
        );
      }
      
      raisedHands = fresh;
      myHandRaised = fresh.any((h) => h.userId == _currentUserId);
      notifyListeners();
    } catch (_) {}
  }
  
  Future<void> toggleMyHand() async {
    final id = liveClassId;
    if (id == null) return;
    try {
      myHandRaised = await _repository.toggleRaisedHand(id);
      notifyListeners();
      await _pollRaisedHands();
    } catch (_) {}
  }
  
  Future<void> lowerHand(String userId) async {
    final id = liveClassId;
    if (id == null || !isOwner) return;
    try {
      await _repository.toggleRaisedHand(id, userId: userId);
      await _pollRaisedHands();
    } catch (_) {}
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
      inputsUpdated: (inputs) {
        micEnabled = inputs.microphone.isEnabled;
        cameraEnabled = inputs.camera.isEnabled;
        notifyListeners();
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
  
  Future<void> flipCamera() async {
    final c = client;
    if (c == null) return;
    final nextFacing =
    usingFrontCamera ? MediaTrackFacingMode.environment : MediaTrackFacingMode.user;
    await c.setCameraFacingMode(facingMode: nextFacing);
    usingFrontCamera = !usingFrontCamera;
    notifyListeners();
  }
  
  Future<void> _updateRemoteParticipants(Map<String, RemoteParticipantUpdate> byId) async {
    if (!isOwner || client == null || byId.isEmpty) return;
    await client!.updateRemoteParticipants(
      updates: RemoteParticipantSettingsUpdatesById.set(
        updates: {for (final entry in byId.entries) ParticipantId(entry.key): entry.value},
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
  
  Future<void> leave() async {
    await _eventSubscription?.cancel();
    _handsPollTimer?.cancel();
    final clientToDispose = client;
    _reset();
    
    await clientToDispose?.leave();
    await clientToDispose?.dispose();
  }
  
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

final dailyCallSessionProvider = ChangeNotifierProvider<DailyCallSession>((ref) {
  return DailyCallSession(ref.watch(liveClassRepositoryProvider));
});
