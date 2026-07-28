import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/assessment_providers.dart';

class QuizListScreen extends ConsumerWidget {
  const QuizListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizzesAsync = ref.watch(quizzesListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Quizzes')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(quizzesListProvider),
        child: quizzesAsync.when(
          data: (quizzes) {
            if (quizzes.isEmpty) {
              return const EmptyView(
                message: 'No quizzes are available yet.',
                icon: Icons.quiz_outlined,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: quizzes.length,
              itemBuilder: (context, index) {
                final quiz = quizzes[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.quiz_rounded, color: AppColors.primary),
                    title: Text(quiz.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      quiz.description?.isNotEmpty == true
                          ? quiz.description!
                          : 'Passing score: ${quiz.passingScore}%',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/quizzes/attempt', extra: quiz),
                  ),
                );
              },
            );
          },
          loading: () => const LoadingView(),
          error: (e, __) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(quizzesListProvider),
          ),
        ),
      ),
    );
  }
}
