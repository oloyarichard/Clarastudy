import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

import '../../core/theme/app_theme.dart';
import '../../models/live_class_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_class_providers.dart';

/// Full-screen, in-app Jitsi Meet call for a live class.
///
/// - The teacher (or an admin) joins as a Jitsi *moderator* (granted via the
///   JWT from the backend), which unlocks Jitsi's native per-participant
///   mute/unmute and "mute everyone" controls in the participants panel.
/// - Jitsi's own built-in chat is disabled — the class uses the app's own
///   chat instead, reachable via the floating chat button, which reuses the
///   existing `/live-classes/:id/chat/` REST chat already in this app.
/// - Runs in immersive fullscreen (status/nav bars hidden) for the duration
///   of the call.
class JitsiMeetingScreen extends ConsumerStatefulWidget {
  const JitsiMeetingScreen({
    super.key,
    required this.liveClassId,
    required this.liveClassTitle,
    required this.credentials,
  });
  
  final String liveClassId;
  final String liveClassTitle;
  final JitsiCredentials credentials;
  
  @override
  ConsumerState<JitsiMeetingScreen> createState() => _JitsiMeetingScreenState();
}

class _JitsiMeetingScreenState extends ConsumerState<JitsiMeetingScreen> {
  final _jitsiMeet = JitsiMeet();
  bool _ended = false;
  
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }
  
  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
  
  Future<void> _join() async {
    final creds = widget.credentials;
    final user = ref.read(authProvider).user;
    
    final options = JitsiMeetConferenceOptions(
      serverURL: 'https://${creds.domain}',
      room: creds.room,
      token: creds.token,
      configOverrides: {
        // Teacher moderation lives entirely in Jitsi's native participants
        // panel once the JWT carries `moderator: true` — no extra UI needed
        // here for mute/unmute.
        'startWithAudioMuted': !creds.isModerator,
        'startWithVideoMuted': false,
        'prejoinPageEnabled': true,
        'disableChat': true, // use the app's own chat instead of Jitsi's
        'toolbarButtons': [
          'microphone',
          'camera',
          'closedcaptions',
          'desktop',
          'fullscreen',
          'fodeviceselection',
          'hangup',
          'profile',
          'chat', // harmless if disableChat is honoured; hidden otherwise
          'settings',
          'raisehand',
          'videoquality',
          'tileview',
          'participants-pane',
        ],
      },
      featureFlags: {
        'chat.enabled': false,
        'invite.enabled': false,
        'meeting-name.enabled': false,
        'pip.enabled': true,
        'fullscreen.enabled': true,
      },
      userInfo: JitsiMeetUserInfo(
        displayName: user?.displayName ?? 'Guest',
        email: user?.email,
      ),
    );
    
    final listener = JitsiMeetEventListener(
      conferenceTerminated: (url, error) => _leave(),
      readyToClose: () => _leave(),
    );
    
    await _jitsiMeet.join(options, listener);
  }
  
  void _leave() {
    if (_ended) return;
    _ended = true;
    if (mounted) Navigator.of(context).maybePop();
  }
  
  void _openAppChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LiveClassChatSheet(liveClassId: widget.liveClassId),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    // Jitsi's native view fills the screen behind this; this Scaffold just
    // supplies our own floating "app chat" affordance on top of it.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const SizedBox.expand(),
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              heroTag: 'live-class-chat-fab',
              backgroundColor: AppColors.primary,
              onPressed: _openAppChat,
              child: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's own live-class chat (REST-backed), shown as an overlay while
/// the Jitsi call is running instead of using Jitsi's built-in chat.
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
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
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
        );
      },
    );
  }
}
