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
  /// Teacher-facing toggle state — true after "Mute all" was last
  /// pressed, false after "Unmute all". This is just a UI hint for
  /// which label/icon to show next; it's not an enforced lock, since
  /// "Unmute all" resets everyone's mic to on but each participant can
  /// still freely mute/unmute themselves afterward (an open meeting),
  /// same as "Mute all" doesn't prevent someone from unmuting themselves.
  bool allMuted = false;
  final Map<String, String> participants = {};
  StreamSubscription<Event>? _eventSubscription;

  // Raise/lower hand — REST + polling, same reliable pattern as chat
  // rather than an unverified Daily "app message" mechanism.
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
    raisedHands = [];
    myHandRaised = false;
    _currentUserId = currentUserId;
    notifyListeners();

    // One automatic "warm" retry on top of the "cold" first attempt.
    // A first-ever join to a fresh room commonly hits transient network
    // negotiation delays (fresh DNS lookup, ICE/NAT traversal needing an
    // extra round, ordinary network jitter) that a near-immediate retry
    // typically doesn't — this mirrors what manually closing and
    // rejoining already did, just automatically, before ever surfacing
    // an error to the user. Each attempt gets a genuinely fresh
    // CallClient rather than retrying join() on one that may be left in
    // a half-open state from the failed attempt — safer than assuming
    // that's fine without being able to confirm it against Daily's docs.
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _attemptJoin(credentials, currentUserId);
        return; // success
      } catch (e) {
        final isLastAttempt = attempt == maxAttempts;
        await _teardownFailedClient();
        if (isLastAttempt) {
          _reset();
          rethrow;
        }
        // Brief pause before the automatic retry — not strictly required,
        // but avoids hammering straight back into whatever just failed.
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

  /// Cleans up a client left over from a failed join attempt, between
  /// retries. Deliberately lighter than _reset() — this keeps
  /// liveClassId/liveClassTitle/etc intact, since start() is still
  /// mid-flight and about to try again with a fresh client; _reset() is
  /// only called once every retry has been exhausted.
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

      // "Notification sent to everyone" — every participant polling
      // this sees the same new-hand snackbar, not just the teacher.
      for (final entry in newlyRaised) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('${entry.userName} raised their hand ✋')),
        );
      }

      raisedHands = fresh;
      myHandRaised = fresh.any((h) => h.userId == _currentUserId);
      notifyListeners();
    } catch (_) {
      // A single failed poll isn't worth surfacing an error for — same
      // reasoning as chat polling; it'll just pick up cleanly next tick.
    }
  }

  /// Raises or lowers the CURRENT user's own hand.
  Future<void> toggleMyHand() async {
    final id = liveClassId;
    if (id == null) return;
    try {
      myHandRaised = await _repository.toggleRaisedHand(id);
      notifyListeners();
      await _pollRaisedHands(); // refresh the full list immediately, don't wait for the next tick
    } catch (_) {
      // Leave state as it was — the next poll tick will reconcile
      // reality either way, so a failed toggle isn't destructive.
    }
  }

  /// Teacher-only (enforced server-side too): lowers someone ELSE's hand.
  Future<void> lowerHand(String userId) async {
    final id = liveClassId;
    if (id == null || !isOwner) return;
    try {
      await _repository.toggleRaisedHand(id, userId: userId);
      await _pollRaisedHands();
    } catch (_) {
      // Same reasoning as toggleMyHand() — next poll reconciles either way.
    }
  }

  void _handleEvent(Event event, String? currentUserId) {
    event.maybeWhen(participantJoined: (participant) {
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
      // Fires for ANY change to this client's own inputs — including
      // when the teacher remotely mutes this participant. Without this,
      // a muted student's own mic button would keep showing "unmuted"
      // even though they'd actually been silenced, since the remote
      // mute never otherwise touches this client's local micEnabled/
      // cameraEnabled state. NOTE: inputs.microphone.isEnabled and
      // inputs.camera.isEnabled are a pattern-based inference (matching
      // every other
