import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_providers.dart';
import '../../providers/core_providers.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.roomId, required this.roomName});

  final String roomId;
  final String roomName;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;

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
      await ref.read(chatRepositoryProvider).sendMessage(roomId: widget.roomId, content: text);
      _messageController.clear();
      ref.invalidate(chatMessagesProvider(widget.roomId));
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
    final messagesAsync = ref.watch(chatMessagesProvider(widget.roomId));
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(title: Text(widget.roomName)),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(chatMessagesProvider(widget.roomId)),
              child: messagesAsync.when(
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
                      final isMine = msg.senderId == user?.id;
                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72,
                          ),
                          decoration: BoxDecoration(
                            color: isMine ? AppColors.primary : AppColors.cardLight,
                            borderRadius: BorderRadius.circular(14),
                            border: isMine ? null : Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            msg.content,
                            style: TextStyle(color: isMine ? Colors.white : AppColors.textPrimary),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const LoadingView(),
                error: (e, __) => ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(chatMessagesProvider(widget.roomId)),
                ),
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
                      decoration: const InputDecoration(hintText: 'Type a message...'),
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
  }
}
