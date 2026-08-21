import 'package:dio/dio.dart';

import '../core/network/api_client.dart';
import '../core/network/api_config.dart';
import '../core/storage/token_storage.dart';
import '../models/user_models.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokenStorage);

  final ApiClient _api;
  final TokenStorage _tokenStorage;

  Future<AppUser> login({required String email, required String password}) async {
    final response = await _api.post(ApiConfig.login, data: {
      'email': email,
      'password': password,
    });
    final data = response.data as Map<String, dynamic>;
    await _tokenStorage.saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
    );
    return fetchProfile();
  }

  Future<AppUser> register({
    required String email,
    required String username,
    required String firstName,
    required String lastName,
    required String password,
    required String passwordConfirm,
    required String role,
    String? phoneNumber,
  }) async {
    await _api.post(ApiConfig.register, data: {
      'email': email,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'password': password,
      'password_confirm': passwordConfirm,
      'role': role,
      if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
    });
    // Registration doesn't return tokens, so log in right after.
    return login(email: email, password: password);
  }

  Future<AppUser> fetchProfile() async {
    final response = await _api.get(ApiConfig.profile);
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  /// Updates the profile. If [profilePicturePath] is provided, the
  /// request is sent as multipart/form-data so the image file can ride
  /// along with the text fields; otherwise a plain JSON PATCH is used.
  /// [onProgress] only fires when [profilePicturePath] is set — a plain
  /// text-only PATCH has nothing worth showing progress for.
  Future<AppUser> updateProfile({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? bio,
    String? country,
    String? city,
    String? profilePicturePath,
    void Function(double progress)? onProgress,
  }) async {
    final fields = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (bio != null) 'bio': bio,
      if (country != null) 'country': country,
      if (city != null) 'city': city,
    };

    final response = profilePicturePath != null
        ? await _api.patchMultipart(
            ApiConfig.profile,
            {
              ...fields,
              'profile_picture': await MultipartFile.fromFile(profilePicturePath),
            },
            onSendProgress: onProgress == null
                ? null
                : (sent, total) {
                    if (total > 0) onProgress(sent / total);
                  },
          )
        : await _api.patch(ApiConfig.profile, data: fields);

    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  Future<bool> hasSession() => _tokenStorage.hasTokens();

  Future<void> logout() => _tokenStorage.clear();

  /// Always succeeds from the app's point of view (matches the
  /// backend's deliberate behavior of not revealing whether an email
  /// is actually registered) — the real signal is whether an email
  /// shows up.
  Future<void> requestPasswordReset(String email) async {
    await _api.post(ApiConfig.passwordResetRequest, data: {'email': email});
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _api.post(ApiConfig.passwordResetConfirm, data: {
      'email': email,
      'code': code,
      'new_password': newPassword,
    });
  }
}
