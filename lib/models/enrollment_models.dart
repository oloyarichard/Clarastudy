import 'parsing_utils.dart';

class Enrollment {
  Enrollment({
    required this.id,
    required this.studentId,
    required this.courseId,
    this.status = 'active',
    this.pricePaid = 0,
    this.enrolledAt,
  });

  final String id;
  final String studentId;
  final String courseId;
  final String status; // active | completed | cancelled
  final double pricePaid;
  final DateTime? enrolledAt;

  factory Enrollment.fromJson(Map<String, dynamic> json) {
    return Enrollment(
      id: parseString(json['id']),
      studentId: parseString(json['student']),
      courseId: parseString(json['course']),
      status: parseString(json['status'], fallback: 'active'),
      pricePaid: parseDouble(json['price_paid']),
      enrolledAt: parseDate(json['enrolled_at']),
    );
  }
}

class LessonProgress {
  LessonProgress({
    required this.id,
    required this.enrollmentId,
    required this.lessonId,
    this.isCompleted = false,
    this.watchTimeSeconds = 0,
  });

  final String id;
  final String enrollmentId;
  final String lessonId;
  final bool isCompleted;
  final int watchTimeSeconds;

  factory LessonProgress.fromJson(Map<String, dynamic> json) {
    return LessonProgress(
      id: parseString(json['id']),
      enrollmentId: parseString(json['enrollment']),
      lessonId: parseString(json['lesson']),
      isCompleted: parseBool(json['is_completed']),
      watchTimeSeconds: parseInt(json['watch_time_seconds']),
    );
  }
}
