import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/global_keys.dart';
import '../../features/assessments/certificates_screen.dart';
import '../../features/assessments/quiz_attempt_screen.dart';
import '../../features/assessments/quiz_list_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/chat/chat_room_screen.dart';
import '../../features/chat/chat_rooms_screen.dart';
import '../../features/courses/course_detail_screen.dart';
import '../../features/courses/course_list_screen.dart';
import '../../features/courses/create_course_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/pending_teachers_screen.dart';
import '../../features/home/pending_topups_screen.dart';
import '../../features/home/pending_withdrawals_screen.dart';
import '../../features/home/teachers_list_screen.dart';
import '../../features/live_classes/create_live_class_screen.dart';
import '../../features/live_classes/live_class_detail_screen.dart';
import '../../features/live_classes/live_class_list_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/payments/wallet_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/resources/resource_list_screen.dart';
import '../../features/resources/upload_resource_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../models/assessment_models.dart';
import '../../providers/auth_provider.dart';

/// Bridges Riverpod state changes into a [Listenable] that go_router can
/// use as its `refreshListenable`, so navigation reacts immediately to
/// login/logout without needing a full widget rebuild.
class _AuthRouterRefresh extends ChangeNotifier {
  _AuthRouterRefresh(Ref ref) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.status != next.status) notifyListeners();
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRouterRefresh(ref);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final loc = state.matchedLocation;
      final isSplash = loc == '/splash';
      final isAuthRoute = loc == '/login' || loc == '/register' || loc == '/forgot-password';

      if (authState.status == AuthStatus.unknown) {
        return isSplash ? null : '/splash';
      }
      if (authState.status == AuthStatus.unauthenticated) {
        return isAuthRoute ? null : '/login';
      }
      // Authenticated.
      if (isSplash || isAuthRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeShell()),

      // NOTE: static-segment routes (e.g. /courses/create) must be
      // registered before the dynamic /courses/:id route below, since
      // go_router evaluates top-level routes in declaration order and
      // would otherwise treat "create" as an :id.
      GoRoute(
        path: '/courses',
        builder: (context, state) => const CourseListScreen(),
      ),
      GoRoute(
        path: '/courses/create',
        builder: (context, state) => const CreateCourseScreen(),
      ),
      GoRoute(
        path: '/courses/:id',
        builder: (context, state) =>
            CourseDetailScreen(courseId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/live-classes',
        builder: (context, state) => const LiveClassListScreen(),
      ),
      GoRoute(
        path: '/live-classes/create',
        builder: (context, state) => const CreateLiveClassScreen(),
      ),
      GoRoute(
        path: '/live-classes/:id',
        builder: (context, state) => LiveClassDetailScreen(
          liveClassId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/chat/rooms',
        builder: (context, state) => const ChatRoomsScreen(),
      ),
      GoRoute(
        path: '/chat/rooms/:id',
        builder: (context, state) => ChatRoomScreen(
          roomId: state.pathParameters['id']!,
          roomName: (state.extra as String?) ?? 'Chat',
        ),
      ),
      GoRoute(
        path: '/quizzes',
        builder: (context, state) => const QuizListScreen(),
      ),
      GoRoute(
        path: '/quizzes/attempt',
        builder: (context, state) => QuizAttemptScreen(quiz: state.extra as Quiz),
      ),
      GoRoute(
        path: '/certificates',
        builder: (context, state) => const CertificatesScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: '/resources',
        builder: (context, state) => const ResourceListScreen(),
      ),
      GoRoute(
        path: '/resources/upload',
        builder: (context, state) => const UploadResourceScreen(),
      ),
      GoRoute(
        path: '/teachers',
        builder: (context, state) => const TeachersListScreen(),
      ),
      GoRoute(
        path: '/admin/pending-teachers',
        builder: (context, state) => const PendingTeachersScreen(),
      ),
      GoRoute(
        path: '/admin/pending-topups',
        builder: (context, state) => const PendingTopUpsScreen(),
      ),
      GoRoute(
        path: '/admin/pending-withdrawals',
        builder: (context, state) => const PendingWithdrawalsScreen(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
    ],
  );
});
