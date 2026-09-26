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
import 'widgets/continue_studying_card.dart';
import 'widgets/dashboard_quick_actions.dart';
import 'widgets/groups_preview_card.dart';
import 'widgets/today_progress_card.dart';

/// Home / Dashboard screen redesigned as a focused, high-performance
/// command center for competitive exam preparation.
///
/// Features:
/// 1. Dynamic Greeting Header with user profile avatar, live date/time, and target goal
/// 2. Today's Preparation (Target) hero card
/// 3. Continue Studying recent topic/chapter progress
/// 4. Quick Actions responsive launchpad
/// 5. Upcoming Tests & Countdown
/// 6. Today's Schedule & Routine
/// 7. Performance Snapshot & Subject Mastery
/// 8. Recent Tests activity
/// 9. Community Study Groups
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.testRepository,
    this.performanceController,
    this.profile,
  });

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
  late final TestRepository _testRepo =
      widget.testRepository ?? const SupabaseTestRepository();
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
    _performance = (widget.performanceController ?? PerformanceController())
      ..addListener(_onChanged);
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
        // Header falls back to generic student profile below.
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
      final upcoming =
          [
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _upcomingError = 'Could not load your tests.';
        _loadingUpcoming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GreetingHeader(profile: _profile),
                  const SizedBox(height: 14),
                  if (_profile != null && _profile!.examTargets.isNotEmpty) ...[
                    _TargetGoalStrip(target: _profile!.examTargets.first),
                    const SizedBox(height: 14),
                  ],
                  const TodayProgressCard(),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    context,
                    'Continue Studying',
                    action: ('All Topics', () => context.push('/study')),
                  ),
                  const SizedBox(height: 8),
                  ContinueStudyingCard(userId: _profile?.id),
                  const SizedBox(height: 20),
                  _sectionLabel(context, 'Quick Actions'),
                  const SizedBox(height: 8),
                  DashboardQuickActions(draftsCount: _draftsCount),
                  const SizedBox(height: 20),
                  _buildUpcomingHero(),
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
                  if (_performance.hasLoaded &&
                      _performance.subjectPerformance.isNotEmpty) ...[
                    _sectionHeader(
                      context,
                      'Subject Mastery',
                      action: ('Study', () => context.push('/study')),
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
                  _sectionHeader(
                    context,
                    'Study Groups',
                    action: ('Explore Groups', () => context.push('/groups')),
                  ),
                  const SizedBox(height: 8),
                  const GroupsPreviewCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        fontSize: 12,
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
          borderRadius: BorderRadius.circular(6),
          onTap: action.$2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action.$1,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Upcoming / active test ──

  Widget _buildUpcomingHero() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    if (_loadingUpcoming) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_upcomingError != null) {
      return _errorCard(_upcomingError!, _loadUpcoming);
    }
    if (_upcoming.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.025),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_available_outlined,
                size: 24,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No upcoming tests',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Practice scheduled mock papers to test your accuracy and speed under exam conditions.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => context.push('/tests'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              icon: const Icon(Icons.explore_outlined, size: 16),
              label: const Text('Explore Tests'),
            ),
          ],
        ),
      );
    }

    final next = _upcoming.first;
    final rest = _upcoming.skip(1).toList();
    final kind = BackendMapping.fromBackend(next.testMode, next.settings);
    final countdown = _countdown(next.startsAt);
    final isLive =
        next.status == TestStatus.live || next.status == TestStatus.ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, isLive ? 'Live Exam' : 'Upcoming Test'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isLive
                ? theme.colorScheme.primaryContainer
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isLive
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : borderColor,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: isLive
                          ? const Color(0xFFDC2626).withValues(alpha: 0.15)
                          : theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLive) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          isLive ? 'LIVE NOW' : 'UPCOMING TEST',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isLive
                                ? const Color(0xFFDC2626)
                                : theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (countdown != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            countdown,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.8,
                              ),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                next.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16.5,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (next.totalQuestions != null)
                    '${next.totalQuestions} Questions',
                  TestFormatters.duration(next.durationSec),
                  kind.label,
                ].join(' • '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isLive
                            ? const Color(0xFFDC2626)
                            : theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => context.push('/tests/${next.id}'),
                      icon: Icon(
                        isLive
                            ? Icons.play_arrow_rounded
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      label: Text(
                        isLive ? 'Start / Resume Test' : 'View Test',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final t in rest)
          _UpcomingTestRow(
            test: t,
            onTap: () => context.push('/tests/${t.id}'),
          ),
      ],
    );
  }

  // ── Performance snapshot ──

  Widget _buildPerformanceSnapshot() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    if (_performance.isLoading && !_performance.hasLoaded) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_performance.error != null && !_performance.hasLoaded) {
      return _errorCard(_performance.error!, _performance.refresh);
    }
    if (_performance.testsAttempted == 0 &&
        _performance.latestSnapshot == null) {
      return Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.025),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.insights_outlined,
                size: 24,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your performance will appear here after your first test.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => context.push('/tests'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
              ),
              icon: const Icon(Icons.quiz_outlined, size: 16),
              label: const Text(
                'Take a Test',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final snapshot = _performance.latestSnapshot;
    final cards = [
      (
        'Tests Attempted',
        '${_performance.testsAttempted}',
        Icons.assignment_turned_in_outlined,
        const Color(0xFF2563EB),
      ),
      (
        'Average Score',
        '${_performance.averageScorePercent.toStringAsFixed(0)}%',
        Icons.speed_outlined,
        const Color(0xFF059669),
      ),
      (
        'Accuracy Rate',
        '${_performance.averageAccuracy.toStringAsFixed(0)}%',
        Icons.check_circle_outline,
        const Color(0xFF7C3AED),
      ),
      if (snapshot != null)
        (
          'Study Time',
          '${(snapshot.studyMinutes / 60).toStringAsFixed(0)}h',
          Icons.hourglass_bottom_outlined,
          const Color(0xFFD97706),
        ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.6,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) {
        final (label, value, icon, color) = cards[i];
        return _statCard(label, value, icon, color);
      },
    );
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    Color accentColor,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w500,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }

  // ── Subject mastery ──

  Widget _buildSubjectMastery() {
    final subjects = _performance.subjectPerformance
        .where((s) => s.attempted > 0)
        .take(4)
        .toList();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          for (var i = 0; i < subjects.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _subjectRow(subjects[i]),
          ],
        ],
      ),
    );
  }

  Widget _subjectRow(SubjectBreakdownItem item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${item.accuracy.toStringAsFixed(0)}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (item.accuracy / 100).clamp(0, 1),
            minHeight: 6,
            backgroundColor: isDark
                ? const Color(0xFF334155)
                : const Color(0xFFEEF2F6),
            color: color,
          ),
        ),
      ],
    );
  }

  static (String, Color) _masteryTier(double accuracy, ThemeData theme) {
    if (accuracy >= 80) return ('Mastered', const Color(0xFF059669));
    if (accuracy >= 60) return ('Strong', const Color(0xFF2563EB));
    return ('Needs Review', const Color(0xFFD97706));
  }

  // ── Recent tests ──

  Widget _buildRecentTests() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    if (_performance.isLoading && !_performance.hasLoaded) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
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
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () =>
                    context.push('/attempts/${r.result.attemptId}/result'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.test.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                TestFormatters.dateTime(r.result.computedAt),
                                if (r.result.rank != null)
                                  'Rank ${r.result.rank}',
                              ].join(' • '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (r.result.correctCount != null &&
                              r.result.totalQuestions != null)
                            Text(
                              '${r.result.correctCount}/${r.result.totalQuestions}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          if (r.result.percentage != null) ...[
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${r.result.percentage!.toStringAsFixed(0)}%',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
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
          ),
      ],
    );
  }

  // ── shared small states ──

  Widget _errorCard(String message, VoidCallback onRetry) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _emptyCard(IconData icon, String title, String subtitle) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Column(
          children: [
            Icon(
              icon,
              size: 34,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 12.5,
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
    final initial = (name.isNotEmpty ? name[0] : 'S').toUpperCase();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Academic command center branding label
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(
                    alpha: isDark ? 0.2 : 0.1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'MY PREPARATION • COMMAND CENTER',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    fontSize: 9.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                key: const Key('dashboard_greeting'),
                '$greeting, $name 👋',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                key: const Key('dashboard_date_time'),
                '${Greeting.weekdayName(wall.weekday)}, ${wall.day} ${Greeting.monthName(wall.month)} ${wall.year} · '
                '${Greeting.time12h(wall.hour, wall.minute)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (profile?.studentCode != null)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        profile!.studentCode!,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF475569),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B)
                          .withValues(alpha: isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.stars_rounded,
                          color: Color(0xFFF59E0B),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${profile?.totalPoints ?? 0} pts',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // User Profile Avatar with profile navigation
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => context.push('/profile'),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
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
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB)
                  .withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.track_changes_rounded,
              size: 16,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Target Goal',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        test.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        TestFormatters.dateTime(test.startsAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
