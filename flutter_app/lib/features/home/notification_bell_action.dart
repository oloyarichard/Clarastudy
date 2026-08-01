import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/notification_providers.dart';

/// A bell icon with an unread-count badge, meant to sit in a dashboard's
/// AppBar actions. Pulled out of HomeShell's floating action button because
/// it was overlapping the teacher dashboard's own "New course" FAB — both
/// were pinned to the same bottom-right corner.
class NotificationBellAction extends ConsumerWidget {
  const NotificationBellAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final unread = unreadAsync.asData?.value ?? 0;

    return IconButton(
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
