import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/core_providers.dart';
import '../../providers/dashboard_providers.dart';

/// Admin duty screen: teachers awaiting approval, with a one-tap approve.
class PendingTeachersScreen extends ConsumerWidget {
  const PendingTeachersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingTeachersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Approve teachers')),
      body: pendingAsync.when(
        data: (teachers) {
          if (teachers.isEmpty) {
            return const EmptyView(
              message: 'No teachers waiting for approval.',
              icon: Icons.how_to_reg_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: teachers.length,
            itemBuilder: (context, index) {
              final profile = teachers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: Text(
                      profile.user.displayName.isNotEmpty
                          ? profile.user.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(profile.user.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    profile.specialization?.isNotEmpty == true
                        ? profile.specialization!
                        : profile.user.email,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  trailing: FilledButton(
                    onPressed: () async {
                      try {
                        await ref.read(analyticsRepositoryProvider).approveTeacher(profile.id);
                        ref.invalidate(pendingTeachersProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${profile.user.displayName} approved')),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not approve teacher.')),
                          );
                        }
                      }
                    },
                    child: const Text('Approve'),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const LoadingView(),
        error: (e, __) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(pendingTeachersProvider),
        ),
      ),
    );
  }
}
