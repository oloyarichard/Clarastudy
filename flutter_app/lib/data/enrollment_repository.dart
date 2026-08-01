import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/enrollment_models.dart';
import '../models/paginated_response.dart';

class EnrollmentRepository {
  EnrollmentRepository(this._api);

  final ApiClient _api;

  Future<PaginatedResponse<Enrollment>> myEnrollments({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.myEnrollments,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, Enrollment.fromJson);
  }

  /// Atomically pays for and enrolls in a course. Throws [ApiException]
  /// with statusCode 402 and fieldErrors containing momo_wallet_number /
  /// shortfall if the student's wallet balance is too low.
  Future<Enrollment> enrollAndPay({required String courseId}) async {
    final response = await _api.post(ApiConfig.enrollAndPay, data: {
      'course_id': courseId,
    });
    final data = response.data as Map<String, dynamic>;
    return Enrollment.fromJson(data['enrollment'] as Map<String, dynamic>);
  }

  Future<Enrollment> enroll({
    required String courseId,
    required String studentId,
    double pricePaid = 0,
  }) async {
    final response = await _api.post(ApiConfig.enrollmentCreate, data: {
      'course': courseId,
      'student': studentId,
      'price_paid': pricePaid,
      'status': 'active',
    });
    return Enrollment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<LessonProgress> updateProgress({
    required String enrollmentId,
    required String lessonId,
    bool isCompleted = false,
    int watchTimeSeconds = 0,
  }) async {
    final response = await _api.post(ApiConfig.progressUpdate, data: {
      'enrollment': enrollmentId,
      'lesson': lessonId,
      'is_completed': isCompleted,
      'watch_time_seconds': watchTimeSeconds,
    });
    return LessonProgress.fromJson(response.data as Map<String, dynamic>);
  }
}
