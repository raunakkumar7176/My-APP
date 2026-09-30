import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/performance_summary.dart';
import '../test/state/test_activity.dart';
import '../test/widgets/test_formatters.dart';
import 'state/performance_controller.dart';

/// Performance & Insights: time-filtered summary (This Week / Monthly / All
/// Time), a weekly consistency chart, subject mastery breakdown, and a
/// Sunday weekly-review banner — every number server-computed by migration
/// 0072's RPCs ([PerformanceController.loadAnalytics]). The legacy
/// study-progress/recent-tests sections (already real data) stay below.
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key, this.controller});

  final PerformanceController? controller;

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  late final PerformanceController _controller;
  late final bool _ownsController;
  int _seenTestActivity = TestActivity.revision.value;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? PerformanceController();
    _controller.addListener(_onChanged);
    _controller.load();
    _controller.loadAnalytics();
    // AppShell keeps this screen mounted via IndexedStack, so it never
    // re-runs initState after a test finishes on another tab — reload when
    // TestActivity signals a fresh submission (see test_activity.dart).
    TestActivity.revision.addListener(_onTestActivity);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onTestActivity() {
    if (TestActivity.revision.value == _seenTestActivity) return;
    _seenTestActivity = TestActivity.revision.value;
    if (mounted) _refresh();
  }

  @override
  void dispose() {
    TestActivity.revision.removeListener(_onTestActivity);
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() => Future.wait([_controller.refresh(), _controller.loadAnalytics()]);

  @override
  Widget build(BuildContext context) {
    // Content-only, matching the app-wide contract for this screen: the
    // caller supplies the Scaffold/AppBar — it's used both as a raw
    // AppShell tab (behind AppShell's own AppBar) and inside the standalone
    // /performance route's own Scaffold. Adding a Scaffold/AppBar here
    // would double up in both places.
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filterTabs(),
            const SizedBox(height: 16),
            if (_controller.shouldOfferWeeklyReport) ...[
              _sundayBanner(),
              const SizedBox(height: 20),
            ],
            if (_controller.analyticsError != null && _controller.summary.totalTestsCompleted == 0)
              _analyticsErrorCard()
            else ...[
              _metricGrid(),
              const SizedBox(height: 20),
              _sectionTitle('Weekly Consistency'),
              const SizedBox(height: 8),
              _weeklyBarChart(),
              const SizedBox(height: 20),
              _sectionTitle('Subject Mastery'),
              const SizedBox(height: 8),
              _subjectMasteryCard(),
            ],
            const SizedBox(height: 24),
            _legacySections(),
          ],
        ),
      ),
    );
  }

  Widget _filterTabs() {
    return Row(
      children: [
        for (final f in TimeFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: Key('perf_filter_${f.rpcValue}'),
              label: Text(f.label),
              selected: _controller.filter == f,
              onSelected: (_) => _controller.setFilter(f),
            ),
          ),
        if (_controller.isAnalyticsLoading) ...[
          const SizedBox(width: 8),
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ],
    );
  }

  Widget _sundayBanner() {
    final theme = Theme.of(context);
    final report = _controller.weeklyReport;
    return Container(
      key: const Key('sunday_weekly_review_banner'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primaryContainer, theme.colorScheme.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration_outlined, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Weekly Study Audit is Ready!', style: TextStyle(fontWeight: FontWeight.bold)),
                if (report != null)
                  Text('${report.accuracyPct.toStringAsFixed(0)}% accuracy this week.')
                else
                  const Text('Generate this week\'s diagnostic report.'),
              ],
            ),
          ),
          FilledButton(
            key: const Key('view_weekly_report_btn'),
            onPressed: () async {
              await _controller.generateWeeklyReport();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Weekly report updated below.')),
                );
              }
            },
            child: const Text('View Detailed Report'),
          ),
        ],
      ),
    );
  }

  Widget _analyticsErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(_controller.analyticsError!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _controller.loadAnalytics, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _metricGrid() {
    final s = _controller.summary;
    final delta = _controller.accuracyDelta;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _metricTile(
          icon: '🎯',
          label: 'Overall Accuracy',
          value: '${s.accuracyPercentage.toStringAsFixed(1)}%',
          delta: delta == null
              ? null
              : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}% vs last week',
        ),
        _metricTile(icon: '📝', label: 'Tests Attempted', value: '${s.totalTestsCompleted} Tests'),
        _metricTile(icon: '⏱️', label: 'Avg Speed / Question', value: '${s.speedAvgSecondsPerQ.toStringAsFixed(0)}s'),
        _metricTile(icon: '📚', label: 'Study Hours', value: '${s.totalStudyHours.toStringAsFixed(1)}h'),
      ],
    );
  }

  Widget _metricTile({required String icon, required String label, required String value, String? delta}) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (delta != null)
              Text(
                delta,
                style: TextStyle(
                  fontSize: 11,
                  color: delta.startsWith('-') ? theme.colorScheme.error : Colors.green,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Widget _weeklyBarChart() {
    final activity = _controller.dailyActivity;
    if (activity.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No activity yet this week.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    final maxQ = activity.map((d) => d.questionsAttempted).fold<int>(1, (a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              maxY: maxQ.toDouble() * 1.2,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= activity.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _weekdayLabels[activity[i].date.weekday - 1],
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < activity.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: activity[i].questionsAttempted.toDouble(),
                        color: Theme.of(context).colorScheme.primary,
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _subjectMasteryCard() {
    final subjects = _controller.subjectBreakdown;
    if (subjects.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Complete a test to see your subject-wise breakdown.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [for (final s in subjects) _subjectRow(s)],
      ),
    );
  }

  Widget _subjectRow(SubjectWiseBreakdown s) {
    final theme = Theme.of(context);
    final (color, label) = switch (s.status) {
      'strong' => (Colors.green, 'Mastered'),
      'weak' => (theme.colorScheme.error, 'Weak Area'),
      _ => (Colors.amber.shade800, 'Review Needed'),
    };
    return InkWell(
      key: Key('subject_row_${s.subjectName}'),
      onTap: () => _openSubjectResults(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(s.subjectName, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${s.accuracyPct.toStringAsFixed(0)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (s.accuracyPct / 100).clamp(0, 1),
                minHeight: 6,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${s.correctCount}/${s.totalQuestions} correct · $label', style: theme.textTheme.bodySmall),
                if (s.isWeak)
                  TextButton(
                    key: Key('add_to_routine_${s.subjectName}'),
                    onPressed: () => context.push('/routine/create'),
                    child: const Text('Add to Routine'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openSubjectResults(SubjectWiseBreakdown s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SubjectResultsSheet(
        controller: _controller,
        subjectName: s.subjectName,
        groupKey: s.groupKey,
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  /// Study-progress snapshot + recent tests — unchanged, already real data
  /// not covered by the new 0072 RPCs.
  Widget _legacySections() {
    if (_controller.isLoading && !_controller.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_controller.latestSnapshot != null) ...[
          _studyProgressCard(),
          const SizedBox(height: 20),
        ],
        _sectionTitle('Recent Tests'),
        const SizedBox(height: 8),
        _recentTestsList(),
      ],
    );
  }

  Widget _studyProgressCard() {
    final snapshot = _controller.latestSnapshot!;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Study Progress', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Latest snapshot · ${snapshot.periodType}',
              style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (snapshot.completionPercentage / 100).clamp(0, 1),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${snapshot.completedTopics}/${snapshot.totalTopics} topics · '
              '${snapshot.studyMinutes} min studied',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentTestsList() {
    if (_controller.recentResults.isEmpty) {
      if (_controller.summary.totalTestsCompleted == 0) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.insights_outlined, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                const Text(
                  'Attempt your first practice drill to unlock diagnostic insights',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => context.push('/tests'), child: const Text('Browse Tests')),
              ],
            ),
          ),
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No recent tests.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final r in _controller.recentResults.take(10))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(r.test.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(TestFormatters.dateTime(r.result.computedAt)),
              trailing: Text(
                r.result.percentage != null ? '${r.result.percentage!.toStringAsFixed(1)}%' : '--',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              onTap: () => context.push('/attempts/${r.result.attemptId}/result'),
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet opened from a Subject Mastery row: the actual test results
/// behind that subject's aggregate number — score, accuracy, and
/// correct/wrong/unanswered breakdown, per attempt, via
/// `rpc_get_subject_results` (migration 0082). Tapping a row opens that
/// attempt's own result screen for full detail.
class _SubjectResultsSheet extends StatefulWidget {
  const _SubjectResultsSheet({
    required this.controller,
    required this.subjectName,
    required this.groupKey,
  });

  final PerformanceController controller;
  final String subjectName;
  final String groupKey;

  @override
  State<_SubjectResultsSheet> createState() => _SubjectResultsSheetState();
}

class _SubjectResultsSheetState extends State<_SubjectResultsSheet> {
  bool _loading = true;
  String? _error;
  List<SubjectResultEntry> _results = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.controller.fetchSubjectResults(widget.groupKey);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load results for ${widget.subjectName}. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.subjectName,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(scrollController)),
          ],
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No results for ${widget.subjectName} in this time range.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _resultCard(_results[index]),
    );
  }

  Widget _resultCard(SubjectResultEntry r) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).pop();
          context.push('/attempts/${r.attemptId}/result');
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      r.testTitle,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${r.percentage.toStringAsFixed(1)}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                TestFormatters.dateTime(r.computedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _statChip('${r.score.toStringAsFixed(1)}/${r.maxScore.toStringAsFixed(0)}', 'Marks'),
                  const SizedBox(width: 8),
                  _statChip('${r.correctCount}', 'Correct', color: Colors.green),
                  const SizedBox(width: 8),
                  _statChip('${r.wrongCount}', 'Wrong', color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  _statChip('${r.unansweredCount}', 'Skipped'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String value, String label, {Color? color}) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
