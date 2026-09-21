import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/result_analytics.dart';
import '../test/widgets/test_formatters.dart';
import 'state/performance_controller.dart';

/// Performance overview: aggregate stats, subject performance / weak areas,
/// study progress and recent tests, built entirely from existing stored
/// data ([PerformanceController]). No client-side ranking, nothing invented.
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key, this.controller});

  final PerformanceController? controller;

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  late final PerformanceController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? PerformanceController();
    _controller.addListener(_onChanged);
    _controller.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isLoading && !_controller.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.error != null && !_controller.hasLoaded) {
      return _errorState();
    }

    final hasAnyData = _controller.testsAttempted > 0 || _controller.latestSnapshot != null;

    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hasAnyData)
              _emptyState()
            else ...[
              _overviewRow(),
              const SizedBox(height: 20),
              if (_controller.latestSnapshot != null) ...[
                _studyProgressCard(),
                const SizedBox(height: 20),
              ],
              if (_controller.weakAreas.isNotEmpty) ...[
                _sectionTitle('Weak Areas'),
                const SizedBox(height: 8),
                _weakAreasCard(),
                const SizedBox(height: 20),
              ],
              if (_controller.subjectPerformance.isNotEmpty) ...[
                _sectionTitle('Subject Performance'),
                const SizedBox(height: 8),
                _subjectPerformanceCard(),
                const SizedBox(height: 20),
              ],
              _sectionTitle('Recent Tests'),
              const SizedBox(height: 8),
              _recentTestsList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(_controller.error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _controller.refresh, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.insights_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text('No performance data yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Complete a test to see your performance overview here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.push('/tests'),
              child: const Text('Browse Tests'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _overviewRow() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            'Tests Attempted',
            '${_controller.testsAttempted}',
            Icons.quiz_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            'Avg Score',
            '${_controller.averageScorePercent.toStringAsFixed(1)}%',
            Icons.grade_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            'Avg Accuracy',
            '${_controller.averageAccuracy.toStringAsFixed(1)}%',
            Icons.gps_fixed,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
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

  Widget _weakAreasCard() {
    return Card(
      child: Column(
        children: [
          for (final area in _controller.weakAreas) _subjectTile(area, highlightWeak: true),
        ],
      ),
    );
  }

  Widget _subjectPerformanceCard() {
    return Card(
      child: Column(
        children: [
          for (final area in _controller.subjectPerformance) _subjectTile(area),
        ],
      ),
    );
  }

  Widget _subjectTile(SubjectBreakdownItem item, {bool highlightWeak = false}) {
    final theme = Theme.of(context);
    final color = highlightWeak ? theme.colorScheme.error : theme.colorScheme.primary;
    return ListTile(
      leading: Icon(Icons.menu_book, color: color),
      title: Text(item.subjectName),
      subtitle: Text('${item.correct}/${item.attempted} correct'),
      trailing: Text(
        '${item.accuracy.toStringAsFixed(0)}%',
        style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _recentTestsList() {
    if (_controller.recentResults.isEmpty) {
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
