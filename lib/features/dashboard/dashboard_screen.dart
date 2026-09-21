import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_error.dart';
import '../../core/models/profile.dart';
import '../../core/models/result_analytics.dart';
import '../../core/models/test.dart';
import '../../core/services/profile_service.dart';
import '../calendar/domain/calendar_clock.dart';
import '../performance/state/performance_controller.dart';
import '../routine/widgets/today_routine_card.dart';
import '../test/data/test_repository.dart';
import '../test/domain/backend_mapping.dart';
import '../test/domain/test_lifecycle.dart';
import '../test/widgets/test_formatters.dart';
import 'domain/greeting.dart';
import 'widgets/dashboard_quick_actions.dart';
import 'widgets/groups_preview_card.dart';
import 'widgets/today_progress_card.dart';

/// Home tab content (no own Scaffold — [AppShell] supplies the AppBar).
/// Visual structure follows the uploaded dashboard reference; every figure
/// comes from an existing repository/controller — nothing is fabricated,
/// and every section has its own loading/empty/error state so one failing
/// section never blanks the rest of the dashboard.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.testRepository, this.performanceController, this.profile});

  /// Injectable for tests; defaults to the Supabase-backed repository.
  final TestRepository? testRepository;

  /// Injectable for tests; defaults to a fresh [PerformanceController].
  final PerformanceController? performanceController;

  /// Overrides [ProfileService.currentProfile] for tests.
  final Profile? profile;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final TestRepository _testRepo = widget.testRepository ?? const SupabaseTestRepository();
  late final PerformanceController _performance;

  Timer? _clockTimer;
  Profile? _profile;

  List<Test> _upcoming = [];
  bool _loadingUpcoming = true;
  String? _upcomingError;
  int _draftsCount = 0;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile ?? ProfileService.currentProfile;
    _performance = (widget.performanceController ?? PerformanceController())..addListener(_onChanged);
    // Re-render every minute so the clock/greeting stay live without a timer per widget.
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _performance.removeListener(_onChanged);
    _performance.dispose();
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
    await Future.wait([_loadUpcoming(), _performance.load()]);
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GreetingHeader(profile: _profile),
            const SizedBox(height: 12),
            if (_profile != null && _profile!.examTargets.isNotEmpty) ...[
              _TargetGoalStrip(target: _profile!.examTargets.first),
              const SizedBox(height: 12),
            ],
            const TodayProgressCard(),
            const SizedBox(height: 20),
            _buildUpcomingHero(),
            const SizedBox(height: 20),
            _sectionLabel(context, 'Quick Actions'),
            const SizedBox(height: 8),
            DashboardQuickActions(draftsCount: _draftsCount),
            const SizedBox(height: 20),
            _sectionHeader(
              context,
              "Today's Schedule",
              action: ('View Routine', () => context.push('/routine')),
            ),
            const SizedBox(height: 8),
            const TodayRoutineCard(),
            const SizedBox(height: 20),
            _sectionHeader(
              context,
              'Performance Snapshot',
              action: ('Analytics', () => context.push('/performance')),
            ),
            const SizedBox(height: 8),
            _buildPerformanceSnapshot(),
            const SizedBox(height: 20),
            if (_performance.hasLoaded && _performance.subjectPerformance.isNotEmpty) ...[
              _sectionHeader(
                context,
                'Subject Mastery',
                action: ('Syllabus', () => context.push('/subjects')),
              ),
              const SizedBox(height: 8),
              _buildSubjectMastery(),
              const SizedBox(height: 20),
            ],
            _sectionHeader(
              context,
              'Recent Tests',
              action: ('All Papers', () => context.push('/tests?tab=2')),
            ),
            const SizedBox(height: 8),
            _buildRecentTests(),
            const SizedBox(height: 20),
            const GroupsPreviewCard(),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title.toUpperCase(),
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    required (String, VoidCallback) action,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _sectionLabel(context, title),
        InkWell(
          onTap: action.$2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action.$1,
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
              ),
              Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ],
    );
  }

  // ── Upcoming / active test ──

  Widget _buildUpcomingHero() {
    if (_loadingUpcoming) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_upcomingError != null) {
      return _errorCard(_upcomingError!, _loadUpcoming);
    }
    if (_upcoming.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 36,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 8),
              Text('No upcoming tests', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push('/tests'),
                child: const Text('Explore Tests'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final next = _upcoming.first;
    final rest = _upcoming.skip(1).toList();
    final kind = BackendMapping.fromBackend(next.testMode, next.settings);
    final countdown = _countdown(next.startsAt);
    final isLive = next.status == TestStatus.live || next.status == TestStatus.ready;

    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isLive ? 'LIVE NOW' : 'UPCOMING TEST',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (countdown != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule, size: 15, color: theme.colorScheme.onPrimaryContainer),
                        const SizedBox(width: 4),
                        Text(
                          countdown,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                next.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (next.totalQuestions != null) '${next.totalQuestions} Questions',
                  TestFormatters.duration(next.durationSec),
                  kind.label,
                ].join(' • '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.surface,
                        foregroundColor: theme.colorScheme.primary,
                      ),
                      onPressed: () => context.push('/tests/${next.id}'),
                      icon: Icon(isLive ? Icons.play_arrow : Icons.visibility_outlined, size: 18),
                      label: Text(isLive ? 'Start / Resume Test' : 'View Test'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final t in rest) _UpcomingTestRow(test: t, onTap: () => context.push('/tests/${t.id}')),
      ],
    );
  }

  // ── Performance snapshot ──

  Widget _buildPerformanceSnapshot() {
    if (_performance.isLoading && !_performance.hasLoaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_performance.error != null && !_performance.hasLoaded) {
      return _errorCard(_performance.error!, _performance.refresh);
    }
    if (_performance.testsAttempted == 0 && _performance.latestSnapshot == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                'Your performance will appear here after your first test.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/tests'),
                child: const Text('Take a Test'),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = _performance.latestSnapshot;
    final cards = [
      ('Tests Attempted', '${_performance.testsAttempted}', Icons.assignment_turned_in_outlined),
      ('Average Score', '${_performance.averageScorePercent.toStringAsFixed(0)}%', Icons.speed_outlined),
      ('Accuracy Rate', '${_performance.averageAccuracy.toStringAsFixed(0)}%', Icons.check_circle_outline),
      if (snapshot != null)
        ('Study Time', '${(snapshot.studyMinutes / 60).toStringAsFixed(0)}h', Icons.hourglass_bottom_outlined),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.7,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) {
        final (label, value, icon) = cards[i];
        return _statCard(label, value, icon);
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // ── Subject mastery ──

  Widget _buildSubjectMastery() {
    final subjects = _performance.subjectPerformance.where((s) => s.attempted > 0).take(4).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < subjects.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _subjectRow(subjects[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subjectRow(SubjectBreakdownItem item) {
    final theme = Theme.of(context);
    final (label, color) = _masteryTier(item.accuracy, theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                item.subjectName,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Text(
              '${item.accuracy.toStringAsFixed(0)}%',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (item.accuracy / 100).clamp(0, 1),
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }

  static (String, Color) _masteryTier(double accuracy, ThemeData theme) {
    if (accuracy >= 80) return ('Mastered', theme.colorScheme.tertiary);
    if (accuracy >= 60) return ('Strong', theme.colorScheme.primary);
    return ('Needs Review', theme.colorScheme.secondary);
  }

  // ── Recent tests ──

  Widget _buildRecentTests() {
    if (_performance.isLoading && !_performance.hasLoaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_performance.error != null && !_performance.hasLoaded) {
      return _errorCard(_performance.error!, _performance.refresh);
    }
    final recent = _performance.recentResults.take(3).toList();
    if (recent.isEmpty) {
      return _emptyCard(
        Icons.insights_outlined,
        'No recent tests',
        'Your completed tests will appear here.',
      );
    }
    return Column(
      children: [
        for (final r in recent)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push('/attempts/${r.result.attemptId}/result'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.test.title,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              TestFormatters.dateTime(r.result.computedAt),
                              if (r.result.rank != null) 'Rank ${r.result.rank}',
                            ].join(' • '),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (r.result.correctCount != null && r.result.totalQuestions != null)
                          Text(
                            '${r.result.correctCount}/${r.result.totalQuestions}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        if (r.result.percentage != null) ...[
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${r.result.percentage!.toStringAsFixed(0)}%',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── shared small states ──

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

  static String? _countdown(DateTime? startsAt) {
    if (startsAt == null) return null;
    final diff = startsAt.difference(DateTime.now());
    if (diff.isNegative) return null;
    if (diff.inDays > 0) return 'In ${diff.inDays}d';
    if (diff.inHours > 0) return 'In ${diff.inHours}h ${diff.inMinutes % 60}m';
    if (diff.inMinutes > 0) return 'In ${diff.inMinutes}m';
    return 'Starting now';
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final clock = CalendarClock(profile?.timezone);
    final wall = clock.toUserWall(DateTime.now());
    final greeting = Greeting.forHour(wall.hour);
    final name = profile?.displayName ?? 'Student';
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: const Key('dashboard_greeting'),
          '$greeting, $name 👋',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          key: const Key('dashboard_date_time'),
          '${Greeting.weekdayName(wall.weekday)}, ${wall.day} ${Greeting.monthName(wall.month)} ${wall.year} · '
          '${Greeting.time12h(wall.hour, wall.minute)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _TargetGoalStrip extends StatelessWidget {
  const _TargetGoalStrip({required this.target});

  final String target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'Target Goal',
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingTestRow extends StatelessWidget {
  const _UpcomingTestRow({required this.test, required this.onTap});

  final Test test;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        title: Text(test.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(TestFormatters.dateTime(test.startsAt)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
