import 'parsing_utils.dart';

class ChatRoom {
  ChatRoom({
    required this.id,
    required this.name,
    this.participantIds = const [],
    required this.createdById,
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String name;
  final List<String> participantIds;
  final String createdById;
  final bool isActive;
  final DateTime? createdAt;

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    final rawParticipants = json['participants'];
    return ChatRoom(
      id: parseString(json['id']),
      name: parseString(json['name']),
      participantIds: rawParticipants is List
          ? rawParticipants.map((e) => e.toString()).toList()
          : const [],
      createdById: parseString(json['created_by']),
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: parseDate(json['created_at']),
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.content,
    this.createdAt,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String content;
  final DateTime? createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: parseString(json['id']),
      roomId: parseString(json['room']),
      senderId: parseString(json['sender']),
      content: parseString(json['content']),
      createdAt: parseDate(json['created_at']),
    );
  }
}
