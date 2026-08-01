import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../courses/course_list_screen.dart';
import '../profile/profile_screen.dart';
import 'admin_dashboard_screen.dart';
import 'student_dashboard_screen.dart';
import 'teacher_dashboard_screen.dart';

/// The authenticated app's root scaffold: a role-aware dashboard tab,
/// a shared courses tab, and a profile tab, all behind one bottom nav.
///
/// Notifications used to be a floating action button here, but it sat in
/// the same bottom-right corner as the teacher dashboard's own "New course"
/// FAB, effectively burying it. Notifications now live as a bell icon in
/// each dashboard's own AppBar (see NotificationBellAction) instead, so
/// there's no shared FAB at this level at all — each dashboard is free to
/// use its own FAB for whatever's relevant to that role.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    if (user == null) {
      // While the app is restoring a saved session (or if that restore
      // fails, e.g. because the backend host is unreachable), this used to
      // return a totally blank Scaffold with no indicator at all — showing
      // a spinner instead makes it obvious the app is doing *something*
      // rather than looking crashed/frozen.
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final dashboard = switch (user.role) {
      'teacher' => const TeacherDashboardScreen(),
      'admin' => const AdminDashboardScreen(),
      _ => const StudentDashboardScreen(),
    };

    final pages = [dashboard, const CourseListScreen(), const ProfileScreen()];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Courses',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
