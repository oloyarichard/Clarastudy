import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/auth_provider.dart';
import '../../providers/course_providers.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/enrollment_providers.dart';
import '../courses/widgets/course_card.dart';
import 'notification_bell_action.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user!;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final enrollmentsAsync = ref.watch(myEnrollmentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Home'), actions: const [NotificationBellAction()]),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(myEnrollmentsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Hi, ${user.firstName.isNotEmpty ? user.firstName : user.username}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              "Here's what's happening with your learning.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            statsAsync.when(
              data: (stats) => Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Enrolled courses',
                      value: '${stats.enrolledCourses ?? 0}',
                      icon: Icons.menu_book_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Completed',
                      value: '${stats.completedCourses ?? 0}',
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
              loading: () => const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),
            _QuickActionsRow(items: [
              _QuickAction(
                icon: Icons.live_tv_rounded,
                label: 'Live classes',
                onTap: () => context.push('/live-classes'),
              ),
              _QuickAction(
                icon: Icons.quiz_rounded,
                label: 'Quizzes',
                onTap: () => context.push('/quizzes'),
              ),
              _QuickAction(
                icon: Icons.workspace_premium_rounded,
                label: 'Certificates',
                onTap: () => context.push('/certificates'),
              ),
              _QuickAction(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Wallet',
                onTap: () => context.push('/wallet'),
              ),
            ]),
            const SizedBox(height: 28),
            SectionHeader(
              title: 'Continue learning',
              actionLabel: 'See all',
              onAction: () => context.push('/courses'),
            ),
            const SizedBox(height: 12),
            enrollmentsAsync.when(
              data: (enrollments) {
                if (enrollments.isEmpty) {
                  return EmptyView(
                    message: "You haven't enrolled in any courses yet.",
                    icon: Icons.menu_book_outlined,
                    actionLabel: 'Browse courses',
                    onAction: () => context.push('/courses'),
                  );
                }
                return Column(
                  children: enrollments.take(5).map((enrollment) {
                    final courseAsync =
                        ref.watch(courseDetailProvider(enrollment.courseId));
                    return courseAsync.when(
                      data: (course) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CourseCard(
                          course: course,
                          statusLabel: enrollment.status,
                          onTap: () => context.push('/courses/${course.id}'),
                        ),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (e, __) => const SizedBox.shrink(),
                    );
                  }).toList(),
                );
              },
              loading: () => const LoadingView(),
              error: (e, __) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(myEnrollmentsProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.items});
  final List<_QuickAction> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: item.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.cardLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Icon(item.icon, color: AppColors.primary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
