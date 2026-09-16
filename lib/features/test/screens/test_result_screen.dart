import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/result.dart';
import '../state/results_controller.dart';
import '../widgets/result_history_card.dart';
import '../widgets/subject_analysis_card.dart';
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

  Future<void> _repeat() async {
    try {
      final launch = await _c.repeat();
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
            Card(
              child: ListTile(
                leading: const Icon(Icons.compare_arrows),
                title: const Text('Compared with previous attempt'),
                subtitle: Text(_delta(pct, previous.percentage ?? _pct(previous))),
              ),
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
          if (_c.history.length > 1) ...[
            const SizedBox(height: 12),
            ResultHistoryCard(results: _c.history, currentResultId: r.id),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.push('/attempts/${widget.attemptId}/review'),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review Answers'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _c.isBusy ? null : _repeat,
            icon: const Icon(Icons.replay),
            label: Text(_c.isBusy ? 'Starting…' : 'Repeat Test'),
          ),
          const SizedBox(height: 8),
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
