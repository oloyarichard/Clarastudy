import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../models/notification_model.dart';
import '../../providers/core_providers.dart';
import '../../providers/notification_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _iconFor(String type) {
    switch (type) {
      case 'class_reminder':
        return Icons.videocam_rounded;
      case 'new_resource':
        return Icons.folder_rounded;
      case 'payment_success':
        return Icons.payments_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsListProvider),
        child: notificationsAsync.when(
          data: (notifications) {
            if (notifications.isEmpty) {
              return const EmptyView(
                message: "You're all caught up.",
                icon: Icons.notifications_none_rounded,
              );
            }
            final formatter = DateFormat('MMM d, h:mm a');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final n = notifications[index];
                return _NotificationTile(
                  notification: n,
                  icon: _iconFor(n.notificationType),
                  timeLabel: n.createdAt != null ? formatter.format(n.createdAt!.toLocal()) : '',
                );
              },
            );
          },
          loading: () => const LoadingView(),
          error: (e, __) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(notificationsListProvider),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({
    required this.notification,
    required this.icon,
    required this.timeLabel,
  });

  final AppNotification notification;
  final IconData icon;
  final String timeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: notification.isRead ? AppColors.cardLight : AppColors.primary.withOpacity(0.04),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.w800,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.message, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(timeLabel, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        trailing: notification.isRead
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
        onTap: () async {
          if (!notification.isRead) {
            await ref.read(notificationRepositoryProvider).markAsRead(notification.id);
            ref.invalidate(notificationsListProvider);
          }
        },
      ),
    );
  }
}
