import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/auth_provider.dart';
import '../../providers/course_providers.dart';
import '../../providers/dashboard_providers.dart';
import '../courses/widgets/course_card.dart';

class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user!;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final myCoursesAsync = ref.watch(myTaughtCoursesProvider(user.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Teacher Dashboard')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create-course-fab',
        onPressed: () => context.push('/courses/create'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New course'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(myTaughtCoursesProvider(user.id));
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Welcome, ${user.firstName.isNotEmpty ? user.firstName : user.username}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage your courses and connect with students.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            statsAsync.when(
              data: (stats) => Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'My courses',
                      value: '${stats.myCourses ?? myCoursesAsync.asData?.value.length ?? 0}',
                      icon: Icons.menu_book_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'My students',
                      value: '${stats.totalStudents ?? 0}',
                      icon: Icons.groups_rounded,
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
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.live_tv_rounded,
                    label: 'Schedule live class',
                    onTap: () => context.push('/live-classes/create'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.upload_file_rounded,
                    label: 'Upload resource',
                    onTap: () => context.push('/resources/upload'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'My courses'),
            const SizedBox(height: 12),
            myCoursesAsync.when(
              data: (courses) {
                if (courses.isEmpty) {
                  return EmptyView(
                    message: "You haven't created any courses yet.",
                    icon: Icons.menu_book_outlined,
                    actionLabel: 'Create your first course',
                    onAction: () => context.push('/courses/create'),
                  );
                }
                return Column(
                  children: courses
                      .map(
                        (course) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: CourseCard(
                            course: course,
                            onTap: () => context.push('/courses/${course.id}'),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
              loading: () => const LoadingView(),
              error: (e, __) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(myTaughtCoursesProvider(user.id)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
