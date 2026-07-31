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

/// The student's own top-up requests (pending/approved/rejected) — shown
/// in the wallet screen so an approved top-up visibly becomes part of
/// their history, not just a silent balance change.
final myTopUpsProvider = FutureProvider.autoDispose<List<WalletTopUpRequest>>((ref) async {
  final repo = ref.watch(paymentRepositoryProvider);
  return repo.myTopUps();
});
