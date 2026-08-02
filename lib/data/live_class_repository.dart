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

  /// Teacher-only: marks the class 'live'. Purely informational (e.g. a
  /// "live now" badge) — no longer required before students can join;
  /// that was a Jitsi-specific workaround, gone now that Daily assigns
  /// roles explicitly via the join token.
  Future<LiveClass> startLiveClass(String liveClassId) async {
    final response = await _api.post(ApiConfig.liveClassStart(liveClassId));
    return LiveClass.fromJson(response.data as Map<String, dynamic>);
  }

  /// Teacher-only (or admin): permanently deletes a live class they created.
  Future<void> deleteLiveClass(String liveClassId) async {
    await _api.delete(ApiConfig.liveClassDelete(liveClassId));
  }

  /// Sends userId + classId to the backend, which decides the role
  /// (teacher/admin -> is_owner, enrolled student -> attendee, anyone
  /// else -> rejected before this call even returns) and mints a Daily
  /// meeting token already carrying that role.
  Future<DailyCallCredentials> getDailyCredentials(String liveClassId) async {
    final response = await _api.get(ApiConfig.liveClassDailyToken(liveClassId));
    return DailyCallCredentials.fromJson(response.data as Map<String, dynamic>);
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

  /// Everyone currently raising their hand in this class.
  Future<List<RaisedHandEntry>> getRaisedHands(String liveClassId) async {
    final response = await _api.get(ApiConfig.raisedHands(liveClassId));
    final result = PaginatedResponse.fromDynamic(response.data, RaisedHandEntry.fromJson);
    return result.results;
  }

  /// Toggles the current user's own hand — raises it if not already up,
  /// lowers it if it is. Pass userId to lower someone ELSE's hand
  /// (teacher-only on the backend).
  Future<bool> toggleRaisedHand(String liveClassId, {String? userId}) async {
    final response = await _api.post(
      ApiConfig.raisedHandToggle(liveClassId),
      data: userId != null ? {'user_id': userId} : {},
    );
    return (response.data as Map<String, dynamic>)['raised'] == true;
  }
}
