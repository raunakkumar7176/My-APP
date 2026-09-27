import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/logging/app_logger.dart';
import '../core/models/referral_status.dart';
import '../core/services/profile_service.dart';
import '../core/services/push_notification_service.dart';
import '../features/notifications/data/notification_feed_repository.dart';
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
  StreamSubscription<ReferralApplyResult>? _referralSub;

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
    // Cold-start deep link: if the app was launched by tapping a system
    // push notification (not just resumed), route to it now that this
    // shell — and therefore a real router context — exists.
    PushNotificationService.instance.handleColdStartDeepLink();
    // Covers "app cold-started with an already-persisted session" — the
    // AuthService.onAuthStateChange path only fires on a NEW sign-in
    // event, not a session Supabase restored from disk on launch.
    PushNotificationService.instance.registerCurrentDevice();
    _referralSub = ProfileService.referralAppliedStream.listen(_onReferralApplied);
  }

  void _onReferralApplied(ReferralApplyResult result) {
    if (!mounted || !result.success) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Welcome! 🎁'),
        content: Text(
          '${result.pointsAwarded ?? 100} Study Points added to your profile, '
          'courtesy of ${result.referrerName ?? 'a fellow student'}!',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Nice!'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _referralSub?.cancel();
    super.dispose();
  }

  /// Uses the global notification feed repository for a single server-side
  /// count query — no per-group aggregation needed.
  Future<void> _loadUnreadCount() async {
    try {
      const feedRepo = SupabaseNotificationFeedRepository();
      final count = await feedRepo.totalUnreadCount();
      if (mounted) setState(() => _unreadNotifications = count);
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
