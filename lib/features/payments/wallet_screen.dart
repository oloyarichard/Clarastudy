import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../models/payment_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/course_providers.dart';
import '../../providers/payment_providers.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final paymentsAsync = ref.watch(myPaymentsProvider);
    final topUpsAsync = ref.watch(myTopUpsProvider);
    final withdrawalsAsync = ref.watch(myWithdrawalsProvider);
    final isTeacher = ref.watch(authProvider).user?.role == 'teacher';
    final currency = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletProvider);
          ref.invalidate(myPaymentsProvider);
          ref.invalidate(myTopUpsProvider);
          ref.invalidate(myWithdrawalsProvider);
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _TopUpDialog(),
                ),
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('Top up'),
              ),
            ),
            if (isTeacher) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _RequestWithdrawalDialog(),
                  ),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Request withdrawal'),
                ),
              ),
            ],
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
            if (isTeacher) ...[
              const SizedBox(height: 28),
              const SectionHeader(title: 'Withdrawal requests'),
              const SizedBox(height: 12),
              withdrawalsAsync.when(
                data: (withdrawals) {
                  if (withdrawals.isEmpty) {
                    return const EmptyView(
                      message: 'No withdrawal requests yet.',
                      icon: Icons.account_balance_wallet_outlined,
                    );
                  }
                  final sorted = [...withdrawals]..sort((a, b) {
                      final aDate = a.createdAt ?? DateTime(2000);
                      final bDate = b.createdAt ?? DateTime(2000);
                      return bDate.compareTo(aDate);
                    });
                  return Column(
                    children: sorted.map((w) => _WithdrawalTile(withdrawal: w)).toList(),
                  );
                },
                loading: () => const LoadingView(),
                error: (e, __) => ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(myWithdrawalsProvider),
                ),
              ),
            ],
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

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.withdrawal});

  final WithdrawalRequest withdrawal;

  Color get _statusColor {
    switch (withdrawal.status) {
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
        leading: Icon(Icons.account_balance_wallet_rounded, color: _statusColor),
        title: Text(
          'To: ${withdrawal.momoNumber}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          withdrawal.createdAt != null ? formatter.format(withdrawal.createdAt!) : '',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('\$${withdrawal.amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            StatusChip(label: withdrawal.status, color: _statusColor),
          ],
        ),
      ),
    );
  }
}

/// The dialog a teacher fills in to request a payout — amount and the
/// mobile money number to receive it. The backend holds (deducts) the
/// amount from their wallet the moment this is submitted, before any
/// admin review — see WithdrawalRequestCreateView for why.
/// The dialog behind the standalone "Top up" button — independent of
/// any enrollment attempt, so a student (or teacher) can add funds to
/// their wallet proactively at any time, not just when an enrollment
/// fails for insufficient balance.
class _TopUpDialog extends ConsumerStatefulWidget {
  const _TopUpDialog();

  @override
  ConsumerState<_TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends ConsumerState<_TopUpDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _submit(String momoNumber) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(paymentRepositoryProvider).submitTopUpRequest(
            amount: double.parse(_amountController.text.trim()),
            momoReference: _refController.text.trim(),
          );
      ref.invalidate(myTopUpsProvider);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Top-up request submitted — an admin will review it shortly.')),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not submit the request.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final momoNumber = walletAsync.asData?.value.momoWalletNumber ?? '';

    return AlertDialog(
      title: const Text('Top up your wallet'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              momoNumber.isEmpty
                  ? 'Send money via mobile money, then enter the details below.'
                  : 'Send money to $momoNumber via mobile money, then enter the details below.',
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _amountController,
              label: 'Amount (USD)',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              prefixIcon: Icons.attach_money_rounded,
              validator: (v) {
                final value = double.tryParse((v ?? '').trim());
                if (value == null || value <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _refController,
              label: 'Mobile payment reference ID',
              prefixIcon: Icons.receipt_long_outlined,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter the payment reference';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : () => _submit(momoNumber),
          child: Text(_submitting ? 'Submitting…' : 'Submit'),
        ),
      ],
    );
  }
}

class _RequestWithdrawalDialog extends ConsumerStatefulWidget {
  const _RequestWithdrawalDialog();

  @override
  ConsumerState<_RequestWithdrawalDialog> createState() => _RequestWithdrawalDialogState();
}

class _RequestWithdrawalDialogState extends ConsumerState<_RequestWithdrawalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _numberController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(paymentRepositoryProvider).requestWithdrawal(
            amount: double.parse(_amountController.text.trim()),
            momoNumber: _numberController.text.trim(),
          );
      ref.invalidate(walletProvider);
      ref.invalidate(myWithdrawalsProvider);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Withdrawal requested — awaiting admin approval.')),
        );
      }
    } catch (e) {
      String message = 'Could not submit the request.';
      if (e is ApiException) {
        final backendError = e.fieldErrors?['error'];
        message = backendError is String ? backendError : e.message;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request withdrawal'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _amountController,
              label: 'Amount',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              prefixIcon: Icons.attach_money_rounded,
              validator: (v) {
                final value = double.tryParse((v ?? '').trim());
                if (value == null || value <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _numberController,
              label: 'Mobile money number',
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter the number to receive payment';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Submitting…' : 'Submit'),
        ),
      ],
    );
  }
}
