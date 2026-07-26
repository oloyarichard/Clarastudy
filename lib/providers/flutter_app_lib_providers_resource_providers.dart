import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/resource_models.dart';
import 'core_providers.dart';

final resourcesListProvider = FutureProvider.autoDispose<List<Resource>>((ref) async {
  final repo = ref.watch(resourceRepositoryProvider);
  final result = await repo.listResources();
  return result.results;
});

final myDownloadsProvider = FutureProvider.autoDispose<List<OfflineDownload>>((ref) async {
  final repo = ref.watch(resourceRepositoryProvider);
  final result = await repo.myDownloads();
  return result.results;
});
