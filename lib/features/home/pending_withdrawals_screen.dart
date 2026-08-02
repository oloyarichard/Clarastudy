import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/core_providers.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/payment_providers.dart';

/// Admin duty screen: teacher withdrawal requests awaiting manual
/// review. Approving marks the payout as sent (the admin has actually
/// paid the teacher's mobile money number themselves, off-platform) and
/// notifies the teacher; rejecting refunds the held amount back to
/// their wallet and notifies them why.
class PendingWithdrawalsScreen extends ConsumerWidget {
  const PendingWithdrawalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingWithdrawalsProvider);
    final currency = NumberFormat.currency(symbol: '\$');

    Future<void> review(String id, bool approve) async {
      try {
        await ref.read(paymentRepositoryProvider).reviewWithdrawal(id, approve: approve);
        ref.invalidate(pendingWithdrawalsProvider);
        ref.invalidate(dashboardStatsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(approve ? 'Marked as sent — teacher notified' : 'Rejected and refunded to teacher')),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not review this request.')),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Withdrawal requests')),
      body: pendingAsync.when(
        data: (requests) {
          if (requests.isEmpty) {
            return const EmptyView(
              message: 'No withdrawal requests waiting for review.',
              icon: Icons.account_balance_wallet_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(currency.format(req.amount),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text(
                            req.createdAt != null
                                ? DateFormat('MMM d, h:mm a').format(req.createdAt!.toLocal())
                                : '',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Send to: ${req.momoNumber}',
                          style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => review(req.id, false),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => review(req.id, true),
                              child: const Text('Mark as sent'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const LoadingView(),
        error: (e, __) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(pendingWithdrawalsProvider),
        ),
      ),
    );
  }
}
