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

/// Room info for joining a live class's Jitsi call. We're on the public
/// meet.jit.si server, so there's no JWT — access control (who's even
/// allowed to fetch this) is enforced entirely by the backend before this
/// ever gets returned. `isModerator` is a UI hint for the app itself (e.g.
/// which controls to show); actual Jitsi moderator status on the public
/// server goes to whoever's client joins the room first.
class JitsiCredentials {
  JitsiCredentials({
    required this.domain,
    required this.room,
    required this.isModerator,
  });

  final String domain;
  final String room;
  final bool isModerator;

  factory JitsiCredentials.fromJson(Map<String, dynamic> json) {
    return JitsiCredentials(
      domain: parseString(json['domain']),
      room: parseString(json['room']),
      isModerator: json['is_moderator'] == true,
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
