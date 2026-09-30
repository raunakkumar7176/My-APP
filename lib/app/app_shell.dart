import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/logging/app_logger.dart';
import '../core/models/referral_status.dart';
import '../core/services/academic_alarm_service.dart';
import '../core/services/profile_service.dart';
import '../core/services/push_notification_service.dart';
import '../core/services/single_device_enforcer.dart';
import '../features/notifications/data/notification_feed_repository.dart';
import '../features/routine/data/routine_repository.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dashboard/profile_tab_screen.dart';
import '../features/dashboard/study_tab_screen.dart';
import '../features/dashboard/tests_tab_screen.dart';
import '../features/performance/performance_screen.dart';
import '../l10n/app_localizations.dart';
import 'widgets/app_drawer.dart';

/// The post-login app shell: one AppBar + Drawer, five bottom-nav tabs.
/// Each tab is content-only (no own Scaffold); deep actions push the
/// existing full-screen routes on top, same as before this shell existed.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  int _unreadNotifications = 0;
  StreamSubscription<ReferralApplyResult>? _referralSub;
  StreamSubscription<ProfileStatus>? _profileSub;
  DateTime? _lastBackPressAt;

  static const _titles = ['Dashboard', 'Study', 'Tests', 'Performance & Insights', 'Profile'];

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
    WidgetsBinding.instance.addObserver(this);
    _loadUnreadCount();
    // Cold-start deep link: if the app was launched by tapping a system
    // push notification (not just resumed), route to it now that this
    // shell — and therefore a real router context — exists.
    PushNotificationService.instance.handleColdStartDeepLink();
    // Covers "app cold-started with an already-persisted session" — the
    // AuthService.onAuthStateChange path only fires on a NEW sign-in
    // event, not a session Supabase restored from disk on launch.
    PushNotificationService.instance.registerCurrentDevice();
    // Single-device-login authoritative check: confirms this is still the
    // active device on every cold start too (not just resume, below) —
    // catches a force-logout push this device missed entirely while it
    // was closed.
    SingleDeviceEnforcer.checkStillActive();
    // Academic routine alarms: Android wipes every exact alarm on device
    // reboot (no boot receiver is registered), and this service otherwise
    // only resyncs when a routine is actually created/edited/completed —
    // so without this, a user who just opens the app (never touches a
    // routine) or reboots their phone would have alarms silently stop
    // firing. Every app open re-covers the rolling 14-day window.
    unawaited(_resyncRoutineAlarms());
    _referralSub = ProfileService.referralAppliedStream.listen(_onReferralApplied);
    // Redraws the AppBar XP pill the instant a points award updates
    // ProfileService.currentProfile (e.g. XpCelebrationOverlay.show).
    _profileSub = ProfileService.statusStream.listen((_) {
      if (mounted) setState(() {});
    });
    // Proactively ask for the OS notification permission (Android 13+
    // POST_NOTIFICATIONS) on first Home visit, rather than only when the
    // user happens to open Settings — but only once, ever (hasAskedBefore),
    // reusing the exact same rationale-dialog flow Settings already uses.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRequestNotificationPermission());
  }

  Future<void> _maybeRequestNotificationPermission() async {
    final service = PushNotificationService.instance;
    if (await service.hasAskedBefore()) return;
    if (!mounted) return;
    await service.requestPermissionWithRationale(context);
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
    WidgetsBinding.instance.removeObserver(this);
    _referralSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Single-device-login authoritative check — see initState's call for
      // why this can't rely solely on the force-logout push arriving.
      SingleDeviceEnforcer.checkStillActive();
      // Same reasoning as initState's call: a resume (not just a cold
      // start) is also a good, frequent point to make sure alarms weren't
      // silently dropped by a reboot that happened while backgrounded.
      unawaited(_resyncRoutineAlarms());
    }
  }

  Future<void> _resyncRoutineAlarms() async {
    try {
      final routines = await const SupabaseRoutineRepository().list();
      await AcademicAlarmService.resyncAlarms(routines);
    } catch (e) {
      AppLogger.warning('AppShell: routine alarm resync failed: $e');
    }
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

  /// Hardware/gesture back on the shell: if not on the Home tab, switch to
  /// it first (matches every major app's bottom-nav convention) rather than
  /// exiting; if already on Home, require a second press within 2 seconds
  /// ("Press back again to exit") before actually leaving the app.
  void _onBackInvoked(bool didPop, Object? result) {
    if (didPop) return;
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPressAt != null && now.difference(_lastBackPressAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPressAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('double_back_to_exit_snackbar'),
        content: Text('Press back again to exit'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBackInvoked,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          _XpPill(totalPoints: ProfileService.currentProfile?.totalPoints ?? 0),
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
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: AppLocalizations.of(context)!.navHome),
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: AppLocalizations.of(context)!.navStudy),
          NavigationDestination(icon: const Icon(Icons.quiz_outlined), selectedIcon: const Icon(Icons.quiz), label: AppLocalizations.of(context)!.navTests),
          NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights), label: AppLocalizations.of(context)!.navPerformance),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: AppLocalizations.of(context)!.navProfile),
        ],
      ),
    );
  }
}

/// AppBar entry point into the XP & Study Rewards Hub — tapping opens
/// [XpRewardsHubScreen]'s rulebook/leaderboard/badges tabs. The number shown
/// here always mirrors `ProfileService.currentProfile.totalPoints`; the
/// parent shell rebuilds this on every [ProfileService.statusStream] tick,
/// so an award from anywhere in the app reflects here instantly.
class _XpPill extends StatelessWidget {
  const _XpPill({required this.totalPoints});

  final int totalPoints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        key: const Key('shell_xp_pill'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/xp-rewards'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '⚡ $totalPoints',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
