import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../models/resource_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/resource_providers.dart';

class ResourceListScreen extends ConsumerWidget {
  const ResourceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resourcesAsync = ref.watch(resourcesListProvider);
    final user = ref.watch(authProvider).user;
    final canUpload = user?.isTeacher == true || user?.isAdmin == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Resources')),
      floatingActionButton: canUpload
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/resources/upload'),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Upload'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(resourcesListProvider),
        child: resourcesAsync.when(
          data: (resources) {
            if (resources.isEmpty) {
              return const EmptyView(
                message: 'No learning resources have been shared yet.',
                icon: Icons.folder_open_rounded,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: resources.length,
              itemBuilder: (context, index) {
                final resource = resources[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ResourceTile(resource: resource),
                );
              },
            );
          },
          loading: () => const LoadingView(),
          error: (e, __) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(resourcesListProvider),
          ),
        ),
      ),
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({required this.resource});

  final Resource resource;

  IconData get _icon {
    switch (resource.resourceType) {
      case 'video':
        return Icons.play_circle_outline_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_icon, color: AppColors.primary),
        ),
        title: Text(resource.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: resource.description != null && resource.description!.isNotEmpty
            ? Text(resource.description!, maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        trailing: resource.isDownloadable
            ? const Icon(Icons.download_rounded, color: AppColors.primary)
            : null,
        onTap: resource.fileUrl.isEmpty
            ? null
            : () async {
                final uri = Uri.tryParse(resource.fileUrl);
                if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
      ),
    );
  }
}
