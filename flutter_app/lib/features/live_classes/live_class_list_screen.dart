import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../models/live_class_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/live_class_providers.dart';

class LiveClassListScreen extends ConsumerWidget {
  const LiveClassListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveClassesAsync = ref.watch(liveClassesListProvider);
    final user = ref.watch(authProvider).user;
    final isTeacher = user?.role == 'teacher';

    return Scaffold(
      appBar: AppBar(title: const Text('Live classes')),
      floatingActionButton: isTeacher
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/live-classes/create'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Schedule'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(liveClassesListProvider),
        child: liveClassesAsync.when(
          data: (classes) {
            if (classes.isEmpty) {
              return const EmptyView(
                message: 'No live classes scheduled yet.',
                icon: Icons.live_tv_outlined,
              );
            }
            final sorted = [...classes]..sort((a, b) {
                final aTime = a.scheduledAt ?? DateTime(2100);
                final bTime = b.scheduledAt ?? DateTime(2100);
                return aTime.compareTo(bTime);
              });
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final liveClass = sorted[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LiveClassCard(liveClass: liveClass),
                );
              },
            );
          },
          loading: () => const LoadingView(),
          error: (e, __) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(liveClassesListProvider),
          ),
        ),
      ),
    );
  }
}

class _LiveClassCard extends StatelessWidget {
  const _LiveClassCard({required this.liveClass});

  final LiveClass liveClass;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('EEE, MMM d · h:mm a');
    final statusColor = switch (liveClass.status) {
      'live' => AppColors.error,
      'ended' => AppColors.textSecondary,
      _ => AppColors.secondary,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/live-classes/${liveClass.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      liveClass.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  StatusChip(
                    label: liveClass.status == 'live' ? '● LIVE' : liveClass.status,
                    color: statusColor,
                  ),
                ],
              ),
              if (liveClass.description != null && liveClass.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  liveClass.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    liveClass.scheduledAt != null
                        ? formatter.format(liveClass.scheduledAt!.toLocal())
                        : 'Not scheduled',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.timer_outlined, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('${liveClass.durationMinutes} min',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
