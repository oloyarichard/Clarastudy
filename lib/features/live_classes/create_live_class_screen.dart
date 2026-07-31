import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/course_providers.dart';
import '../../providers/live_class_providers.dart';

class CreateLiveClassScreen extends ConsumerStatefulWidget {
  const CreateLiveClassScreen({super.key});
  
  @override
  ConsumerState<CreateLiveClassScreen> createState() => _CreateLiveClassScreenState();
}

class _CreateLiveClassScreenState extends ConsumerState<CreateLiveClassScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 1));
  String? _selectedCourseId;
  bool _submitting = false;
  
  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    super.dispose();
  }
  
  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }
  
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authProvider).user;
    if (user == null) return;
    if (_selectedCourseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick which course this class is for.')),
      );
      return;
    }
    
    setState(() => _submitting = true);
    try {
      final roomId = 'room-${DateTime.now().millisecondsSinceEpoch}';
      final created = await ref.read(liveClassRepositoryProvider).createLiveClass(
        teacherId: user.id,
        courseId: _selectedCourseId!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        scheduledAt: _scheduledAt,
        durationMinutes: int.tryParse(_durationController.text.trim()) ?? 60,
        roomId: roomId,
      );
      ref.invalidate(liveClassesListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live class scheduled!')),
        );
        // Go straight into the class's own screen — that's where the
        // teacher finds the "Start class" button, rather than leaving
        // them to hunt for it back in a list.
        context.pushReplacement('/live-classes/${created.id}');
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not schedule the class.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('EEE, MMM d, yyyy · h:mm a');
    
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule live class')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Course', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Consumer(
                  builder: (context, ref, _) {
                    final user = ref.watch(authProvider).user;
                    if (user == null) return const SizedBox.shrink();
                    final coursesAsync = ref.watch(myTaughtCoursesProvider(user.id));
                    return coursesAsync.when(
                      data: (courses) {
                        if (courses.isEmpty) {
                          return const Text(
                            'Create a course first — a live class must belong to one.',
                            style: TextStyle(color: AppColors.textSecondary),
                          );
                        }
                        return DropdownButtonFormField<String>(
                          initialValue: _selectedCourseId,
                          decoration: const InputDecoration(
                            hintText: 'Only students enrolled in this course can join',
                          ),
                          items: courses
                          .map((Course c) => DropdownMenuItem(value: c.id, child: Text(c.title)))
                          .toList(),
                          onChanged: (value) => setState(() => _selectedCourseId = value),
                          validator: (v) => v == null ? 'Pick a course' : null,
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, __) => Text('$e', style: const TextStyle(color: AppColors.error)),
                    );
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _titleController,
                  label: 'Class title',
                  validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _descriptionController,
                  label: 'Description (optional)',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text('Scheduled for', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickDateTime,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Text(formatter.format(_scheduledAt)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _durationController,
                  label: 'Duration (minutes)',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.timer_outlined,
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Schedule class',
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
