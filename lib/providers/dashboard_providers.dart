import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dashboard_stats.dart';
import '../models/user_models.dart';
import 'core_providers.dart';

final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats>((ref) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  return repo.getDashboardStats();
});

final teachersListProvider = FutureProvider.autoDispose<List<TeacherProfile>>((ref) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  final result = await repo.listTeachers();
  return result.results;
});
