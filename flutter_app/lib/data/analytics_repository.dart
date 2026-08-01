import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/dashboard_stats.dart';
import '../models/paginated_response.dart';
import '../models/user_models.dart';

class AnalyticsRepository {
  AnalyticsRepository(this._api);

  final ApiClient _api;

  Future<DashboardStats> getDashboardStats() async {
    final response = await _api.get(ApiConfig.dashboard);
    return DashboardStats.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<TeacherProfile>> listTeachers({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.teachers,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, TeacherProfile.fromJson);
  }

  /// Admin-only: teachers awaiting approval.
  Future<List<TeacherProfile>> listPendingTeachers() async {
    final response = await _api.get(ApiConfig.pendingTeachers);
    final data = response.data;
    final results = data is Map<String, dynamic> ? (data['results'] ?? data) : data;
    return (results as List)
        .map((e) => TeacherProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approveTeacher(String teacherProfileId) async {
    await _api.post(ApiConfig.teacherApprove(teacherProfileId));
  }
}
