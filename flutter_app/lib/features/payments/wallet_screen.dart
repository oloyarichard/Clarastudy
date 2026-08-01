import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../models/payment_models.dart';
import '../../providers/course_providers.dart';
import '../../providers/payment_providers.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final paymentsAsync = ref.watch(myPaymentsProvider);
    final topUpsAsync = ref.watch(myTopUpsProvider);
    final currency = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletProvider);
          ref.invalidate(myPaymentsProvider);
          ref.invalidate(myTopUpsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  walletAsync.when(
                    data: (wallet) => Text(
                      currency.format(wallet.balance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    loading: () => const SizedBox(
                      height: 32,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                    error: (e, __) => const Text(
                      '—',
                      style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Payment history'),
            const SizedBox(height: 12),
            paymentsAsync.when(
              data: (payments) {
                if (payments.isEmpty) {
                  return const EmptyView(
                    message: 'No payments yet.',
                    icon: Icons.receipt_long_outlined,
                  );
                }
                final sorted = [...payments]..sort((a, b) {
                    final aDate = a.createdAt ?? DateTime(2000);
                    final bDate = b.createdAt ?? DateTime(2000);
                    return bDate.compareTo(aDate);
                  });
                return Column(
                  children: sorted.map((p) => _PaymentTile(payment: p)).toList(),
                );
              },
              loading: () => const LoadingView(),
              error: (e, __) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(myPaymentsProvider),
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Top-up requests'),
            const SizedBox(height: 12),
            topUpsAsync.when(
              data: (topUps) {
                if (topUps.isEmpty) {
                  return const EmptyView(
                    message: 'No top-up requests yet.',
                    icon: Icons.request_quote_outlined,
                  );
                }
                final sorted = [...topUps]..sort((a, b) {
                    final aDate = a.createdAt ?? DateTime(2000);
                    final bDate = b.createdAt ?? DateTime(2000);
                    return bDate.compareTo(aDate);
                  });
                return Column(
                  children: sorted.map((t) => _TopUpTile(topUp: t)).toList(),
                );
              },
              loading: () => const LoadingView(),
              error: (e, __) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(myTopUpsProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopUpTile extends StatelessWidget {
  const _TopUpTile({required this.topUp});

  final WalletTopUpRequest topUp;

  Color get _statusColor {
    switch (topUp.status) {
      case 'approved':
        return AppColors.secondary;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, yyyy');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.request_quote_rounded, color: _statusColor),
        title: Text(
          'Reference: ${topUp.momoReference}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          topUp.createdAt != null ? formatter.format(topUp.createdAt!) : '',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('\$${topUp.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            StatusChip(label: topUp.status, color: _statusColor),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends ConsumerWidget {
  const _PaymentTile({required this.payment});

  final Payment payment;

  Color get _statusColor {
    switch (payment.status) {
      case 'completed':
        return AppColors.secondary;
      case 'failed':
        return AppColors.error;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = DateFormat('MMM d, yyyy');
    final courseAsync = ref.watch(courseDetailProvider(payment.courseId));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.payments_rounded, color: _statusColor),
        title: Text(
          courseAsync.asData?.value.title ?? 'Course payment',
          style: const TextStyle(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${payment.paymentMethod.replaceAll('_', ' ')}'
          '${payment.createdAt != null ? ' · ${formatter.format(payment.createdAt!)}' : ''}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('\$${payment.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            StatusChip(label: payment.status, color: _statusColor),
          ],
        ),
      ),
    );
  }
}
