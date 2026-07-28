import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                InitialsAvatar(
                  name: user.displayName,
                  role: user.role,
                  radius: 40,
                  imageUrl: user.profilePictureUrl,
                ),
                const SizedBox(height: 14),
                Text(
                  user.displayName,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(user.email, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                StatusChip(
                  label: user.role.toUpperCase(),
                  color: AppColors.forRole(user.role),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: AppColors.primary),
                  title: const Text('Edit profile'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/profile/edit'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined,
                      color: AppColors.primary),
                  title: const Text('Wallet & payments'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/wallet'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined,
                      color: AppColors.primary),
                  title: const Text('Certificates'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/certificates'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded,
                      color: AppColors.primary),
                  title: const Text('Messages'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/chat/rooms'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_outlined, color: AppColors.primary),
                  title: const Text('Learning resources'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/resources'),
                ),
                if (user.isAdmin) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cast_for_education_outlined,
                        color: AppColors.primary),
                    title: const Text('Teachers directory'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/teachers'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('You will need to log in again to continue.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(authProvider.notifier).logout();
              }
            },
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            label: const Text('Log out', style: TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
