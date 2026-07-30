import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_class_providers.dart';
import 'jitsi_meeting_screen.dart';

class LiveClassDetailScreen extends ConsumerStatefulWidget {
  const LiveClassDetailScreen({super.key, required this.liveClassId});
  
  final String liveClassId;
  
  @override
  ConsumerState<LiveClassDetailScreen> createState() => _LiveClassDetailScreenState();
}

class _LiveClassDetailScreenState extends ConsumerState<LiveClassDetailScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;
  bool _joining = false;
  
  Future<void> _joinCall(String title) async {
    setState(() => _joining = true);
    try {
      final creds = await ref
      .read(liveClassRepositoryProvider)
      .getJitsiCredentials(widget.liveClassId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => JitsiMeetingScreen(
            liveClassId: widget.liveClassId,
            liveClassTitle: title,
            credentials: creds,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not join the call.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }
  
  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
  
  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
      .read(liveClassRepositoryProvider)
      .sendLiveChat(liveClassId: widget.liveClassId, message: text);
      _messageController.clear();
      ref.invalidate(liveChatProvider(widget.liveClassId));
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not send message.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(liveClassesListProvider);
    final chatAsync = ref.watch(liveChatProvider(widget.liveClassId));
    final user = ref.watch(authProvider).user;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Live class')),
      body: classesAsync.when(
        data: (classes) {
          final matches = classes.where((c) => c.id == widget.liveClassId);
          final liveClass = matches.isEmpty ? null : matches.first;
          if (liveClass == null) {
            return const ErrorView(message: 'This live class could not be found.');
          }
          final formatter = DateFormat('EEEE, MMM d · h:mm a');
          
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                color: AppColors.cardLight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(liveClass.title,
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        ),
                        StatusChip(
                          label: liveClass.status == 'live' ? '● LIVE' : liveClass.status,
                          color: liveClass.isLive ? AppColors.error : AppColors.secondary,
                        ),
                      ],
                    ),
                    if (liveClass.description != null) ...[
                      const SizedBox(height: 8),
                      Text(liveClass.description!,
                           style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 12),
                    if (liveClass.scheduledAt != null)
                      Text(formatter.format(liveClass.scheduledAt!.toLocal()),
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: liveClass.isEnded
                        ? 'Class ended'
                      : (_joining ? 'Joining…' : 'Join room · ${liveClass.roomId}'),
                      icon: Icons.videocam_rounded,
                      onPressed: (liveClass.isEnded || _joining)
                      ? null
                      : () => _joinCall(liveClass.title),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: chatAsync.when(
                  data: (messages) {
                    if (messages.isEmpty) {
                      return const EmptyView(
                        message: 'No messages yet. Say hello!',
                        icon: Icons.chat_bubble_outline_rounded,
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMine = msg.userId == user?.id;
                        return Align(
                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.72,
                            ),
                            decoration: BoxDecoration(
                              color: isMine
                              ? AppColors.primary
                              : AppColors.cardLight,
                              borderRadius: BorderRadius.circular(14),
                              border: isMine ? null : Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              msg.message,
                              style: TextStyle(
                                color: isMine ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const LoadingView(),
                  error: (e, __) => ErrorView(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(liveChatProvider(widget.liveClassId)),
                  ),
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
                          controller: _messageController,
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
          );
        },
        loading: () => const LoadingView(),
        error: (e, __) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(liveClassesListProvider),
        ),
      ),
    );
  }
}
