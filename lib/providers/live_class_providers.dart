import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/live_class_models.dart';
import 'core_providers.dart';

final liveClassesListProvider = FutureProvider.autoDispose<List<LiveClass>>((ref) async {
  final repo = ref.watch(liveClassRepositoryProvider);
  final result = await repo.listLiveClasses();
  return result.results;
});

final liveChatProvider =
    FutureProvider.autoDispose.family<List<LiveChatMessage>, String>((ref, liveClassId) async {
  final repo = ref.watch(liveClassRepositoryProvider);
  return repo.getLiveChat(liveClassId);
});
