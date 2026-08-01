import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/live_class_models.dart';
import '../models/paginated_response.dart';

class LiveClassRepository {
  LiveClassRepository(this._api);
  
  final ApiClient _api;
  
  Future<PaginatedResponse<LiveClass>> listLiveClasses({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.liveClasses,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, LiveClass.fromJson);
  }
  
  Future<LiveClass> createLiveClass({
    required String teacherId,
    required String courseId,
    required String title,
    String? description,
    required DateTime scheduledAt,
    int durationMinutes = 60,
    required String roomId,
  }) async {
    final response = await _api.post(ApiConfig.liveClassCreate, data: {
      'teacher': teacherId,
      'course': courseId,
      'title': title,
      if (description != null) 'description': description,
        'scheduled_at': scheduledAt.toIso8601String(),
        'duration_minutes': durationMinutes,
        'room_id': roomId,
        'status': 'scheduled',
    });
    return LiveClass.fromJson(response.data as Map<String, dynamic>);
  }
  
  /// Teacher-only: marks the class live, which is what unblocks students'
  /// join calls (see LiveClassJitsiTokenView on the backend).
  Future<LiveClass> startLiveClass(String liveClassId) async {
    final response = await _api.post(ApiConfig.liveClassStart(liveClassId));
    return LiveClass.fromJson(response.data as Map<String, dynamic>);
  }
  
  /// Teacher-only (or admin): permanently deletes a live class they created.
  Future<void> deleteLiveClass(String liveClassId) async {
    await _api.delete(ApiConfig.liveClassDelete(liveClassId));
  }
  
  Future<JitsiCredentials> getJitsiCredentials(String liveClassId) async {
    final response = await _api.get(ApiConfig.liveClassJitsiToken(liveClassId));
    return JitsiCredentials.fromJson(response.data as Map<String, dynamic>);
  }
  
  Future<List<LiveChatMessage>> getLiveChat(String liveClassId) async {
    final response = await _api.get(ApiConfig.liveClassChat(liveClassId));
    final result =
    PaginatedResponse.fromDynamic(response.data, LiveChatMessage.fromJson);
    return result.results;
  }
  
  Future<LiveChatMessage> sendLiveChat({
    required String liveClassId,
    required String message,
  }) async {
    final response = await _api.post(
      ApiConfig.liveClassChat(liveClassId),
      data: {'message': message},
    );
    return LiveChatMessage.fromJson(response.data as Map<String, dynamic>);
  }
}
