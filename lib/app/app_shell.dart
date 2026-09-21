import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/logging/app_logger.dart';
import '../features/group/data/group_repository.dart';
import '../features/group/data/notification_repository.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/profile_tab_screen.dart';
import '../features/dashboard/study_tab_screen.dart';
import '../features/dashboard/tests_tab_screen.dart';
import '../features/performance/performance_screen.dart';
import 'widgets/app_drawer.dart';

/// The post-login app shell: one AppBar + Drawer, five bottom-nav tabs.
/// Each tab is content-only (no own Scaffold); deep actions push the
/// existing full-screen routes on top, same as before this shell existed.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _unreadNotifications = 0;

  static const _titles = ['Dashboard', 'Study', 'Tests', 'Performance', 'Profile'];

  final _tabs = const [
    DashboardScreen(),
    StudyTabScreen(),
    TestsTabScreen(),
    PerformanceScreen(),
    ProfileTabScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  /// Notifications are group-scoped only (see NotificationRepository); there
  /// is no single aggregate query, so this sums the caller's own groups —
  /// a small, bounded list, not an unlimited fetch.
  Future<void> _loadUnreadCount() async {
    try {
      const GroupRepository groups = SupabaseGroupRepository();
      const NotificationRepository notifications = SupabaseNotificationRepository();
      final myGroups = await groups.myGroups();
      var total = 0;
      for (final g in myGroups) {
        total += await notifications.unreadCount(g.id);
      }
      if (mounted) setState(() => _unreadNotifications = total);
    } catch (e, st) {
      AppLogger.error('AppShell unread count failed: $e', stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            key: const Key('shell_notifications_button'),
            tooltip: 'Notifications',
            onPressed: () async {
              await context.push('/notifications');
              if (mounted) _loadUnreadCount();
            },
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text('$_unreadNotifications'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _index, children: _tabs),
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('app_bottom_nav'),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Study'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Tests'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Performance'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
