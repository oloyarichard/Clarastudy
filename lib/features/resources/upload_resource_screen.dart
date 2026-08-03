import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/course_providers.dart';
import '../../providers/resource_providers.dart';

class UploadResourceScreen extends ConsumerStatefulWidget {
  const UploadResourceScreen({super.key});

  @override
  ConsumerState<UploadResourceScreen> createState() => _UploadResourceScreenState();
}

class _UploadResourceScreenState extends ConsumerState<UploadResourceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _resourceType = 'document';
  PlatformFile? _file;
  bool _submitting = false;
  String? _selectedCourseId;

  static const _types = ['document', 'pdf', 'video'];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      setState(() => _file = result.files.first);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_file?.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a file to upload.')),
      );
      return;
    }
    if (_selectedCourseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Every resource must belong to a course — please pick one.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(resourceRepositoryProvider).uploadResource(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            resourceType: _resourceType,
            filePath: _file!.path!,
            courseId: _selectedCourseId!,
          );
      ref.invalidate(resourcesListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resource uploaded!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not upload the resource.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload resource')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _titleController,
                  label: 'Title',
                  validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final teacherId = ref.watch(authProvider).user?.id ?? '';
                    final coursesAsync = ref.watch(myTaughtCoursesProvider(teacherId));
                    return coursesAsync.when(
                      data: (courses) {
                        return DropdownButtonFormField<String>(
                          initialValue: _selectedCourseId,
                          decoration: const InputDecoration(
                            hintText: 'Select a course',
                            helperText: 'Every resource belongs to a course.',
                          ),
                          items: courses
                              .map((Course c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.title, overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => _selectedCourseId = value),
                          validator: (v) => v == null ? 'Please select a course' : null,
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, __) => Text('Could not load your courses: $e'),
                    );
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _descriptionController,
                  label: 'Description (optional)',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text('Type', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _types.map((type) {
                    final selected = _resourceType == type;
                    return ChoiceChip(
                      label: Text(type[0].toUpperCase() + type.substring(1)),
                      selected: selected,
                      onSelected: (_) => setState(() => _resourceType = type),
                      selectedColor: AppColors.primary.withOpacity(0.15),
                      labelStyle: TextStyle(
                        color: selected ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickFile,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file_rounded, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _file?.name ?? 'Choose a file to upload',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _file != null
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Upload',
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
