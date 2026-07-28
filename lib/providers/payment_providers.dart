import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/payment_models.dart';
import 'core_providers.dart';

final myPaymentsProvider = FutureProvider.autoDispose<List<Payment>>((ref) async {
  final repo = ref.watch(paymentRepositoryProvider);
  final result = await repo.myPayments();
  return result.results;
});

final walletProvider = FutureProvider.autoDispose<Wallet>((ref) async {
  final repo = ref.watch(paymentRepositoryProvider);
  return repo.getWallet();
});
