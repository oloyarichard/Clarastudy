import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/dashboard_providers.dart';

class TeachersListScreen extends ConsumerWidget {
  const TeachersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teachersAsync = ref.watch(teachersListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Teachers')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(teachersListProvider),
        child: teachersAsync.when(
          data: (teachers) {
            if (teachers.isEmpty) {
              return const EmptyView(
                message: 'No teacher profiles yet.',
                icon: Icons.cast_for_education_outlined,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: teachers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final teacher = teachers[index];
                return Card(
                  child: ListTile(
                    leading: InitialsAvatar(
                      name: teacher.user.displayName,
                      role: 'teacher',
                      imageUrl: teacher.user.profilePictureUrl,
                    ),
                    title: Text(teacher.user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      teacher.specialization?.isNotEmpty == true
                          ? teacher.specialization!
                          : teacher.user.email,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        StatusChip(
                          label: teacher.isApproved ? 'Approved' : 'Pending',
                          color: teacher.isApproved ? AppColors.secondary : AppColors.accent,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
                            const SizedBox(width: 2),
                            Text(teacher.rating.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 12)),
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
            onRetry: () => ref.invalidate(teachersListProvider),
          ),
        ),
      ),
    );
  }
}
