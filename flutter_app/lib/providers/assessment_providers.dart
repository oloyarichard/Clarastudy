import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/assessment_models.dart';
import 'core_providers.dart';

final quizzesListProvider = FutureProvider.autoDispose<List<Quiz>>((ref) async {
  final repo = ref.watch(assessmentRepositoryProvider);
  final result = await repo.listQuizzes();
  return result.results;
});

final myCertificatesProvider = FutureProvider.autoDispose<List<Certificate>>((ref) async {
  final repo = ref.watch(assessmentRepositoryProvider);
  final result = await repo.myCertificates();
  return result.results;
});

/// Quizzes that belong to a specific course.
final quizzesForCourseProvider =
    FutureProvider.autoDispose.family<List<Quiz>, String>((ref, courseId) async {
  final quizzes = await ref.watch(quizzesListProvider.future);
  return quizzes.where((q) => q.courseId == courseId).toList();
});
