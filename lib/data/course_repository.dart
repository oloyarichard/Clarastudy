import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../models/course_models.dart';
import '../models/paginated_response.dart';

class CourseRepository {
  CourseRepository(this._api);
  
  final ApiClient _api;
  
  Future<PaginatedResponse<Course>> listCourses({
    int page = 1,
    String? search,
    String? level,
    String? subjectId,
    String? teacherId,
  }) async {
    final response = await _api.get(ApiConfig.courses, queryParameters: {
      'page': page,
      if (search != null && search.isNotEmpty) 'search': search,
        if (level != null && level.isNotEmpty) 'level': level,
          if (subjectId != null && subjectId.isNotEmpty) 'subject': subjectId,
            if (teacherId != null && teacherId.isNotEmpty) 'teacher': teacherId,
    });
      return PaginatedResponse.fromDynamic(response.data, Course.fromJson);
  }
  
  Future<Course> getCourse(String id) async {
    final response = await _api.get(ApiConfig.courseDetail(id));
    return Course.fromJson(response.data as Map<String, dynamic>);
  }
  
  Future<Course> createCourse({
    required String title,
    required String description,
    required String teacherId,
    String? subjectId,
    String level = 'beginner',
    double price = 0,
    String? thumbnailPath,
    void Function(double progress)? onProgress,
  }) async {
    final fields = <String, dynamic>{
      'title': title,
      'description': description,
      'teacher': teacherId,
      'level': level,
      'price': price,
      if (subjectId != null && subjectId.isNotEmpty) 'subject': subjectId,
        if (thumbnailPath != null)
          'thumbnail': await MultipartFile.fromFile(thumbnailPath),
    };
    final response = await _api.postMultipart(
      ApiConfig.courseCreate,
      fields,
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total > 0) onProgress(sent / total);
            },
    );
    return Course.fromJson(response.data as Map<String, dynamic>);
  }
  
  Future<CourseModule> createModule({
    required String courseId,
    required String title,
    int order = 0,
  }) async {
    final response = await _api.post(ApiConfig.moduleCreate, data: {
      'course': courseId,
      'title': title,
      'order': order,
    });
    return CourseModule.fromJson(response.data as Map<String, dynamic>);
  }
  
  Future<Lesson> createLesson({
    required String moduleId,
    required String title,
    String lessonType = 'video',
    String? content,
    String? videoUrl,
    int durationMinutes = 0,
    int order = 0,
    bool isFree = false,
  }) async {
    final response = await _api.post(ApiConfig.lessonCreate, data: {
      'module': moduleId,
      'title': title,
      'lesson_type': lessonType,
      if (content != null) 'content': content,
        if (videoUrl != null) 'video_url': videoUrl,
          'duration_minutes': durationMinutes,
          'order': order,
          'is_free': isFree,
    });
    return Lesson.fromJson(response.data as Map<String, dynamic>);
  }
}
