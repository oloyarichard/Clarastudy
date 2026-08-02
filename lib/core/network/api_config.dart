/// Base URL configuration for the Django backend.
///
/// The Django dev server runs on http://127.0.0.1:8000 by default.
/// Depending on where you run the Flutter app, "localhost" means
/// different things, so pick the right one below:
///
///  - Android emulator  -> http://10.0.2.2:8000
///  - iOS simulator     -> http://127.0.0.1:8000
///  - Physical device    -> http://<your-computer-LAN-IP>:8000
///  - Chrome/web         -> http://127.0.0.1:8000
///
/// Simplest option while developing: set this to your machine's LAN IP
/// so it works from emulators, simulators and physical devices alike.
class ApiConfig {
  ApiConfig._();

  /// Change this single value to point the app at your backend.
  static const String host = 'https://77.42.41.162/';

  static const String apiBase = '$host/api';
  static const String mediaBase = host;

  // Auth
  static const String login = '/auth/login/';
  static const String refresh = '/auth/refresh/';

  // Users
  static const String register = '/users/register/';
  static const String profile = '/users/profile/';
  static const String teachers = '/users/teachers/';
  static const String pendingTeachers = '/users/teachers/pending/';
  static String teacherApprove(String id) => '/users/teachers/$id/approve/';

  // Courses
  static const String courses = '/courses/';
  static const String courseCreate = '/courses/create/';
  static String courseDetail(String id) => '/courses/$id/';
  static const String moduleCreate = '/courses/modules/create/';
  static const String lessonCreate = '/courses/lessons/create/';

  // Enrollments
  static const String myEnrollments = '/enrollments/my/';
  static const String enrollmentCreate = '/enrollments/create/';
  static const String enrollAndPay = '/enrollments/enroll-and-pay/';
  static const String progressUpdate = '/enrollments/progress/';

  // Live classes
  static const String liveClasses = '/live-classes/';
  static const String liveClassCreate = '/live-classes/create/';
  static String liveClassChat(String liveClassId) =>
      '/live-classes/$liveClassId/chat/';
  static String liveClassDailyToken(String liveClassId) =>
      '/live-classes/$liveClassId/daily-token/';
  static String liveClassStart(String liveClassId) =>
      '/live-classes/$liveClassId/start/';
  static String liveClassDelete(String liveClassId) =>
      '/live-classes/$liveClassId/delete/';
  static String raisedHands(String liveClassId) =>
      '/live-classes/$liveClassId/raised-hands/';
  static String raisedHandToggle(String liveClassId) =>
      '/live-classes/$liveClassId/raised-hands/toggle/';

  // Chat
  static const String chatRooms = '/chat/rooms/';
  static String chatMessages(String roomId) => '/chat/rooms/$roomId/messages/';

  // Notifications
  static const String notifications = '/notifications/';
  static String notificationRead(String id) => '/notifications/$id/read/';

  // Assessments
  static const String quizzes = '/assessments/';
  static const String quizAttempt = '/assessments/attempt/';
  static const String certificates = '/assessments/certificates/';

  // Resources
  static const String resources = '/resources/';
  static const String resourceUpload = '/resources/upload/';
  static const String myDownloads = '/resources/downloads/';

  // Payments
  static const String payments = '/payments/';
  static const String paymentCreate = '/payments/create/';
  static const String wallet = '/payments/wallet/';
  static const String walletTopUp = '/payments/topup/';
  static const String pendingTopUps = '/payments/topup/pending/';
  static String reviewTopUp(String id) => '/payments/topup/$id/review/';
  static const String withdrawalRequest = '/payments/withdraw/';
  static const String pendingWithdrawals = '/payments/withdraw/pending/';
  static String reviewWithdrawal(String id) => '/payments/withdraw/$id/review/';

  // Analytics
  static const String dashboard = '/analytics/dashboard/';

  /// Resolves a possibly-relative media URL (e.g. "/media/courses/x.png")
  /// returned by Django into an absolute URL the app can load.
  static String resolveMediaUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$mediaBase$url';
  }
}
