import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course_models.dart';
import 'core_providers.dart';

/// Search/filter state for the course list screen. Kept simple: a query
/// string and an optional level filter, both editable from the UI.
class CourseFilter {
  const CourseFilter({this.search = '', this.level});

  final String search;
  final String? level;

  CourseFilter copyWith({String? search, String? level, bool clearLevel = false}) {
    return CourseFilter(
      search: search ?? this.search,
      level: clearLevel ? null : (level ?? this.level),
    );
  }
}

final courseFilterProvider = StateProvider<CourseFilter>((ref) => const CourseFilter());

final coursesListProvider = FutureProvider.autoDispose<List<Course>>((ref) async {
  final filter = ref.watch(courseFilterProvider);
  final repo = ref.watch(courseRepositoryProvider);
  final result = await repo.listCourses(search: filter.search, level: filter.level);
  return result.results;
});

final courseDetailProvider =
    FutureProvider.autoDispose.family<Course, String>((ref, courseId) async {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.getCourse(courseId);
});

/// Courses taught by a specific teacher — derived client-side from the
/// full list since the backend doesn't expose a dedicated filter for it.
final myTaughtCoursesProvider =
    FutureProvider.autoDispose.family<List<Course>, String>((ref, teacherId) async {
  final repo = ref.watch(courseRepositoryProvider);
  final result = await repo.listCourses();
  return result.results.where((c) => c.teacherId == teacherId).toList();
});
