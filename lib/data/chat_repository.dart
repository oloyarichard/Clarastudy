import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/chat_models.dart';
import '../models/paginated_response.dart';

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  Future<PaginatedResponse<ChatRoom>> listRooms({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.chatRooms,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, ChatRoom.fromJson);
  }

  Future<PaginatedResponse<ChatMessage>> getMessages(
    String roomId, {
    int page = 1,
  }) async {
    final response = await _api.get(
      ApiConfig.chatMessages(roomId),
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, ChatMessage.fromJson);
  }

  Future<ChatMessage> sendMessage({
    required String roomId,
    required String content,
  }) async {
    final response = await _api.post(
      ApiConfig.chatMessages(roomId),
      data: {'content': content},
    );
    return ChatMessage.fromJson(response.data as Map<String, dynamic>);
  }
}
