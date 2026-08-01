import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../models/live_class_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/course_providers.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/live_class_providers.dart';
import '../courses/widgets/course_card.dart';
import 'notification_bell_action.dart';

class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user!;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final myCoursesAsync = ref.watch(myTaughtCoursesProvider(user.id));
    final myLiveClassesAsync = ref.watch(myLiveClassesProvider(user.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Dashboard'),
        actions: const [NotificationBellAction()],
      ),
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
          ref.invalidate(myLiveClassesProvider(user.id));
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
                    icon: Icons.event_available_rounded,
                    label: 'My live classes',
                    onTap: () => context.push('/live-classes'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.upload_file_rounded,
                    label: 'Upload resource',
                    onTap: () => context.push('/resources/upload'),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox.shrink()),
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
            const SizedBox(height: 28),
            const SectionHeader(title: 'My live classes'),
            const SizedBox(height: 12),
            myLiveClassesAsync.when(
              data: (classes) {
                if (classes.isEmpty) {
                  return const EmptyView(
                    message: "You haven't scheduled any live classes yet.",
                    icon: Icons.live_tv_outlined,
                  );
                }
                return Column(
                  children: classes
                      .map((c) => _LiveClassManageTile(liveClass: c, teacherId: user.id))
                      .toList(),
                );
              },
              loading: () => const LoadingView(),
              error: (e, __) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(myLiveClassesProvider(user.id)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveClassManageTile extends ConsumerStatefulWidget {
  const _LiveClassManageTile({required this.liveClass, required this.teacherId});

  final LiveClass liveClass;
  final String teacherId;

  @override
  ConsumerState<_LiveClassManageTile> createState() => _LiveClassManageTileState();
}

class _LiveClassManageTileState extends ConsumerState<_LiveClassManageTile> {
  bool _busy = false;

  Color get _statusColor {
    switch (widget.liveClass.status) {
      case 'live':
        return AppColors.error;
      case 'ended':
        return AppColors.textSecondary;
      default:
        return AppColors.secondary;
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this class?'),
        content: Text('"${widget.liveClass.title}" will be permanently removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(liveClassRepositoryProvider).deleteLiveClass(widget.liveClass.id);
      ref.invalidate(myLiveClassesProvider(widget.teacherId));
      ref.invalidate(liveClassesListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live class deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not delete the class.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveClass = widget.liveClass;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(liveClass.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                StatusChip(
                  label: liveClass.status == 'live' ? '● LIVE' : liveClass.status,
                  color: _statusColor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_busy)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/live-classes/${liveClass.id}'),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (liveClass.status != 'live') ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                      tooltip: 'Delete',
                    ),
                  ],
                ],
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
