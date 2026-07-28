import 'parsing_utils.dart';

/// The /api/analytics/dashboard/ endpoint returns a different shape
/// depending on the logged-in user's role, so every field here is
/// optional/defaulted and the UI only reads the ones relevant to the
/// current role.
class DashboardStats {
  DashboardStats({
    this.totalStudents,
    this.totalTeachers,
    this.totalCourses,
    this.totalRevenue,
    this.myCourses,
    this.enrolledCourses,
    this.completedCourses,
  });

  // admin
  final int? totalStudents;
  final int? totalTeachers;
  final int? totalCourses;
  final double? totalRevenue;

  // teacher
  final int? myCourses;

  // student
  final int? enrolledCourses;
  final int? completedCourses;

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalStudents: json.containsKey('total_students')
          ? parseInt(json['total_students'])
          : null,
      totalTeachers: json.containsKey('total_teachers')
          ? parseInt(json['total_teachers'])
          : null,
      totalCourses: json.containsKey('total_courses')
          ? parseInt(json['total_courses'])
          : null,
      totalRevenue: json.containsKey('total_revenue')
          ? parseDouble(json['total_revenue'])
          : null,
      myCourses:
          json.containsKey('my_courses') ? parseInt(json['my_courses']) : null,
      enrolledCourses: json.containsKey('enrolled_courses')
          ? parseInt(json['enrolled_courses'])
          : null,
      completedCourses: json.containsKey('completed_courses')
          ? parseInt(json['completed_courses'])
          : null,
    );
  }
}
