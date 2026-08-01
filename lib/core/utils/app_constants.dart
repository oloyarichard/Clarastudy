/// Central place for constants used across the app.
class AppConstants {
  AppConstants._();

  static const String appName = 'Clarastudy';
  static const String appVersion = '1.0.0';

  // Secure storage keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';

  // Pagination
  static const int pageSize = 20;

  // Network timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}

/// User role constants matching the Django backend's ROLE_CHOICES.
class UserRole {
  UserRole._();

  static const String student = 'student';
  static const String teacher = 'teacher';
  static const String admin = 'admin';
}

/// The only prices a course can be created at. Teachers pick one of these
/// rather than typing an arbitrary number — keeps pricing predictable for
/// the payment/wallet-split flow and avoids odd values mobile money can't
/// cleanly represent.
class CoursePriceTiers {
  CoursePriceTiers._();

  static const List<double> values = [0, 4.99, 9.99, 19.99, 29.99, 49.99, 99.99];
}
