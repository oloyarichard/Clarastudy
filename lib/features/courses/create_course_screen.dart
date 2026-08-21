import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_constants.dart';
import '../../core/widgets/app_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/course_providers.dart';

class CreateCourseScreen extends ConsumerStatefulWidget {
  const CreateCourseScreen({super.key});

  @override
  ConsumerState<CreateCourseScreen> createState() => _CreateCourseScreenState();
}

class _CreateCourseScreenState extends ConsumerState<CreateCourseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  double _price = CoursePriceTiers.values.first;
  String _level = 'beginner';
  XFile? _thumbnail;
  bool _submitting = false;
  double? _uploadProgress;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickThumbnail() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _thumbnail = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() {
      _submitting = true;
      _uploadProgress = _thumbnail != null ? 0 : null;
    });
    try {
      final course = await ref.read(courseRepositoryProvider).createCourse(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            teacherId: user.id,
            level: _level,
            price: _price,
            thumbnailPath: _thumbnail?.path,
            onProgress: _thumbnail == null
                ? null
                : (p) {
                    if (mounted) setState(() => _uploadProgress = p);
                  },
          );
      ref.invalidate(myTaughtCoursesProvider(user.id));
      ref.invalidate(coursesListProvider);
      if (mounted) {
        context.pushReplacement('/courses/${course.id}');
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not create the course.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create a course')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _pickThumbnail,
                  child: Container(
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.cardLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: _thumbnail != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: kIsWeb
                                ? Image.network(_thumbnail!.path, fit: BoxFit.cover)
                                : Image.file(File(_thumbnail!.path), fit: BoxFit.cover),
                          )
                        : _thumbnailPlaceholder(),
                  ),
                ),
                const SizedBox(height: 20),
                AppTextField(
                  controller: _titleController,
                  label: 'Course title',
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  maxLines: 4,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Description is required' : null,
                ),
                const SizedBox(height: 16),
                const Text('Level', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['beginner', 'intermediate', 'advanced'].map((level) {
                    final selected = _level == level;
                    return ChoiceChip(
                      label: Text(level[0].toUpperCase() + level.substring(1)),
                      selected: selected,
                      onSelected: (_) => setState(() => _level = level),
                      selectedColor: AppColors.primary.withOpacity(0.15),
                      labelStyle: TextStyle(
                        color: selected ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Price', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: CoursePriceTiers.values.map((tier) {
                    final selected = _price == tier;
                    return ChoiceChip(
                      label: Text(tier == 0 ? 'Free' : '\$${tier.toStringAsFixed(2)}'),
                      selected: selected,
                      onSelected: (_) => setState(() => _price = tier),
                      selectedColor: AppColors.primary.withOpacity(0.15),
                      labelStyle: TextStyle(
                        color: selected ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                if (_uploadProgress != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _uploadProgress,
                      minHeight: 6,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                PrimaryButton(
                  label: 'Create course',
                  isLoading: _submitting,
                  progress: _uploadProgress,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnailPlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary, size: 32),
          SizedBox(height: 6),
          Text('Add a course thumbnail', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
