import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/notification_providers.dart';

/// A bell icon with an unread-count badge, meant to sit in a dashboard's
/// AppBar actions. Pulled out of HomeShell's floating action button because
/// it was overlapping the teacher dashboard's own "New course" FAB — both
/// were pinned to the same bottom-right corner.
///
/// Polls every few seconds while mounted — the underlying provider was a
/// plain one-shot fetch, so the badge count would only ever update when
/// this widget got fully rebuilt/remounted (e.g. navigating away and
/// back), staying static the rest of the time even as new notifications
/// arrived server-side.
class NotificationBellAction extends ConsumerStatefulWidget {
  const NotificationBellAction({super.key});

  @override
  ConsumerState<NotificationBellAction> createState() => _NotificationBellActionState();
}

class _NotificationBellActionState extends ConsumerState<NotificationBellAction> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.invalidate(notificationsListProvider);
        ref.invalidate(unreadNotificationCountProvider);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
