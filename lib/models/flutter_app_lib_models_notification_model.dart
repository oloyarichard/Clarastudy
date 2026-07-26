import 'parsing_utils.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.userId,
    required this.notificationType,
    required this.title,
    required this.message,
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String notificationType; // class_reminder | new_resource | payment_success | general
  final String title;
  final String message;
  final bool isRead;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: parseString(json['id']),
      userId: parseString(json['user']),
      notificationType: parseString(json['notification_type'], fallback: 'general'),
      title: parseString(json['title']),
      message: parseString(json['message']),
      isRead: parseBool(json['is_read']),
      createdAt: parseDate(json['created_at']),
    );
  }
}
