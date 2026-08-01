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
    await ref.read(dailyCallSessionProvider).leave();
    if (mounted) Navigator.of(context).maybePop();
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
  
  void _openParticipants(DailyCallSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardLight,
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Participants', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(dailyCallSessionProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _joining
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : _errorMessage != null
        ? Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        )
        : Builder(builder: (context) {
          _syncVideoTrack(session);
          final showVideo = session.cameraEnabled && _lastTrack != null;
          return Stack(
            children: [
              if (session.client != null)
                Positioned.fill(
                  child: showVideo
                  ? VideoView(controller: _videoController)
                  : CameraOffPlaceholder(
                    displayName: ref.watch(authProvider).user?.displayName ?? 'You',
                  ),
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
                          onPressed: () => _openParticipants(session),
                        ),
                    ],
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
                    ],
                  ),
                ),
            ],
          );
        }),
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
  
  @override
  void dispose() {
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
                    data: (messages) => ListView.builder(
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
                    ),
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
