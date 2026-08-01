import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_model.dart';
import 'core_providers.dart';

final notificationsListProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final repo = ref.watch(notificationRepositoryProvider);
  final result = await repo.myNotifications();
  return result.results;
});

final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final notifications = await ref.watch(notificationsListProvider.future);
  return notifications.where((n) => !n.isRead).length;
});
