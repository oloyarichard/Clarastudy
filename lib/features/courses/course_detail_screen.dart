import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/state_views.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/course_providers.dart';
import '../../providers/enrollment_providers.dart';
import '../../providers/payment_providers.dart';
import '../../providers/assessment_providers.dart';
import '../assessments/quiz_attempt_screen.dart';

class CourseDetailScreen extends ConsumerStatefulWidget {
  const CourseDetailScreen({super.key, required this.courseId});
  
  final String courseId;
  
  @override
  ConsumerState<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends ConsumerState<CourseDetailScreen> {
  bool _enrolling = false;
  
  Future<void> _enroll(Course course) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm payment'),
        content: Text(
          course.isFree
          ? 'Enroll in "${course.title}" for free?'
        : '${course.price.toStringAsFixed(2)} will be deducted from your '
        'wallet to enroll in "${course.title}". Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    
    setState(() => _enrolling = true);
    try {
      await ref.read(enrollmentRepositoryProvider).enrollAndPay(courseId: course.id);
      ref.invalidate(myEnrollmentsProvider);
      ref.invalidate(isEnrolledProvider(course.id));
      ref.invalidate(walletProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enrolled! Happy learning.')),
        );
      }
    } on ApiException catch (e) {
      if (e.statusCode == 402) {
        if (mounted) await _showTopUpDialog(e.fieldErrors);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not enroll right now.')),
        );
      }
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }
  
  /// Shown when the backend reports insufficient wallet balance (HTTP 402).
  /// Walks the student through sending money to the platform's mobile
  /// money wallet (MTN or Airtel), then submits a top-up request for an
  /// admin to approve.
  Future<void> _showTopUpDialog(Map<String, dynamic>? details) async {
    final mtnNumber = details?['momo_wallet_number']?.toString() ?? '';
    final airtelNumber = details?['airtel_merchant_number']?.toString() ?? '';
    final shortfall = details?['shortfall']?.toString() ?? '';
    final refController = TextEditingController();
    final amountController = TextEditingController(text: shortfall);
    String paymentMethod = 'mtn';
    
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final activeNumber = paymentMethod == 'mtn' ? mtnNumber : airtelNumber;
          final activeLabel = paymentMethod == 'mtn' ? 'MTN Mobile Money' : 'Airtel Money';
      
      return AlertDialog(
        title: const Text('Top up your wallet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose the network you sent from', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mtn', label: Text('MTN')),
                ButtonSegment(value: 'airtel', label: Text('Airtel')),
              ],
              selected: {paymentMethod},
              onSelectionChanged: (selected) => setDialogState(() => paymentMethod = selected.first),
            ),
            const SizedBox(height: 16),
            Text(
              'Your wallet balance is too low. Send at least \$$shortfall '
            '(USD) to $activeNumber via $activeLabel, then enter the '
            'transaction reference below. An admin will review and '
            'credit your wallet.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount sent (USD)',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: refController,
              decoration: const InputDecoration(labelText: 'Mobile payment reference ID'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              if (amount <= 0 || refController.text.trim().isEmpty) return;
              try {
                await ref.read(paymentRepositoryProvider).submitTopUpRequest(
                  amount: amount,
                  paymentMethod: paymentMethod,
                  momoReference: refController.text.trim(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Top-up request submitted — an admin will review it shortly.'),
                    ),
                  );
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not submit top-up request.')),
                  );
                }
              }
            },
            child: const Text('Submit'),
          ),
        ],
      );
        },
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final courseAsync = ref.watch(courseDetailProvider(widget.courseId));
    final user = ref.watch(authProvider).user;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Course details')),
      body: courseAsync.when(
        data: (course) => _buildBody(course, user),
        loading: () => const LoadingView(),
        error: (e, __) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(courseDetailProvider(widget.courseId)),
        ),
      ),
    );
  }
  
  Widget _buildBody(Course course, dynamic user) {
    final isOwner = user != null && user.id == course.teacherId;
    final isStudent = user != null && user.role == 'student';
    final enrollmentAsync =
    isStudent ? ref.watch(isEnrolledProvider(course.id)) : null;
    final quizzesAsync = ref.watch(quizzesForCourseProvider(course.id));
    
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(courseDetailProvider(widget.courseId)),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: double.infinity,
              height: 160,
              child: course.thumbnailUrl.isNotEmpty
              ? CachedNetworkImage(imageUrl: course.thumbnailUrl, fit: BoxFit.cover)
              : Container(
                color: AppColors.primary.withOpacity(0.1),
                child: const Icon(Icons.menu_book_rounded,
                                  size: 48, color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),Row(
            children: [
              StatusChip(
                label: course.level,
                color: AppColors.forRole(course.level == 'advanced' ? 'admin' : 'student'),
              ),
              const SizedBox(width: 8),
              Icon(Icons.star_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 2),
              Text('${course.rating.toStringAsFixed(1)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Icon(Icons.groups_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 2),
              Text('${course.totalStudents} students',
                   style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Text(course.title,
               style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
               const SizedBox(height: 8),
               Text(course.description, style: const TextStyle(color: AppColors.textSecondary)),
               const SizedBox(height: 20),
               if (isStudent && enrollmentAsync != null)
                 enrollmentAsync.when(
                   data: (enrollment) {
                     if (enrollment != null) {
                       return StatusChip(
                         label: 'Enrolled · ${enrollment.status}',
                         color: AppColors.secondary,
                       );
                     }
                     return PrimaryButton(
                       label: course.isFree
                       ? 'Enroll for free'
                     : 'Enroll · \$${course.price.toStringAsFixed(2)}',
                     isLoading: _enrolling,
                     onPressed: () => _enroll(course),
                     );
                   },
                   loading: () => const SizedBox(
                     height: 52,
                     child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                   ),
                   error: (e, __) => const SizedBox.shrink(),
                 ),
                 if (isOwner)
                   OutlinedButton.icon(
                     onPressed: () => _showAddModuleSheet(course.id),
                     icon: const Icon(Icons.add_rounded),
                     label: const Text('Add module'),
                   ),
                   const SizedBox(height: 24),
                   Text('Curriculum · ${course.totalLessons} lessons',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        if (course.modules.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('No modules published yet.',
                                        style: TextStyle(color: AppColors.textSecondary)),
                          )
                          else
                            ...course.modules.map((m) => _ModuleTile(module: m, isOwner: isOwner, course: course)),
                            const SizedBox(height: 24),
                            quizzesAsync.when(
                              data: (quizzes) {
                                if (quizzes.isEmpty) return const SizedBox.shrink();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Quizzes',
                                               style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                               const SizedBox(height: 10),
                                               ...quizzes.map(
                                                 (quiz) => Card(
                                                   margin: const EdgeInsets.only(bottom: 8),
                                                   child: ListTile(
                                                     leading: const Icon(Icons.quiz_rounded, color: AppColors.primary),
                                                     title: Text(quiz.title,
                                                                 style: const TextStyle(fontWeight: FontWeight.w600)),
                                                                 subtitle: Text('Passing score: ${quiz.passingScore}%'),
                                                                 trailing: const Icon(Icons.chevron_right_rounded),
                                                                 onTap: () => context.push('/quizzes/attempt', extra: quiz),
                                                   ),
                                                 ),
                                               ),
                                  ],
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (e, __) => const SizedBox.shrink(),
                            ),
        ],
      ),
    );
  }
  
  void _showAddModuleSheet(String courseId) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New module', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            AppTextField(controller: controller, label: 'Module title'),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Add module',
              onPressed: () async {
                if (controller.text.trim().isEmpty) return;
                try {
                  await ref.read(courseRepositoryProvider).createModule(
                    courseId: courseId,
                    title: controller.text.trim(),
                  );
                  ref.invalidate(courseDetailProvider(courseId));
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) {
                    final message = e is ApiException ? e.message : 'Failed to add module.';
            ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends ConsumerWidget {
  const _ModuleTile({required this.module, required this.isOwner, required this.course});
  
  final CourseModule module;
  final bool isOwner;
  final Course course;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(module.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${module.lessons.length} lessons'),
        children: [
          ...module.lessons.map(
            (lesson) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: Icon(
                    lesson.lessonType == 'video'
                  ? Icons.play_circle_outline_rounded
                  : lesson.lessonType == 'quiz'
                  ? Icons.quiz_outlined
                  : Icons.article_outlined,
                  color: AppColors.primary,
                  ),
                  title: Text(lesson.title),
                  subtitle: Text('${lesson.durationMinutes} min'
                  '${lesson.isFree ? ' · Free preview' : ''}'),
                  trailing: isOwner
                  ? IconButton(
                    icon: const Icon(Icons.attach_file_rounded, size: 20),
                    tooltip: 'Attach a file',
                    onPressed: () => _attachResource(context, ref, lesson.id),
                  )
                  : null,
                  onTap: () async {
                    if (lesson.videoUrl != null && lesson.videoUrl!.isNotEmpty) {
                      final uri = Uri.tryParse(lesson.videoUrl!);
                      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else if (lesson.content != null && context.mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(lesson.title),
                          content: SingleChildScrollView(child: Text(lesson.content!)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
                // Real, downloadable files attached to this lesson —
                // students get their own local copy, not just a link.
                if (lesson.resources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: lesson.resources.map((resource) {
                        return ActionChip(
                          avatar: Icon(
                            resource.resourceType == 'pdf'
                          ? Icons.picture_as_pdf_outlined
                          : resource.resourceType == 'video'
                          ? Icons.movie_outlined
                          : Icons.insert_drive_file_outlined,
                          size: 16,
                          ),
                          label: Text(resource.title, style: const TextStyle(fontSize: 12)),
                          onPressed: () => _openResource(context, ref, resource.id),);
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          if (isOwner)
            ListTile(
              leading: const Icon(Icons.add_rounded, color: AppColors.primary),
              title: const Text('Add lesson'),
              onTap: () => _showAddLessonSheet(context, ref, module.id),
            ),
        ],
      ),
    );
  }
  
  Future<void> _openResource(BuildContext context, WidgetRef ref, String resourceId) async {
    try {
      final fileUrl = await ref.read(resourceRepositoryProvider).checkResourceAccess(resourceId);
      final uri = Uri.tryParse(fileUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 403 && context.mounted) {
        await _promptEnrollment(context, ref);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this file.')),
        );
      }
    }
  }
  
  /// A condensed version of the full enroll flow on the course page
  /// itself — confirms payment and enrolls directly. If the wallet
  /// balance turns out to be insufficient, this points the student back
  /// to the course page's own "Enroll" button, which has the full
  /// top-up-request flow already built — not duplicated here to keep
  /// this dialog small.
  Future<void> _promptEnrollment(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enrollment required'),
        content: Text(
          course.isFree
          ? 'You need to enroll in "${course.title}" to access this resource. Enroll for free now?'
        : 'You need to enroll in "${course.title}" to access this resource. '
        '\$${course.price.toStringAsFixed(2)} will be deducted from your wallet. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enroll')),
        ],
      ),
    );
    if (confirmed != true) return;
    
    try {
      await ref.read(enrollmentRepositoryProvider).enrollAndPay(courseId: course.id);
      ref.invalidate(isEnrolledProvider(course.id));
      ref.invalidate(walletProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enrolled — try opening the file again.')),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        final message = e.statusCode == 402
        ? 'Insufficient wallet balance. Top up from the course page, then try again.'
        : e.message;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
  
  Future<void> _attachResource(BuildContext context, WidgetRef ref, String lessonId) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;
    final file = result.files.single;
    final extension = (file.extension ?? '').toLowerCase();
    final resourceType = extension == 'pdf'
    ? 'pdf'
    : ['mp4', 'mov', 'avi', 'mkv'].contains(extension)
    ? 'video'
    : 'document';
    
    try {
      await ref.read(resourceRepositoryProvider).uploadResource(
        title: file.name,
        resourceType: resourceType,
        filePath: file.path!,
        courseId: module.courseId,
        lessonId: lessonId,
      );
      ref.invalidate(courseDetailProvider(module.courseId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.name} attached.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is ApiException ? e.message : 'Could not attach the file.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
  
  void _showAddLessonSheet(BuildContext context, WidgetRef ref, String moduleId) {
    final titleController = TextEditingController();
    final videoController = TextEditingController();
    PlatformFile? pickedFile;
    bool submitting = false;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setLocalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New lesson', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                AppTextField(controller: titleController, label: 'Lesson title'),
                const SizedBox(height: 12),
                AppTextField(
                  controller: videoController,
                  label: 'Video URL (optional)',
                  hint: 'https://...',
                ),
                const SizedBox(height: 12),
                // A lesson can have a linked video URL, an attached
                // file (video/PDF/document the student downloads a
                // real local copy of), both, or neither — this is
                // purely optional, same as the URL field beside it.
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles();
                    if (result != null && result.files.single.path != null) {
                      setLocalState(() => pickedFile = result.files.single);
                    }
                  },
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(
                    pickedFile == null
                    ? 'Attach a file (optional)'
                  : pickedFile!.name,
                  overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Add lesson',
                  isLoading: submitting,
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) return;
                    setLocalState(() => submitting = true);
                    try {
                      final lesson = await ref.read(courseRepositoryProvider).createLesson(
                        moduleId: moduleId,
                        title: titleController.text.trim(),
                        videoUrl: videoController.text.trim().isEmpty
                        ? null
                        : videoController.text.trim(),
                      );
                      
                      if (pickedFile != null) {
                        final extension = (pickedFile!.extension ?? '').toLowerCase();
                        final resourceType = extension == 'pdf'
                ? 'pdf'
                : ['mp4', 'mov', 'avi', 'mkv'].contains(extension)
                ? 'video'
                : 'document';
                await ref.read(resourceRepositoryProvider).uploadResource(
                  title: pickedFile!.name,
                  resourceType: resourceType,
                  filePath: pickedFile!.path!,
                  courseId: module.courseId,
                  lessonId: lesson.id,
                );
                      }
                      
                      ref.invalidate(courseDetailProvider(module.courseId));
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    } catch (e) {
                      setLocalState(() => submitting = false);
                      if (sheetContext.mounted) {
                        final message =
                        e is ApiException ? e.message : 'Failed to add lesson.';
                ScaffoldMessenger.of(sheetContext)
                .showSnackBar(SnackBar(content: Text(message)));
                      }
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
