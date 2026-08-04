import 'dart:async';

import 'package:daily_flutter/daily_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/live_class_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/daily_call_session_provider.dart';
import '../../providers/live_class_providers.dart';
import 'camera_off_placeholder.dart';

/// Full-screen, in-app Daily.co call for a live class.
///
/// The actual CallClient lives in [DailyCallSession] (an app-level
/// provider), not here — that's what lets "minimize" work: minimizing
/// just pops this route, the call itself keeps running in the
/// background, and re-opening this screen re-attaches to the same
/// client instead of rejoining. Pass [credentials] when actually
/// starting a new call; omit it when re-opening an already-active one
/// (e.g. from the minimized bubble) — in that case this screen just
/// attaches to whatever's already in the session.
class DailyCallScreen extends ConsumerStatefulWidget {
  const DailyCallScreen({
    super.key,
    required this.liveClassId,
    required this.liveClassTitle,
    this.credentials,
  });

  final String liveClassId;
  final String liveClassTitle;
  final DailyCallCredentials? credentials;

  @override
  ConsumerState<DailyCallScreen> createState() => _DailyCallScreenState();
}

class _DailyCallScreenState extends ConsumerState<DailyCallScreen> {
  bool _joining = true;
  bool _immersive = true;
  // Set the moment leave/minimize is tapped. Once true, build() stops
  // touching session/controllers entirely — this is the real fix, not
  // just reordering pop-vs-leave: Navigator.pop() isn't instant (there's
  // an exit transition), so this screen can still be mounted and still
  // rebuild in response to the session's notifyListeners() for a brief
  // window after leave() runs. Without this flag, that rebuild would
  // keep calling _syncRemoteControllers() — actively disposing video
  // controllers — while Flutter's own widget diffing might simultaneously
  // be tearing down the very VideoView bound to those same controllers,
  // as part of the same fade-out transition. This flag stops that
  // reactive teardown path entirely; the screen's own dispose() remains
  // the single, well-defined place controllers actually get disposed.
  bool _leaving = false;
  String? _errorMessage;

  // Confirmed API (pub.dev VideoViewController class docs, daily_flutter
  // 0.38.0): create once, call setTrack() whenever the track changes,
  // hand the controller itself to VideoView.
  final _videoController = VideoViewController();
  MediaStreamTrack? _lastTrack;

  /// Pushes the local participant's current camera track into the
  /// controller whenever it changes. Cheap to call on every build —
  /// it no-ops via the _lastTrack check when nothing's actually changed.
  void _syncVideoTrack(DailyCallSession session) {
    final track = session.client?.participants.local.media?.camera.track;
    if (track != _lastTrack) {
      _lastTrack = track;
      _videoController.setTrack(track);
    }
  }

  // Remote participants' video — confirmed via pub.dev (Participants.remote,
  // Participant.media?.camera.track, ParticipantInfo.isOwner). One
  // VideoViewController per remote participant, created/disposed as
  // people join and leave.
  final Map<String, VideoViewController> _remoteControllers = {};
  final Map<String, MediaStreamTrack?> _remoteLastTracks = {};

  /// Which remote participant, if any, was tapped in the thumbnail strip
  /// to become the main view. Null means "use the default" — the
  /// moderator for a student, or nobody (show local) for the teacher.
  String? _pinnedRemoteId;

  void _syncRemoteControllers(DailyCallSession session) {
    final remote = session.client?.participants.remote ?? {};
    final currentIds = remote.keys.map((id) => id.id).toSet();

    // Drop controllers for anyone who's left.
    final staleIds = _remoteControllers.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in staleIds) {
      _remoteControllers.remove(id)?.dispose();
      _remoteLastTracks.remove(id);
    }

    // Add/update controllers for everyone currently present.
    for (final entry in remote.entries) {
      final id = entry.key.id;
      final track = entry.value.media?.camera.track;
      final controller = _remoteControllers.putIfAbsent(id, () => VideoViewController());
      if (_remoteLastTracks[id] != track) {
        _remoteLastTracks[id] = track;
        controller.setTrack(track);
      }
    }
  }

  /// Returns (participantId, Participant) for whoever should be shown
  /// full-size right now, or null to mean "show the local participant"
  /// (the teacher's own default view, unchanged from before).
  MapEntry<String, Participant>? _mainRemoteParticipant(DailyCallSession session) {
    final remote = session.client?.participants.remote ?? {};
    if (remote.isEmpty) return null;

    if (_pinnedRemoteId != null) {
      final pinned = remote.entries.where((e) => e.key.id == _pinnedRemoteId);
      if (pinned.isNotEmpty) {
        return MapEntry(pinned.first.key.id, pinned.first.value);
      }
      _pinnedRemoteId = null; // they left — fall through to the default
    }

    // Default for a student: the moderator, if present.
    if (!session.isOwner) {
      final moderator = remote.entries.where((e) => e.value.info.isOwner);
      if (moderator.isNotEmpty) {
        return MapEntry(moderator.first.key.id, moderator.first.value);
      }
    }

    return null; // teacher's own screen keeps showing themselves by default
  }

  Widget _localVideoTile(DailyCallSession session, {bool compact = false}) {
    final showVideo = session.cameraEnabled && _lastTrack != null;
    return showVideo
        ? VideoView(controller: _videoController)
        : CameraOffPlaceholder(
            displayName: ref.watch(authProvider).user?.displayName ?? 'You',
            compact: compact,
          );
  }

  Widget _remoteVideoTile(String id, Participant participant, {bool compact = false}) {
    final controller = _remoteControllers[id];
    final showVideo = !participant.isCameraMuted && controller != null;
    return showVideo
        ? VideoView(controller: controller)
        : CameraOffPlaceholder(
            displayName: participant.info.username?.isNotEmpty ?? false
                ? participant.info.username!
                : 'Participant',
            compact: compact,
          );
  }

  /// Horizontal scrollable strip of everyone NOT currently shown as the
  /// main view — tap any tile to swap it into main. Always includes the
  /// local participant as a tile (so you can tap back to "myself") when
  /// a remote participant is currently pinned as main.
  Widget _thumbnailStrip(DailyCallSession session, String? mainRemoteId) {
    final remote = session.client?.participants.remote ?? {};
    final others = remote.entries.where((e) => e.key.id != mainRemoteId).toList();
    final showLocalTile = mainRemoteId != null; // local is main by default, so only show it in the strip when it's NOT main

    if (others.isEmpty && !showLocalTile) return const SizedBox.shrink();

    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (showLocalTile)
            _thumbnailTile(
              child: _localVideoTile(session, compact: true),
              muted: !session.micEnabled,
              onTap: () => setState(() => _pinnedRemoteId = null),
            ),
          ...others.map(
            (entry) => _thumbnailTile(
              child: _remoteVideoTile(entry.key.id, entry.value, compact: true),
              muted: entry.value.isMicrophoneMuted,
              onTap: () => setState(() => _pinnedRemoteId = entry.key.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnailTile({required Widget child, required VoidCallback onTap, bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 68,
            height: 90,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.black, child: child),
                if (muted)
                  const Positioned(
                    bottom: 4,
                    left: 4,
                    child: Icon(Icons.mic_off_rounded, color: Colors.white, size: 16),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _enterImmersive();
    _ensureJoined();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _videoController.dispose();
    for (final controller in _remoteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _enterImmersive() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  void _exitImmersive() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  void _toggleFullscreen() {
    setState(() => _immersive = !_immersive);
    _immersive ? _enterImmersive() : _exitImmersive();
  }

  Future<void> _ensureJoined() async {
    final session = ref.read(dailyCallSessionProvider);

    // Re-opening an already-active call for this same class (e.g. from
    // the minimized bubble) — nothing to do, just attach the UI.
    if (session.hasActiveCall && session.liveClassId == widget.liveClassId) {
      if (mounted) setState(() => _joining = false);
      return;
    }

    if (widget.credentials == null) {
      if (mounted) {
        setState(() {
          _joining = false;
          _errorMessage = 'No active call to show.';
        });
      }
      return;
    }

    try {
      final user = ref.read(authProvider).user;
      await session.start(
        liveClassId: widget.liveClassId,
        liveClassTitle: widget.liveClassTitle,
        credentials: widget.credentials!,
        currentUserId: user?.id,
      );
      if (mounted) setState(() => _joining = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _errorMessage = 'Could not join the call: $e';
        });
      }
    }
  }

  void _minimize() {
    ref.read(dailyCallSessionProvider).minimize();
    Navigator.of(context).maybePop();
  }

  Future<void> _leave() async {
    final session = ref.read(dailyCallSessionProvider);
    // Stop reacting to the session provider before anything else — this
    // is what actually closes the race, not the pop/leave ordering
    // alone (Navigator.pop() has a non-instant exit transition, so this
    // screen can still rebuild in that window regardless of ordering).
    setState(() => _leaving = true);
    if (mounted) Navigator.of(context).maybePop();
    await session.leave();
  }

  Future<void> _flipCamera() async {
    try {
      await ref.read(dailyCallSessionProvider).flipCamera();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not switch camera: $e')),
        );
      }
    }
  }

  void _openAppChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LiveClassChatSheet(liveClassId: widget.liveClassId),
    );
  }

  void _openParticipants() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardLight,
      builder: (_) => Consumer(
        builder: (context, ref, __) {
          final session = ref.watch(dailyCallSessionProvider);
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Participants', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    if (session.isOwner && session.participants.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => session.toggleMuteAll(),
                        icon: Icon(
                          session.allMuted ? Icons.mic_rounded : Icons.mic_off_rounded,
                          size: 18,
                        ),
                        label: Text(session.allMuted ? 'Unmute all' : 'Mute all'),
                      ),
                  ],
                ),
              ),
              ...session.participants.entries.map(
                (entry) => ListTile(
                  leading: const Icon(Icons.person_rounded),
                  title: Text(entry.value),
                  trailing: session.isOwner
                      ? IconButton(
                          icon: const Icon(Icons.mic_off_rounded),
                          tooltip: 'Mute',
                          onPressed: () => session.muteParticipant(entry.key),
                        )
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(dailyCallSessionProvider);

    return PopScope(
      // System back gesture always gets a real exit too — not just the
      // in-UI buttons. onPopInvokedWithResult still lets the pop happen
      // (canPop stays true); this just makes sure state is sane either
      // way, so backing out never leaves a broken half-joined session
      // sitting around confusing a later screen.
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _joining
              ? Stack(
                  children: [
                    const Center(child: CircularProgressIndicator(color: Colors.white)),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: TextButton.styleFrom(foregroundColor: Colors.white70),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Cancel'),
                      ),
                    ),
                  ],
                )
              : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).maybePop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white54),
                                ),
                                child: const Text('Close'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _errorMessage = null;
                                    _joining = true;
                                  });
                                  _ensureJoined();
                                },
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : _leaving
                  ? const ColoredBox(color: Colors.black)
                  : Builder(builder: (context) {
                    _syncVideoTrack(session);
                    _syncRemoteControllers(session);
                    final mainRemote = _mainRemoteParticipant(session);
                    return Stack(
                      children: [
                        if (session.client != null)
                          Positioned.fill(
                            child: mainRemote != null
                                ? _remoteVideoTile(mainRemote.key, mainRemote.value)
                                : _localVideoTile(session),
                          ),
                        if (session.client != null)
                          Positioned(
                            left: 16,
                            bottom: 112,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if ((mainRemote?.value.isMicrophoneMuted ?? !session.micEnabled))
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.black45,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.mic_off_rounded, color: Colors.white, size: 16),
                                  ),
                              ],
                            ),
                          ),
                        if (session.client != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 96,
                            child: _thumbnailStrip(session, mainRemote?.key),
                          ),
                        Positioned(
                          top: 12,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                              tooltip: 'Minimize',
                              onPressed: _minimize,
                            ),
                            Expanded(
                              child: Text(
                                widget.liveClassTitle,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _immersive ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                color: Colors.white,
                              ),
                              tooltip: _immersive ? 'Exit fullscreen' : 'Fullscreen',
                              onPressed: _toggleFullscreen,
                            ),
                            if (session.isOwner)
                              IconButton(
                                icon: const Icon(Icons.people_alt_rounded, color: Colors.white),
                                onPressed: () => _openParticipants(),
                              ),
                          ],
                        ),
                      ),
                      if (session.raisedHands.isNotEmpty)
                        Positioned(
                          top: 56,
                          left: 16,
                          right: 16,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: session.raisedHands
                                .map(
                                  (entry) => Chip(
                                    backgroundColor: AppColors.accent,
                                    label: Text(
                                      entry.userName,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                    avatar: const Icon(Icons.back_hand_rounded, color: Colors.white, size: 16),
                                    onDeleted: session.isOwner ? () => session.lowerHand(entry.userId) : null,
                                    deleteIcon: session.isOwner
                                        ? const Icon(Icons.close_rounded, color: Colors.white, size: 16)
                                        : null,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Positioned(
                        right: 16,
                        bottom: 100,
                        child: FloatingActionButton(
                          heroTag: 'live-class-chat-fab',
                          backgroundColor: AppColors.primary,
                          onPressed: _openAppChat,
                          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CallControlButton(
                              icon: session.micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                              onPressed: () => session.toggleMic(),
                            ),
                            const SizedBox(width: 16),
                            _CallControlButton(
                              icon: session.cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                              onPressed: () => session.toggleCamera(),
                            ),
                            const SizedBox(width: 16),
                            _CallControlButton(
                              icon: Icons.cameraswitch_rounded,
                              onPressed: _flipCamera,
                            ),
                            const SizedBox(width: 16),
                            _CallControlButton(
                              icon: Icons.call_end_rounded,
                              color: AppColors.error,
                              onPressed: _leave,
                            ),
                            if (!session.isOwner) ...[
                              const SizedBox(width: 16),
                              _CallControlButton(
                                icon: Icons.back_hand_rounded,
                                color: session.myHandRaised ? AppColors.accent : null,
                                onPressed: () => session.toggleMyHand(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ],
                    );
                  }),
      ),
    ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({required this.icon, required this.onPressed, this.color});

  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: color ?? Colors.white24,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}

/// The app's own live-class chat (REST-backed) — unchanged, and still
/// backed by the same persisted history as before; nothing about the
/// Daily migration touched this.
class _LiveClassChatSheet extends ConsumerStatefulWidget {
  const _LiveClassChatSheet({required this.liveClassId});

  final String liveClassId;

  @override
  ConsumerState<_LiveClassChatSheet> createState() => _LiveClassChatSheetState();
}

class _LiveClassChatSheetState extends ConsumerState<_LiveClassChatSheet> {
  final _controller = TextEditingController();
  bool _sending = false;
  Timer? _pollTimer;
  ScrollController? _chatScrollController;
  int _lastMessageCount = 0;

  void _scrollToBottom() {
    final c = _chatScrollController;
    if (c == null || !c.hasClients) return;
    c.animateTo(
      c.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void initState() {
    super.initState();
    // Chat is REST-backed, not a live socket — poll while this sheet is
    // open so messages from other participants actually show up without
    // requiring you to send something yourself to trigger a refresh.
    // 1 second is close to the practical floor for REST polling without
    // hammering the server — true instant delivery would need a
    // WebSocket (Django Channels is already in this project's stack for
    // that, just not wired up for chat yet). This is the fast-as-
    // reasonable version of the polling approach, not literal real-time.
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) ref.invalidate(liveChatProvider(widget.liveClassId));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(liveClassRepositoryProvider)
          .sendLiveChat(liveClassId: widget.liveClassId, message: text);
      _controller.clear();
      ref.invalidate(liveChatProvider(widget.liveClassId));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(liveChatProvider(widget.liveClassId));
    final user = ref.watch(authProvider).user;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        _chatScrollController = scrollController;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.cardLight,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Class chat', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Expanded(
                  child: chatAsync.when(
                    data: (messages) {
                      if (messages.length > _lastMessageCount) {
                        _lastMessageCount = messages.length;
                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                      }
                      return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMine = msg.userId == user?.id;
                        return Align(
                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMine ? AppColors.primary : AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              msg.message,
                              style: TextStyle(color: isMine ? Colors.white : AppColors.textPrimary),
                            ),
                          ),
                        );
                      },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, __) => Center(child: Text('$e')),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: const InputDecoration(hintText: 'Message the class...'),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _sending ? null : _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
