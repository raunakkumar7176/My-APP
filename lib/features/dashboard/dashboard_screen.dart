import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_error.dart';
import '../../core/models/profile.dart';
import '../../core/models/result.dart';
import '../../core/models/test.dart';
import '../../core/services/profile_service.dart';
import '../calendar/domain/calendar_clock.dart';
import '../routine/widgets/today_routine_card.dart';
import '../test/data/result_repository.dart';
import '../test/data/test_repository.dart';
import '../test/domain/backend_mapping.dart';
import '../test/domain/test_lifecycle.dart';
import '../test/widgets/test_formatters.dart';
import 'widgets/dashboard_quick_actions.dart';

/// Home tab content (no own Scaffold — [AppShell] supplies the AppBar).
/// Every section owns its own load/error/empty state; nothing is fetched
/// through new business logic, only existing repositories.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TestRepository _testRepo = const SupabaseTestRepository();
  final ResultRepository _resultRepo = const SupabaseResultRepository();

  Timer? _clockTimer;
  Profile? _profile;

  List<Test> _upcoming = [];
  bool _loadingUpcoming = true;
  String? _upcomingError;

  Test? _lastCompletedTest;
  Result? _lastResult;
  bool _loadingRecent = true;
  String? _recentError;

  int _draftsCount = 0;

  @override
  void initState() {
    super.initState();
    _profile = ProfileService.currentProfile;
    // Re-render every minute so the clock/greeting stay live without a timer per widget.
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (_profile == null) {
      try {
        await ProfileService.loadProfile();
      } catch (_) {
        // Header falls back to a generic greeting below.
      }
      if (mounted) setState(() => _profile = ProfileService.currentProfile);
    }
    await Future.wait([_loadUpcoming(), _loadRecent()]);
  }

  Future<void> _loadUpcoming() async {
    setState(() {
      _loadingUpcoming = true;
      _upcomingError = null;
    });
    try {
      final accessible = await _testRepo.listAccessible();
      final drafts = await _testRepo.listMyDrafts();
      final now = DateTime.now();
      final upcoming = [
        for (final t in accessible)
          if (TestLifecycle.categorize(
                status: t.status,
                testMode: t.testMode,
                startsAt: t.startsAt,
                endsAt: t.endsAt,
                isSoftDeleted: t.isSoftDeleted,
                now: now,
              ) ==
              ListingCategory.upcoming)
            t,
      ]..sort((a, b) {
          final aAt = a.startsAt ?? DateTime(9999);
          final bAt = b.startsAt ?? DateTime(9999);
          return aAt.compareTo(bAt);
        });
      if (!mounted) return;
      setState(() {
        _upcoming = upcoming.take(3).toList();
        _draftsCount = drafts.length;
        _loadingUpcoming = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _upcomingError = e.message;
        _loadingUpcoming = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _upcomingError = 'Could not load your tests.';
        _loadingUpcoming = false;
      });
    }
  }

  Future<void> _loadRecent() async {
    setState(() {
      _loadingRecent = true;
      _recentError = null;
    });
    try {
      final accessible = await _testRepo.listAccessible();
      final now = DateTime.now();
      final previous = [
        for (final t in accessible)
          if (TestLifecycle.categorize(
                status: t.status,
                testMode: t.testMode,
                startsAt: t.startsAt,
                endsAt: t.endsAt,
                isSoftDeleted: t.isSoftDeleted,
                now: now,
              ) ==
              ListingCategory.previous)
            t,
      ]..sort((a, b) {
          final aAt = a.endsAt ?? a.startsAt ?? DateTime(0);
          final bAt = b.endsAt ?? b.startsAt ?? DateTime(0);
          return bAt.compareTo(aAt);
        });

      Result? latest;
      Test? latestTest;
      for (final t in previous.take(5)) {
        final results = await _resultRepo.mineForTest(t.id);
        if (results.isNotEmpty) {
          latest = results.first;
          latestTest = t;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _lastResult = latest;
        _lastCompletedTest = latestTest;
        _loadingRecent = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _recentError = e.message;
        _loadingRecent = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recentError = 'Could not load recent results.';
        _loadingRecent = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GreetingHeader(profile: _profile),
            const SizedBox(height: 20),
            const TodayRoutineCard(),
            const SizedBox(height: 20),
            _sectionTitle(context, 'Quick Actions'),
            const SizedBox(height: 8),
            DashboardQuickActions(draftsCount: _draftsCount),
            const SizedBox(height: 20),
            _sectionTitle(context, 'Upcoming Test', action: (
              'View All',
              () => context.push('/tests'),
            )),
            const SizedBox(height: 8),
            _buildUpcoming(),
            const SizedBox(height: 20),
            _sectionTitle(context, 'Recent Performance', action: (
              'View All',
              () => context.push('/performance'),
            )),
            const SizedBox(height: 8),
            _buildRecent(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String title, {
    (String, VoidCallback)? action,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (action != null)
          TextButton(onPressed: action.$2, child: Text(action.$1)),
      ],
    );
  }

  Widget _buildUpcoming() {
    if (_loadingUpcoming) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_upcomingError != null) {
      return _errorCard(_upcomingError!, _loadUpcoming);
    }
    if (_upcoming.isEmpty) {
      return _emptyCard(
        Icons.event_available_outlined,
        'No upcoming tests',
        'Scheduled and challenge tests will appear here.',
      );
    }
    return Column(
      children: [
        for (final test in _upcoming)
          _UpcomingTestCard(
            test: test,
            onTap: () => context.push('/tests/${test.id}'),
          ),
      ],
    );
  }

  Widget _buildRecent() {
    if (_loadingRecent) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_recentError != null) {
      return _errorCard(_recentError!, _loadRecent);
    }
    if (_lastResult == null || _lastCompletedTest == null) {
      return _emptyCard(
        Icons.insights_outlined,
        'No results yet',
        'Your most recent test result will appear here once you complete a test.',
      );
    }
    final result = _lastResult!;
    final test = _lastCompletedTest!;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/attempts/${result.attemptId}/result'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      test.title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.percentage != null
                          ? '${result.percentage!.toStringAsFixed(1)}% score'
                          : 'Score pending',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard(String message, VoidCallback onRetry) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(IconData icon, String title, String subtitle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final clock = CalendarClock(profile?.timezone);
    final wall = clock.toUserWall(DateTime.now());
    final greeting = _greetingFor(wall.hour);
    final name = profile?.displayName ?? 'Student';
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting, $name 👋',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${_weekdayName(wall.weekday)}, ${_monthName(wall.month)} ${wall.day} · '
          '${_time12h(wall.hour, wall.minute)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  static String _greetingFor(int hour) {
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  static String _time12h(int hour, int minute) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour < 12 ? 'AM' : 'PM';
    return '$h:${minute.toString().padLeft(2, '0')} $period';
  }

  static String _weekdayName(int weekday) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][weekday - 1];

  static String _monthName(int month) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][month - 1];
}

class _UpcomingTestCard extends StatelessWidget {
  const _UpcomingTestCard({required this.test, required this.onTap});

  final Test test;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = BackendMapping.fromBackend(test.testMode, test.settings);
    final countdown = _countdown(test.startsAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      test.title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (countdown != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        countdown,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _chip(context, Icons.category_outlined, kind.label),
                  _chip(context, Icons.timer_outlined, TestFormatters.duration(test.durationSec)),
                  if (test.startsAt != null)
                    _chip(context, Icons.schedule, TestFormatters.dateTime(test.startsAt)),
                  if (test.totalQuestions != null)
                    _chip(context, Icons.list_alt, '${test.totalQuestions} questions'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  static String? _countdown(DateTime? startsAt) {
    if (startsAt == null) return null;
    final diff = startsAt.difference(DateTime.now());
    if (diff.isNegative) return null;
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'in ${diff.inMinutes}m';
    return 'starting now';
  }
}
