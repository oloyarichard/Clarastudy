import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enrollment_models.dart';
import 'core_providers.dart';

final myEnrollmentsProvider = FutureProvider.autoDispose<List<Enrollment>>((ref) async {
  final repo = ref.watch(enrollmentRepositoryProvider);
  final result = await repo.myEnrollments();
  return result.results;
});

/// Convenience lookup: is the current student already enrolled in
/// [courseId]? Used to toggle the "Enroll" button on course details.
final isEnrolledProvider =
    FutureProvider.autoDispose.family<Enrollment?, String>((ref, courseId) async {
  final enrollments = await ref.watch(myEnrollmentsProvider.future);
  for (final e in enrollments) {
    if (e.courseId == courseId && e.status != 'cancelled') return e;
  }
  return null;
});
