import 'parsing_utils.dart';

class Quiz {
  Quiz({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
    this.passingScore = 70,
    this.createdAt,
  });

  final String id;
  final String courseId;
  final String title;
  final String? description;
  final int passingScore;
  final DateTime? createdAt;

  factory Quiz.fromJson(Map<String, dynamic> json) {
    return Quiz(
      id: parseString(json['id']),
      courseId: parseString(json['course']),
      title: parseString(json['title']),
      description: json['description'] as String?,
      passingScore: parseInt(json['passing_score'], fallback: 70),
      createdAt: parseDate(json['created_at']),
    );
  }
}

class QuizAttempt {
  QuizAttempt({
    required this.id,
    required this.quizId,
    required this.studentId,
    this.score = 0,
    this.isPassed = false,
    this.createdAt,
  });

  final String id;
  final String quizId;
  final String studentId;
  final int score;
  final bool isPassed;
  final DateTime? createdAt;

  factory QuizAttempt.fromJson(Map<String, dynamic> json) {
    return QuizAttempt(
      id: parseString(json['id']),
      quizId: parseString(json['quiz']),
      studentId: parseString(json['student']),
      score: parseInt(json['score']),
      isPassed: parseBool(json['is_passed']),
      createdAt: parseDate(json['created_at']),
    );
  }
}

class Certificate {
  Certificate({
    required this.id,
    required this.studentId,
    required this.courseId,
    required this.certificateNumber,
    this.issueDate,
  });

  final String id;
  final String studentId;
  final String courseId;
  final String certificateNumber;
  final DateTime? issueDate;

  factory Certificate.fromJson(Map<String, dynamic> json) {
    return Certificate(
      id: parseString(json['id']),
      studentId: parseString(json['student']),
      courseId: parseString(json['course']),
      certificateNumber: parseString(json['certificate_number']),
      issueDate: parseDate(json['issue_date']),
    );
  }
}
