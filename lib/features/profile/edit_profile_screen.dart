import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _bioController;
  late final TextEditingController _countryController;
  late final TextEditingController _cityController;
  XFile? _newPicture;
  bool _submitting = false;
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _lastNameController = TextEditingController(text: user?.lastName ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _countryController = TextEditingController(text: user?.country ?? '');
    _cityController = TextEditingController(text: user?.city ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _countryController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _newPicture = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      // Only a picture upload has real bytes to track — a text-only save
      // has nothing for a progress bar to measure, so leave it null and
      // PrimaryButton falls back to its plain indeterminate spinner.
      _uploadProgress = _newPicture != null ? 0 : null;
    });
    try {
      final updated = await ref.read(authRepositoryProvider).updateProfile(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
            bio: _bioController.text.trim(),
            country: _countryController.text.trim(),
            city: _cityController.text.trim(),
            profilePicturePath: _newPicture?.path,
            onProgress: _newPicture == null
                ? null
                : (p) {
                    if (mounted) setState(() => _uploadProgress = p);
                  },
          );
      ref.read(authProvider.notifier).updateLocalUser(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.message : 'Could not update profile.';
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
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickPicture,
                  child: Stack(
                    children: [
                      _newPicture != null
                          ? CircleAvatar(
                              radius: 44,
                              backgroundImage: kIsWeb
                                  ? NetworkImage(_newPicture!.path)
                                  : FileImage(File(_newPicture!.path)) as ImageProvider,
                            )
                          : InitialsAvatar(
                              name: user?.displayName ?? '',
                              role: user?.role ?? 'student',
                              radius: 44,
                              imageUrl: user?.profilePictureUrl,
                            ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(controller: _firstNameController, label: 'First name'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(controller: _lastNameController, label: 'Last name'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _phoneController,
                label: 'Phone number',
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_outlined,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _bioController,
                label: 'Bio',
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(controller: _countryController, label: 'Country'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(controller: _cityController, label: 'City'),
                  ),
                ],
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
                label: 'Save changes',
                isLoading: _submitting,
                progress: _uploadProgress,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
