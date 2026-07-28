import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/notification_providers.dart';
import '../courses/course_list_screen.dart';
import '../profile/profile_screen.dart';
import 'admin_dashboard_screen.dart';
import 'student_dashboard_screen.dart';
import 'teacher_dashboard_screen.dart';

/// The authenticated app's root scaffold: a role-aware dashboard tab,
/// a shared courses tab, and a profile tab, all behind one bottom nav.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final dashboard = switch (user.role) {
      'teacher' => const TeacherDashboardScreen(),
      'admin' => const AdminDashboardScreen(),
      _ => const StudentDashboardScreen(),
    };

    final pages = [dashboard, const CourseListScreen(), const ProfileScreen()];
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final unread = unreadAsync.asData?.value ?? 0;

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Courses',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: _index == 0
          ? Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: FloatingActionButton(
                heroTag: 'notifications-fab',
                onPressed: () => context.push('/notifications'),
                child: const Icon(Icons.notifications_outlined),
              ),
            )
          : null,
    );
  }
}
