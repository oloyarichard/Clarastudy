import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../models/user_models.dart';
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
            final approved = teachers.where((t) => t.isApproved).toList()
            ..sort((a, b) => b.rating.compareTo(a.rating));
            final pending = teachers.where((t) => !t.isApproved).toList();
            
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (approved.isNotEmpty) ...[
                  _SectionLabel(text: 'Approved · ${approved.length}'),
                  const SizedBox(height: 10),
                  ...approved.map((t) => _TeacherCard(teacher: t)),
                  const SizedBox(height: 24),
                ],
                if (pending.isNotEmpty) ...[
                  _SectionLabel(text: 'Awaiting approval · ${pending.length}'),
                  const SizedBox(height: 10),
                  ...pending.map((t) => _TeacherCard(teacher: t)),
                ],
              ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;
  
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.teacher});
  final TeacherProfile teacher;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(
                name: teacher.user.displayName,
                role: 'teacher',
                imageUrl: teacher.user.profilePictureUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teacher.user.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      teacher.specialization?.isNotEmpty == true
                      ? teacher.specialization!
                      : teacher.user.email,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusChip(
                label: teacher.isApproved ? 'Approved' : 'Pending',
                color: teacher.isApproved ? AppColors.secondary : AppColors.accent,
              ),
            ],
          ),
          if (teacher.qualifications?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              teacher.qualifications!,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatBit(
                icon: Icons.star_rounded,
                label: teacher.totalReviews > 0
                ? '${teacher.rating.toStringAsFixed(1)} (${teacher.totalReviews})'
              : 'No reviews yet',
              color: AppColors.accent,
              ),
              const SizedBox(width: 16),
              _StatBit(
                icon: Icons.work_history_rounded,
                label: teacher.yearsOfExperience == 1
                ? '1 year'
              : '${teacher.yearsOfExperience} years',
              color: AppColors.primary,
              ),
              if (teacher.hourlyRate > 0) ...[
                const SizedBox(width: 16),
                _StatBit(
                  icon: Icons.payments_outlined,
                  label: '\$${teacher.hourlyRate.toStringAsFixed(0)}/hr',
                  color: AppColors.secondary,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBit extends StatelessWidget {
  const _StatBit({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
