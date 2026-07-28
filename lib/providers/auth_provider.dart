import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../data/auth_repository.dart';
import '../models/user_models.dart';
import 'core_providers.dart';

enum AuthStatus { unknown, authenticating, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.errorMessage,
  });

  final AuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repo) : super(const AuthState()) {
    _restoreSession();
  }

  final AuthRepository _repo;

  Future<void> _restoreSession() async {
    final hasSession = await _repo.hasSession();
    if (!hasSession) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _repo.fetchProfile();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      // Access token likely expired and refresh failed — clear and bounce
      // to the login screen rather than getting stuck.
      await _repo.logout();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Called by the ApiClient when a refresh attempt fails mid-session.
  void forceLogout() {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating, clearError: true);
    try {
      final user = await _repo.login(email: email, password: password);
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (e) {
      final message = e is ApiException ? e.message : 'Login failed. Please try again.';
      state = AuthState(status: AuthStatus.unauthenticated, errorMessage: message);
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String username,
    required String firstName,
    required String lastName,
    required String password,
    required String passwordConfirm,
    required String role,
    String? phoneNumber,
  }) async {
    state = state.copyWith(status: AuthStatus.authenticating, clearError: true);
    try {
      final user = await _repo.register(
        email: email,
        username: username,
        firstName: firstName,
        lastName: lastName,
        password: password,
        passwordConfirm: passwordConfirm,
        role: role,
        phoneNumber: phoneNumber,
      );
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (e) {
      final message =
          e is ApiException ? e.message : 'Registration failed. Please try again.';
      state = AuthState(status: AuthStatus.unauthenticated, errorMessage: message);
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> refreshProfile() async {
    if (!state.isAuthenticated) return;
    try {
      final user = await _repo.fetchProfile();
      state = state.copyWith(user: user);
    } catch (_) {
      // Silently ignore — the UI keeps showing the last known profile.
    }
  }

  void updateLocalUser(AppUser user) {
    state = state.copyWith(user: user);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(ref.watch(authRepositoryProvider));
  // Wire the API client's session-expiry callback back into auth state so
  // an expired refresh token anywhere in the app bounces to login.
  ref.watch(apiClientProvider).onSessionExpired = notifier.forceLogout;
  return notifier;
});
