import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/payment_providers.dart';
import 'notification_bell_action.dart';

/// The admin's home screen: platform-wide stats, the admin's own 40%
/// revenue-share wallet, and the two actual admin duties in this app —
/// approving pending teachers and reviewing wallet top-up requests —
/// each with a live pending-count badge so it's obvious when something
/// needs attention.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user!;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final walletAsync = ref.watch(walletProvider);
    final pendingTeachersAsync = ref.watch(pendingTeachersProvider);
    final pendingTopUpsAsync = ref.watch(pendingTopUpsProvider);
    final currency = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Overview'),
        actions: const [NotificationBellAction()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(walletProvider);
          ref.invalidate(pendingTeachersProvider);
          ref.invalidate(pendingTopUpsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Platform overview',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Signed in as ${user.email}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            statsAsync.when(
              data: (stats) => GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
                children: [
                  StatCard(
                    label: 'Total students',
                    value: '${stats.totalStudents ?? 0}',
                    icon: Icons.school_rounded,
                    color: AppColors.primary,
                  ),
                  StatCard(
                    label: 'Total teachers',
                    value: '${stats.totalTeachers ?? 0}',
                    icon: Icons.cast_for_education_rounded,
                    color: AppColors.secondary,
                  ),
                  StatCard(
                    label: 'Total courses',
                    value: '${stats.totalCourses ?? 0}',
                    icon: Icons.menu_book_rounded,
                    color: AppColors.accent,
                  ),
                  StatCard(
                    label: 'Platform revenue',
                    value: currency.format(stats.totalRevenue ?? 0),
                    icon: Icons.payments_rounded,
                    color: AppColors.error,
                  ),
                ],
              ),
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, __) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Could not load platform stats: $e',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            walletAsync.when(
              data: (wallet) => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your admin wallet (40% share)',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          Text(currency.format(wallet.balance),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Admin duties'),
            const SizedBox(height: 12),
            _DutyTile(
              icon: Icons.how_to_reg_rounded,
              label: 'Approve teachers',
              count: pendingTeachersAsync.asData?.value.length ?? 0,
              onTap: () => context.push('/admin/pending-teachers'),
            ),
            _DutyTile(
              icon: Icons.request_quote_rounded,
              label: 'Review wallet top-ups',
              count: pendingTopUpsAsync.asData?.value.length ?? 0,
              onTap: () => context.push('/admin/pending-topups'),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Quick links'),
            const SizedBox(height: 12),
            _LinkTile(
              icon: Icons.menu_book_outlined,
              label: 'Browse all courses',
              onTap: () => context.push('/courses'),
            ),
            _LinkTile(
              icon: Icons.cast_for_education_outlined,
              label: 'Approved teachers directory',
              onTap: () => context.push('/teachers'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DutyTile extends StatelessWidget {
  const _DutyTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: count > 0
            ? CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.error,
                child: Text(
                  '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
