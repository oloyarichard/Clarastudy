import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_providers.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user!;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final currency = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Overview')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardStatsProvider),
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
                childAspectRatio: 1.3,
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
                    label: 'Total revenue',
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
            const SizedBox(height: 28),
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
            _LinkTile(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              onTap: () => context.push('/notifications'),
            ),
          ],
        ),
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
