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

  /// NOTE: the backend's TeacherApprovalView is a POST with no body and
  /// requires Django is_staff (not just role == 'admin'). It also only
  /// returns a confirmation message, not the updated profile — there is
  /// currently no endpoint to list *unapproved* teachers either.
  Future<void> approveTeacher(String teacherProfileId) async {
    await _api.post(ApiConfig.teacherApprove(teacherProfileId));
  }
}
