import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_models.dart';
import 'core_providers.dart';

final chatRoomsProvider = FutureProvider.autoDispose<List<ChatRoom>>((ref) async {
  final repo = ref.watch(chatRepositoryProvider);
  final result = await repo.listRooms();
  return result.results;
});

final chatMessagesProvider =
    FutureProvider.autoDispose.family<List<ChatMessage>, String>((ref, roomId) async {
  final repo = ref.watch(chatRepositoryProvider);
  final result = await repo.getMessages(roomId);
  return result.results;
});
