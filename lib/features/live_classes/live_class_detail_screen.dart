import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/daily_call_session_provider.dart';
import '../../providers/live_class_providers.dart';
import 'daily_call_screen.dart';

/// Shows a live class's details and a "Join class" button. Chat now
/// lives entirely inside the call itself (see DailyCallScreen's chat
/// FAB) — this screen used to also show the class's full chat history
/// and its own message box before you'd even joined, which is removed
/// on purpose: chat is an in-call feature now, not something visible
/// before joining.
class LiveClassDetailScreen extends ConsumerStatefulWidget {
  const LiveClassDetailScreen({super.key, required this.liveClassId});

  final String liveClassId;

  @override
  ConsumerState<LiveClassDetailScreen> createState() => _LiveClassDetailScreenState();
}

class _LiveClassDetailScreenState extends ConsumerState<LiveClassDetailScreen> {
  bool _joining = false;

  Future<void> _joinCall(String title) async {
    final session = ref.read(dailyCallSessionProvider);

    // Already in this exact class's call (e.g. it's minimized) — just
    // reopen the full-screen view, no need to fetch new credentials.
    if (session.hasActiveCall && session.liveClassId == widget.liveClassId) {
      session.maximize();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DailyCallScreen(
            liveClassId: widget.liveClassId,
            liveClassTitle: title,
          ),
          fullscreenDialog: true,
        ),
      );
      return;
    }

    // In a DIFFERENT class's call — confirm before dropping it.
    if (session.hasActiveCall && session.liveClassId != widget.liveClassId) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Leave current call?'),
          content: Text(
            'You\'re still in "${session.liveClassTitle}". Leave it to join "$title" instead?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave & join')),
          ],
        ),
      );
      if (confirmed != true) return;
      await session.leave();
    }

    setState(() => _joining = true);
    try {
      final creds = await ref
          .read(liveClassRepositoryProvider)
          .getDailyCredentials(widget.liveClassId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DailyCallScreen(
            liveClassId: widget.liveClassId,
            liveClassTitle: title,
            credentials: creds,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      if (mounted) {
        String message = 'Could not join the call.';
        if (e is ApiException) {
          final backendError = e.fieldErrors?['error'];
          message = backendError is String ? backendError : e.message;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesAsync = ref.watch(liveClassesListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Live class')),
      body: classesAsync.when(
        data: (classes) {
          final matches = classes.where((c) => c.id == widget.liveClassId);
          final liveClass = matches.isEmpty ? null : matches.first;
          if (liveClass == null) {
            return const ErrorView(message: 'This live class could not be found.');
          }
          final formatter = DateFormat('EEEE, MMM d · h:mm a');

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(liveClass.title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    StatusChip(
                      label: liveClass.status == 'live' ? '● LIVE' : liveClass.status,
                      color: liveClass.isLive ? AppColors.error : AppColors.secondary,
                    ),
                  ],
                ),
                if (liveClass.description != null) ...[
                  const SizedBox(height: 8),
                  Text(liveClass.description!,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 12),
                if (liveClass.scheduledAt != null)
                  Text(formatter.format(liveClass.scheduledAt!.toLocal()),
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: liveClass.isEnded
                      ? 'Class ended'
                      : (_joining ? 'Joining…' : 'Join class'),
                  icon: Icons.videocam_rounded,
                  onPressed: (liveClass.isEnded || _joining)
                      ? null
                      : () => _joinCall(liveClass.title),
                ),
              ],
            ),
          );
        },
        loading: () => const LoadingView(),
        error: (e, __) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(liveClassesListProvider),
        ),
      ),
    );
  }
}
