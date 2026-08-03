import '../core/network/api_config.dart';
import 'parsing_utils.dart';
import 'resource_models.dart';

class Subject {
  Subject({required this.id, required this.name, this.description});

  final String id;
  final String name;
  final String? description;

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      id: parseString(json['id']),
      name: parseString(json['name']),
      description: json['description'] as String?,
    );
  }
}

class Lesson {
  Lesson({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.lessonType,
    this.content,
    this.videoUrl,
    this.durationMinutes = 0,
    this.order = 0,
    this.isFree = false,
    this.resources = const [],
  });

  final String id;
  final String moduleId;
  final String title;
  final String lessonType; // video | text | quiz
  final String? content;
  final String? videoUrl;
  final int durationMinutes;
  final int order;
  final bool isFree;
  final List<Resource> resources;

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: parseString(json['id']),
      moduleId: parseString(json['module']),
      title: parseString(json['title']),
      lessonType: parseString(json['lesson_type'], fallback: 'video'),
      content: json['content'] as String?,
      videoUrl: json['video_url'] as String?,
      durationMinutes: parseInt(json['duration_minutes']),
      order: parseInt(json['order']),
      isFree: parseBool(json['is_free']),
      resources: (json['resources'] as List<dynamic>? ?? [])
          .map((e) => Resource.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CourseModule {
  CourseModule({
    required this.id,
    required this.courseId,
    required this.title,
    this.order = 0,
    this.lessons = const [],
  });

  final String id;
  final String courseId;
  final String title;
  final int order;
  final List<Lesson> lessons;

  factory CourseModule.fromJson(Map<String, dynamic> json) {
    final rawLessons = json['lessons'];
    return CourseModule(
      id: parseString(json['id']),
      courseId: parseString(json['course']),
      title: parseString(json['title']),
      order: parseInt(json['order']),
      lessons: rawLessons is List
          ? rawLessons
              .whereType<Map<String, dynamic>>()
              .map(Lesson.fromJson)
              .toList()
          : const [],
    );
  }
}

class Course {
  Course({
    required this.id,
    required this.title,
    required this.description,
    required this.teacherId,
    this.subjectId,
    this.level = 'beginner',
    this.thumbnail,
    this.price = 0,
    this.rating = 0,
    this.totalStudents = 0,
    this.createdAt,
    this.modules = const [],
  });

  final String id;
  final String title;
  final String description;
  final String teacherId;
  final String? subjectId;
  final String level; // beginner | intermediate | advanced
  final String? thumbnail;
  final double price;
  final double rating;
  final int totalStudents;
  final DateTime? createdAt;
  final List<CourseModule> modules;

  bool get isFree => price <= 0;
  String get thumbnailUrl => ApiConfig.resolveMediaUrl(thumbnail);

  int get totalLessons =>
      modules.fold(0, (sum, m) => sum + m.lessons.length);

  factory Course.fromJson(Map<String, dynamic> json) {
    final rawModules = json['modules'];
    return Course(
      id: parseString(json['id']),
      title: parseString(json['title']),
      description: parseString(json['description']),
      teacherId: parseString(json['teacher']),
      subjectId: json['subject'] as String?,
      level: parseString(json['level'], fallback: 'beginner'),
      thumbnail: json['thumbnail'] as String?,
      price: parseDouble(json['price']),
      rating: parseDouble(json['rating']),
      totalStudents: parseInt(json['total_students']),
      createdAt: parseDate(json['created_at']),
      modules: rawModules is List
          ? rawModules
              .whereType<Map<String, dynamic>>()
              .map(CourseModule.fromJson)
              .toList()
          : const [],
    );
  }
}
