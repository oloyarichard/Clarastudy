import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/chat_providers.dart';

class ChatRoomsScreen extends ConsumerWidget {
  const ChatRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(chatRoomsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(chatRoomsProvider),
        child: roomsAsync.when(
          data: (rooms) {
            if (rooms.isEmpty) {
              return const EmptyView(
                message: 'No conversations yet.',
                icon: Icons.chat_bubble_outline_rounded,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rooms.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final room = rooms[index];
                return Card(
                  child: ListTile(
                    leading: InitialsAvatar(name: room.name),
                    title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${room.participantIds.length} participants'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/chat/rooms/${room.id}', extra: room.name),
                  ),
                );
              },
            );
          },
          loading: () => const LoadingView(),
          error: (e, __) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(chatRoomsProvider),
          ),
        ),
      ),
    );
  }
}
