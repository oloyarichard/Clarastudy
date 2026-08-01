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
  
  /// See the note on this same method in the old DailyCallScreen — exact
  /// method names for device enumeration/switching aren't fully verified
  /// against daily_flutter's actual API surface.
  Future<void> flipCamera() async {
    final c = client;
    if (c == null) return;
    try {
      final devices = await c.getInputDevices();
      final cameras = devices.camera;
      if (cameras.length < 2) return;
      final nextFacing = usingFrontCamera ? 'environment' : 'user';
      final target = cameras.firstWhere(
        (d) => d.facingMode == nextFacing,
        orElse: () => cameras.first,
      );
      await c.updateInputs(
        inputs: InputSettingsUpdate.set(
          camera: CameraInputSettingsUpdate.set(
            isEnabled: const BoolUpdate.set(true),
            settings: CameraInputSettingsUpdate.set(deviceId: target.deviceId),
          ),
        ),
      );
      usingFrontCamera = !usingFrontCamera;
      notifyListeners();
    } catch (_) {
      // Surfaced to the user by the caller, which has a BuildContext.
      rethrow;
    }
  }
  
  /// Owner-only remote mute — same call as before, now callable from
  /// either the full-screen or minimized context since it lives here.
  Future<void> muteParticipant(String participantId) async {
    if (!isOwner) return;
    await client?.updateParticipants(
      participants: {
        participantId: ParticipantUpdate(
          inputsEnabled: ParticipantInputsUpdate(microphone: BoolUpdate.set(false)),
        ),
      },
    );
  }
  
  Future<void> leave() async {
    await client?.leave();
    await client?.dispose();
    _reset();
  }
  
  void _reset() {
    client = null;
    liveClassId = null;
    liveClassTitle = null;
    isOwner = false;
    isMinimized = false;
    participants.clear();
