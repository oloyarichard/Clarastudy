import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/assessment_providers.dart';
import '../../providers/course_providers.dart';

class CertificatesScreen extends ConsumerWidget {
  const CertificatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certificatesAsync = ref.watch(myCertificatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Certificates')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myCertificatesProvider),
        child: certificatesAsync.when(
          data: (certificates) {
            if (certificates.isEmpty) {
              return const EmptyView(
                message: 'Complete a course to earn your first certificate.',
                icon: Icons.workspace_premium_outlined,
              );
            }
            final formatter = DateFormat('MMM d, yyyy');
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: certificates.length,
              itemBuilder: (context, index) {
                final cert = certificates[index];
                final courseAsync = ref.watch(courseDetailProvider(cert.courseId));
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium_rounded,
                        color: AppColors.accent, size: 32),
                    title: Text(
                      courseAsync.asData?.value.title ?? 'Certificate',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${cert.certificateNumber}'
                      '${cert.issueDate != null ? ' · ${formatter.format(cert.issueDate!)}' : ''}',
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const LoadingView(),
          error: (e, __) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(myCertificatesProvider),
          ),
        ),
      ),
    );
  }
}
