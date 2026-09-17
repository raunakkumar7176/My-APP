import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/result.dart';
import '../domain/attempt_history.dart';
import '../state/results_controller.dart';
import '../widgets/subject_analysis_card.dart';
import '../widgets/test_formatters.dart';
import '../widgets/topic_analysis_card.dart';

/// Result by attempt id. Everything shown comes from the server's result
/// row; the client neither scores nor grades.
class TestResultScreen extends StatefulWidget {
  const TestResultScreen({required this.attemptId, this.controller, super.key});

  final String attemptId;
  final ResultsController? controller;

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  late final ResultsController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? ResultsController(attemptId: widget.attemptId);
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  Future<void> _reattempt() async {
    try {
      final launch = await _c.reattempt();
      if (!mounted) return;
      context.go('/attempts/${launch.attemptId}/take?test=${launch.testId}');
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _c.result;
    if (_c.isLoading && r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.hourglass_top, size: 48, color: AppColors.warning),
                const SizedBox(height: 12),
                Text(_c.error ?? 'Result not available.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _c.load, child: const Text('Retry')),
                TextButton(onPressed: () => context.go('/tests'), child: const Text('Back to Tests')),
              ],
            ),
          ),
        ),
      );
    }

    final pct = r.percentage ?? _pct(r);
    final passed = r.isPassed;
    final previous = _c.previousResult;

    return Scaffold(
      appBar: AppBar(
        title: Text(_c.test?.title ?? 'Result'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/tests'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(_c.kind.label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  Text(
                    pct == null ? '--' : '${pct.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: passed == null
                              ? null
                              : (passed ? AppColors.success : AppColors.error),
                        ),
                  ),
                  if (r.score != null || r.maxScore != null)
                    Text('Score ${_num(r.score)} / ${_num(r.maxScore)}',
                        style: Theme.of(context).textTheme.titleMedium),
                  if (passed != null) ...[
                    const SizedBox(height: 4),
                    Text(passed ? 'Passed' : 'Not passed',
                        style: TextStyle(
                            color: passed ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.w600)),
                  ],
                  if (r.rank != null) ...[
                    const SizedBox(height: 4),
                    Text('Rank #${r.rank}'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Correct', r.correctCount, AppColors.success),
              const SizedBox(width: 8),
              _stat('Wrong', r.wrongCount, AppColors.error),
              const SizedBox(width: 8),
              _stat('Unanswered', r.unansweredCount, AppColors.warning),
            ],
          ),
          if (r.accuracy != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.track_changes),
                title: const Text('Accuracy'),
                trailing: Text('${r.accuracy!.toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
          if (previous != null) ...[
            const SizedBox(height: 12),
            _ComparisonCard(
              headline: _delta(pct, previous.percentage ?? _pct(previous)),
              delta: _c.deltaFromPrevious,
              previousNumber: _c.previousEntry?.attemptNumber,
            ),
          ],
          if (_c.subjectBreakdown.isNotEmpty) ...[
            const SizedBox(height: 12),
            SubjectAnalysisCard(items: _c.subjectBreakdown),
          ],
          if (_c.topicBreakdown.isNotEmpty) ...[
            const SizedBox(height: 12),
            TopicAnalysisCard(items: _c.topicBreakdown),
          ],
          if (_c.attemptHistory.length > 1) ...[
            const SizedBox(height: 12),
            _AttemptSummaryCard(
              latest: _c.latestEntry,
              best: _c.bestEntry,
              currentAttemptId: r.attemptId,
            ),
            const SizedBox(height: 12),
            _AttemptHistoryCard(
              entries: _c.attemptHistory,
              currentAttemptId: r.attemptId,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push('/attempts/${widget.attemptId}/review'),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review Answers'),
          ),
          const SizedBox(height: 8),
          // Only an explicit re-attempt may request attempt N+1 (server-enforced).
          if (_c.canReattempt) ...[
            OutlinedButton.icon(
              onPressed: _c.isBusy ? null : _reattempt,
              icon: const Icon(Icons.replay),
              label: Text(_c.isBusy ? 'Starting…' : 'Re-attempt'),
            ),
            const SizedBox(height: 8),
          ] else if (_c.attemptState != null && _c.attemptState!.hasAnyAttempt) ...[
            Text(
              _c.attemptState!.settings.allowReattempt
                  ? '${_c.attemptState!.usageLabel} · Re-attempt limit reached'
                  : 'This test allows a single attempt',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
          TextButton(
            onPressed: () => context.go('/tests'),
            child: const Text('Back to Tests'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int? value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text('${value ?? '--'}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: color, fontWeight: FontWeight.w700)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  static double? _pct(Result r) {
    if (r.score == null || r.maxScore == null || r.maxScore == 0) return null;
    return r.score! / r.maxScore! * 100;
  }

  static String _num(double? v) => v == null ? '--' : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

  static String _delta(double? current, double? previous) {
    if (current == null || previous == null) return 'Previous attempt available';
    final d = current - previous;
    if (d.abs() < 0.05) return 'Same as your previous attempt';
    return d > 0
        ? 'Up ${d.toStringAsFixed(1)} points from your previous attempt'
        : 'Down ${d.abs().toStringAsFixed(1)} points from your previous attempt';
  }
}

// ── attempt history widgets (stored fields only; no derived analytics) ──

String _fmtNum(double? v) =>
    v == null ? '--' : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

String _signed(num v, {String suffix = ''}) {
  final s = v is int ? '$v' : _fmtNum(v.toDouble());
  return (v > 0 ? '+$s' : s) + suffix;
}

String _fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.headline,
    required this.delta,
    required this.previousNumber,
  });

  final String headline;
  final ResultDelta? delta;
  final int? previousNumber;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final rows = <(String, String)>[
      if (d?.score != null) ('Marks', _signed(d!.score!)),
      if (d?.percentage != null) ('Percentage', _signed(d!.percentage!, suffix: ' pts')),
      if (d?.accuracy != null) ('Accuracy', _signed(d!.accuracy!, suffix: ' pts')),
      if (d?.correct != null) ('Correct', _signed(d!.correct!)),
      if (d?.wrong != null) ('Wrong', _signed(d!.wrong!)),
      if (d?.unanswered != null) ('Unanswered', _signed(d!.unanswered!)),
      if (d?.time != null)
        ('Time', '${d!.time!.isNegative ? '-' : '+'}${_fmtDuration(d.time!.abs())}'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.compare_arrows),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  previousNumber == null
                      ? 'Compared with previous attempt'
                      : 'Compared with attempt $previousNumber',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(headline),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(label), Text(value)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttemptSummaryCard extends StatelessWidget {
  const _AttemptSummaryCard({
    required this.latest,
    required this.best,
    required this.currentAttemptId,
  });

  final AttemptHistoryEntry? latest;
  final AttemptHistoryEntry? best;
  final String currentAttemptId;

  String _line(AttemptHistoryEntry e) {
    final n = e.attemptNumber == null ? '' : 'Attempt ${e.attemptNumber} · ';
    final r = e.result;
    final pct = r.percentage == null ? '' : ' (${_fmtNum(r.percentage)}%)';
    return '$n${_fmtNum(r.score)} / ${_fmtNum(r.maxScore)}$pct';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          if (latest != null)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Latest Attempt'),
              subtitle: Text(_line(latest!)),
              trailing: latest!.result.attemptId == currentAttemptId
                  ? const Text('Viewing')
                  : null,
            ),
          if (best != null)
            ListTile(
              leading: const Icon(Icons.emoji_events_outlined),
              title: const Text('Best Attempt'),
              subtitle: Text(_line(best!)),
              trailing:
                  best!.result.attemptId == currentAttemptId ? const Text('Viewing') : null,
            ),
        ],
      ),
    );
  }
}

class _AttemptHistoryCard extends StatelessWidget {
  const _AttemptHistoryCard({required this.entries, required this.currentAttemptId});

  final List<AttemptHistoryEntry> entries;
  final String currentAttemptId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Attempt History', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final e in entries.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: e.result.attemptId == currentAttemptId
                      ? null
                      : () => context.push('/attempts/${e.result.attemptId}/result'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.attemptNumber == null
                                  ? 'Attempt'
                                  : 'Attempt ${e.attemptNumber}'
                                      '${e.result.attemptId == currentAttemptId ? ' (current)' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '${_fmtNum(e.result.score)} / ${_fmtNum(e.result.maxScore)}'
                              '${e.result.percentage == null ? '' : ' · ${_fmtNum(e.result.percentage)}%'}'
                              '${e.result.accuracy == null ? '' : ' · acc ${_fmtNum(e.result.accuracy)}%'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'C ${e.result.correctCount ?? '--'} · W ${e.result.wrongCount ?? '--'} · U ${e.result.unansweredCount ?? '--'}'
                              '${e.duration == null ? '' : ' · ${_fmtDuration(e.duration!)}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (e.completedAt != null)
                        Text(TestFormatters.dateTime(e.completedAt),
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
