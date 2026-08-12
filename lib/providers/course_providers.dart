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

/// Every course actually belonging to this teacher — filtered server-side
/// (not fetched-all-then-filtered-client-side, which only ever saw page
/// 1 of ALL platform courses and could silently miss this teacher's own
/// courses once the platform passed 20 total). Pages through completely
/// so this stays correct even for a teacher with more than 20 courses
/// of their own, not just "good enough for now."
final myTaughtCoursesProvider =
FutureProvider.autoDispose.family<List<Course>, String>((ref, teacherId) async {
  final repo = ref.watch(courseRepositoryProvider);
  final all = <Course>[];
  var page = 1;
  while (true) {
    final result = await repo.listCourses(teacherId: teacherId, page: page);
    all.addAll(result.results);
    if (!result.hasNext) break;
    page++;
  }
  return all;
});
