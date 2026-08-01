import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/live_class_models.dart';
import 'core_providers.dart';

final liveClassesListProvider = FutureProvider.autoDispose<List<LiveClass>>((ref) async {
  final repo = ref.watch(liveClassRepositoryProvider);
  final result = await repo.listLiveClasses();
  return result.results;
});

/// A teacher's own live classes, across all their courses — used on the
/// teacher dashboard so they can see, start, or delete each one without
/// digging through course detail screens. Fetches independently rather
/// than watching liveClassesListProvider.future — chaining an autoDispose
/// provider's in-flight future into another autoDispose provider can throw
/// a disposal-related exception on rapid rebuilds (e.g. right after login,
/// when several screens mount/unmount quickly).
final myLiveClassesProvider =
    FutureProvider.autoDispose.family<List<LiveClass>, String>((ref, teacherId) async {
  final repo = ref.watch(liveClassRepositoryProvider);
  final result = await repo.listLiveClasses();
  return result.results.where((c) => c.teacherId == teacherId).toList();
});

final liveChatProvider =
    FutureProvider.autoDispose.family<List<LiveChatMessage>, String>((ref, liveClassId) async {
  final repo = ref.watch(liveClassRepositoryProvider);
  return repo.getLiveChat(liveClassId);
});
