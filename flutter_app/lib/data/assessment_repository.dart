import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/assessment_models.dart';
import '../models/paginated_response.dart';

class AssessmentRepository {
  AssessmentRepository(this._api);

  final ApiClient _api;

  Future<PaginatedResponse<Quiz>> listQuizzes({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.quizzes,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, Quiz.fromJson);
  }

  Future<QuizAttempt> submitAttempt({
    required String quizId,
    required String studentId,
    required int score,
    required bool isPassed,
  }) async {
    final response = await _api.post(ApiConfig.quizAttempt, data: {
      'quiz': quizId,
      'student': studentId,
      'score': score,
      'is_passed': isPassed,
    });
    return QuizAttempt.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<Certificate>> myCertificates({int page = 1}) async {
    final response = await _api.get(
      ApiConfig.certificates,
      queryParameters: {'page': page},
    );
    return PaginatedResponse.fromDynamic(response.data, Certificate.fromJson);
  }
}
