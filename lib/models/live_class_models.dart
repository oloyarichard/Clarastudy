import 'parsing_utils.dart';

class LiveClass {
  LiveClass({
    required this.id,
    required this.teacherId,
    required this.courseId,
    required this.title,
    this.description,
    required this.scheduledAt,
    this.durationMinutes = 60,
    required this.roomId,
    this.status = 'scheduled',
    this.createdAt,
  });

  final String id;
  final String teacherId;
  final String courseId;
  final String title;
  final String? description;
  final DateTime? scheduledAt;
  final int durationMinutes;
  final String roomId;
  final String status; // scheduled | live | ended
  final DateTime? createdAt;

  bool get isLive => status == 'live';
  bool get isEnded => status == 'ended';

  factory LiveClass.fromJson(Map<String, dynamic> json) {
    return LiveClass(
      id: parseString(json['id']),
      teacherId: parseString(json['teacher']),
      courseId: parseString(json['course']),
      title: parseString(json['title']),
      description: json['description'] as String?,
      scheduledAt: parseDate(json['scheduled_at']),
      durationMinutes: parseInt(json['duration_minutes'], fallback: 60),
      roomId: parseString(json['room_id']),
      status: parseString(json['status'], fallback: 'scheduled'),
      createdAt: parseDate(json['created_at']),
    );
  }
}

/// Room info for joining a live class's Daily.co call. The token already
/// carries the correct role (moderator or not) — decided server-side by
/// LiveClassDailyTokenView before this is ever returned — so there's no
/// join-order dependency and no lobby/knocking involved.
class DailyCallCredentials {
  DailyCallCredentials({
    required this.roomUrl,
    required this.token,
    required this.isOwner,
  });

  final String roomUrl;
  final String token;
  final bool isOwner;

  factory DailyCallCredentials.fromJson(Map<String, dynamic> json) {
    return DailyCallCredentials(
      roomUrl: parseString(json['room_url']),
      token: parseString(json['token']),
      isOwner: json['is_owner'] == true,
    );
  }
}

class LiveChatMessage {
  LiveChatMessage({
    required this.id,
    required this.liveClassId,
    required this.userId,
    required this.message,
    this.createdAt,
  });

  final String id;
  final String liveClassId;
  final String userId;
  final String message;
  final DateTime? createdAt;

  factory LiveChatMessage.fromJson(Map<String, dynamic> json) {
    return LiveChatMessage(
      id: parseString(json['id']),
      liveClassId: parseString(json['live_class']),
      userId: parseString(json['user']),
      message: parseString(json['message']),
      createdAt: parseDate(json['created_at']),
    );
  }
}

class RaisedHandEntry {
  RaisedHandEntry({
    required this.id,
    required this.userId,
    required this.userName,
    this.raisedAt,
  });

  final String id;
  final String userId;
  final String userName;
  final DateTime? raisedAt;

  factory RaisedHandEntry.fromJson(Map<String, dynamic> json) {
    return RaisedHandEntry(
      id: parseString(json['id']),
      userId: parseString(json['user']),
      userName: parseString(json['user_name']),
      raisedAt: parseDate(json['raised_at']),
    );
  }
}
