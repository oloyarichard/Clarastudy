import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../models/assessment_models.dart';
import '../../providers/assessment_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';

/// NOTE: the backend's /api/assessments/ endpoints expose quizzes,
/// attempts, and certificates, but do not expose an endpoint for a
/// quiz's individual questions. So rather than fabricating a fake
/// question-answering flow that isn't backed by real data, this screen
/// lets the student record the score they achieved (e.g. after taking
/// the quiz in class or via an external tool) and submits that as a
/// formal quiz attempt. If a /questions/ endpoint is added later, swap
/// this out for a real multi-question flow.
class QuizAttemptScreen extends ConsumerStatefulWidget {
  const QuizAttemptScreen({super.key, required this.quiz});

  final Quiz quiz;

  @override
  ConsumerState<QuizAttemptScreen> createState() => _QuizAttemptScreenState();
}

class _QuizAttemptScreenState extends ConsumerState<QuizAttemptScreen> {
  double _score = 70;
  bool _submitting = false;
  bool _submitted = false;

  Future<void> _submit() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _submitting = true);
    try {
      final isPassed = _score >= widget.quiz.passingScore;
      await ref.read(assessmentRepositoryProvider).submitAttempt(
            quizId: widget.quiz.id,
            studentId: user.id,
            score: _score.round(),
            isPassed: isPassed,
          );
      ref.invalidate(myCertificatesProvider);
      setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not submit your attempt.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;
    final willPass = _score >= quiz.passingScore;

    return Scaffold(
      appBar: AppBar(title: Text(quiz.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (quiz.description != null && quiz.description!.isNotEmpty) ...[
                Text(quiz.description!, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  const Icon(Icons.flag_rounded, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('Passing score: ${quiz.passingScore}%',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 28),
              if (_submitted) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: (willPass ? AppColors.secondary : AppColors.error).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        willPass ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: willPass ? AppColors.secondary : AppColors.error,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        willPass ? 'Attempt recorded — you passed!' : 'Attempt recorded — try again',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text('Score: ${_score.round()}%'),
                    ],
                  ),
                ),
              ] else ...[
                const Text(
                  'Record your score',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Enter the score you achieved on this quiz to log an official attempt.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '${_score.round()}%',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: willPass ? AppColors.secondary : AppColors.error,
                    ),
                  ),
                ),
                Slider(
                  value: _score,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${_score.round()}%',
                  onChanged: (v) => setState(() => _score = v),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Submit attempt',
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
