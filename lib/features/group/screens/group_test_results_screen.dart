import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/result.dart';
import '../../test/domain/test_lifecycle.dart';
import '../../test/widgets/test_formatters.dart';
import '../domain/group_test_results.dart';
import '../state/group_test_results_controller.dart';

/// Group test results (G11). Members: their own stored result, deterministic
/// insights and their stored AI coach report. GENERATE_RESULTS /
/// VIEW_GROUP_ANALYTICS holders and the owner additionally: batch status,
/// "Generate results", "Request AI coach reports", every participant's row
/// and report coverage. Opening the screen never generates anything.
class GroupTestResultsScreen extends StatefulWidget {
  const GroupTestResultsScreen({
    required this.groupId,
    required this.testId,
    this.controller,
    super.key,
  });

  final String groupId;
  final String testId;
  final GroupTestResultsController? controller;

  @override
  State<GroupTestResultsScreen> createState() => _GroupTestResultsScreenState();
}

class _GroupTestResultsScreenState extends State<GroupTestResultsScreen> {
  late final GroupTestResultsController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c =
        widget.controller ??
        GroupTestResultsController(groupId: widget.groupId, testId: widget.testId);
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

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _generate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate results?'),
        content: const Text(
          'Every submitted attempt is scored on the server and stored. '
          'Running it again reuses the existing batch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_generate_results'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _c.generateResults();
    if (!mounted) return;
    _snack(ok ? 'Results generated.' : (_c.error ?? 'Could not generate results.'), error: !ok);
  }

  Future<void> _requestCoach() async {
    final ok = await _c.requestCoachReports();
    if (!mounted) return;
    _snack(
      ok
          ? (_c.coachJob?.created == true
                ? 'AI coach reports queued.'
                : 'AI coach reports were already requested.')
          : (_c.error ?? 'Could not request coach reports.'),
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.hasLoaded && _c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: const Center(
          child: CircularProgressIndicator(key: Key('group_results_loading')),
        ),
      );
    }
    if (_c.accessDenied) {
      return _message(
        key: const Key('group_results_denied'),
        icon: Icons.lock_outline,
        title: 'Results not available',
        body: 'This test does not belong to a group you are a member of.',
      );
    }
    if (_c.test == null) {
      return _message(
        key: const Key('group_results_error'),
        icon: Icons.error_outline,
        title: 'Could not load results',
        body: _c.error ?? 'Please try again.',
        action: FilledButton(
          key: const Key('group_results_retry'),
          onPressed: _c.load,
          child: const Text('Retry'),
        ),
      );
    }
    final test = _c.test!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${test.title} · Results')),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          key: const Key('group_results_list'),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${TestLifecycle.statusLabel(test.status)} · ${_c.group?.name ?? ''}',
              key: const Key('results_test_meta'),
              style: theme.textTheme.bodySmall,
            ),
            if (_c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _c.error!,
                  key: const Key('group_results_action_error'),
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            if (!_c.isResultsPhase)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This test is not over yet; results are prepared once it ends.',
                  key: const Key('results_not_over_note'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            _myResultCard(theme),
            const SizedBox(height: 16),
            _coachReportCard(theme, _c.myReport, title: 'AI Coach Report'),
            if (_c.canGenerateResults || _c.canSeeAllResults) ...[
              const SizedBox(height: 24),
              _managerSection(theme),
            ],
          ],
        ),
      ),
    );
  }

  // ── participant ──

  Widget _myResultCard(ThemeData theme) {
    final r = _c.myResult;
    if (r == null) {
      return Card(
        key: const Key('my_result_empty'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _c.hasAnyResults
                ? 'You have no stored result for this test.'
                : 'No results yet. Results appear after a manager generates them.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    final ins = _c.myInsights!;
    final test = _c.test!;
    return Card(
      key: const Key('my_result_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your result', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${_num(r.score)} / ${_num(r.maxScore)} marks'
              '${r.percentage != null ? ' · ${_num(r.percentage)}%' : ''}'
              '${r.rank != null ? ' · rank ${r.rank}' : ''}',
              key: const Key('my_score'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Correct ${r.correctCount ?? 0} · Wrong ${r.wrongCount ?? 0} · '
              'Unanswered ${r.unansweredCount ?? 0}'
              '${r.accuracy != null ? ' · Accuracy ${_num(r.accuracy)}%' : ''}',
              key: const Key('my_counts'),
            ),
            if (ins.negativeMarksLost > 0)
              Text(
                'Negative marking: −${_num(ins.negativeMarksLost)} '
                '(${_num(test.negativeMarks)} per wrong answer)',
                key: const Key('my_negative'),
              ),
            if (r.computedAt != null)
              Text(
                'Computed ${TestFormatters.dateTime(r.computedAt)}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            if (ins.strongSubjects.isNotEmpty)
              _chips(theme, 'Strong areas', ins.strongSubjects, key: const Key('my_strong')),
            if (ins.weakSubjects.isNotEmpty)
              _chips(theme, 'Weak areas', ins.weakSubjects, key: const Key('my_weak')),
            if (ins.improvementPoints.isNotEmpty) ...[
              Text('Improvement points', style: theme.textTheme.titleSmall),
              for (final p in ins.improvementPoints)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $p'),
                ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('open_detailed_result'),
              onPressed: () => context.push('/attempts/${r.attemptId}/result'),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Question-wise review'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chips(
    ThemeData theme,
    String title,
    List<MapEntry<String, double>> entries, {
    Key? key,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        Wrap(
          spacing: 6,
          children: [
            for (final e in entries)
              Chip(label: Text('${e.key} ${_num(e.value)}%')),
          ],
        ),
      ],
    ),
  );

  Widget _coachReportCard(ThemeData theme, AiCoachReport? rep, {required String title}) {
    if (rep == null || rep.isEmpty) {
      return Card(
        key: const Key('coach_report_empty'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'No coach report stored for you yet. Reports are generated in a '
                'batch by a group manager, never when this screen opens.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    Widget list(String heading, List<String> items, Key key) => items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            key: key,
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heading, style: theme.textTheme.titleSmall),
                for (final i in items) Text('• $i'),
              ],
            ),
          );
    return Card(
      key: const Key('coach_report_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (rep.summary != null) ...[
              const SizedBox(height: 4),
              Text(rep.summary!, key: const Key('coach_summary')),
            ],
            list('Strengths', rep.strengths, const Key('coach_strengths')),
            list('Weak areas', rep.weaknesses, const Key('coach_weaknesses')),
            list('Repeated mistakes', rep.mistakePatterns, const Key('coach_mistakes')),
            if (rep.subjectAnalysis.isNotEmpty)
              Padding(
                key: const Key('coach_subjects'),
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Subject analysis', style: theme.textTheme.titleSmall),
                    for (final s in rep.subjectAnalysis)
                      Text('• ${s.subject} — ${s.performance}: ${s.note}'),
                  ],
                ),
              ),
            list('Revision plan', rep.revisionPlan, const Key('coach_revision')),
            list('Practice plan', rep.practicePlan, const Key('coach_practice')),
            list('Next week', rep.nextWeekActionPlan, const Key('coach_next_week')),
            if (rep.coachMessage != null) ...[
              const SizedBox(height: 8),
              Text(rep.coachMessage!, key: const Key('coach_message'), style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 4),
            Text(
              'Generated ${TestFormatters.dateTime(rep.createdAt)}'
              '${rep.model.isNotEmpty ? ' · ${rep.model}' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // ── managers ──

  Widget _managerSection(ThemeData theme) {
    final b = _c.batch;
    final job = _c.coachJob;
    final busy = _c.isBusy;
    final s = _c.summary;
    return Column(
      key: const Key('results_manager_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Group results', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_c.canGenerateResults) ...[
          Text(
            b == null
                ? 'Results not generated yet.'
                : 'Batch ${b.status.name} · ${b.reportsDone ?? 0}/${b.reportsTotal ?? 0} attempts scored'
                      '${b.completedAt != null ? ' · ${TestFormatters.dateTime(b.completedAt)}' : ''}',
            key: const Key('batch_status'),
          ),
          if (job != null)
            Text(
              'AI coach reports: ${job.status} · ${job.reportsDone}/${job.reportsTotal} stored',
              key: const Key('coach_job_status'),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('generate_results_button'),
                onPressed: busy ? null : _generate,
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: Text(b == null ? 'Generate results' : 'Re-run scoring'),
              ),
              OutlinedButton.icon(
                key: const Key('request_coach_reports_button'),
                onPressed: busy || b == null || !(b.isCompleted || b.isPartiallyCompleted)
                    ? null
                    : _requestCoach,
                icon: const Icon(Icons.psychology_outlined, size: 18),
                label: const Text('Request AI coach reports'),
              ),
            ],
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(key: Key('results_busy')),
            ),
          const SizedBox(height: 16),
        ],
        if (_c.canSeeAllResults) ...[
          Text(
            s.participants == 0
                ? 'No participant results stored.'
                : '${s.participants} participant${s.participants == 1 ? '' : 's'}'
                      '${s.averagePercentage != null ? ' · average ${_num(s.averagePercentage)}%' : ''}'
                      '${s.medianPercentage != null ? ' · median ${_num(s.medianPercentage)}%' : ''}'
                      '${s.highestPercentage != null ? ' · best ${_num(s.highestPercentage)}%' : ''}',
            key: const Key('group_summary'),
          ),
          const SizedBox(height: 8),
          for (final r in _c.results) _participantTile(r),
        ],
      ],
    );
  }

  Widget _participantTile(Result r) => ListTile(
    key: Key('participant_${r.userId}'),
    contentPadding: EdgeInsets.zero,
    leading: r.rank != null ? CircleAvatar(child: Text('${r.rank}')) : null,
    title: Text(_c.participantLabel(r)),
    subtitle: Text(
      '${_num(r.score)} / ${_num(r.maxScore)}'
      '${r.percentage != null ? ' · ${_num(r.percentage)}%' : ''}'
      ' · C ${r.correctCount ?? 0} W ${r.wrongCount ?? 0} U ${r.unansweredCount ?? 0}',
    ),
    trailing: _c.canSeeAllReports
        ? Icon(
            _c.hasReport(r) ? Icons.psychology : Icons.psychology_outlined,
            key: Key('report_flag_${r.userId}'),
            color: _c.hasReport(r) ? AppColors.success : null,
          )
        : null,
  );

  static String _num(double? v) {
    if (v == null) return '--';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  Widget _message({
    required Key key,
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: Center(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action ??
                  FilledButton(
                    onPressed: () => context.go('/groups/${widget.groupId}/tests'),
                    child: const Text('Back to group tests'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
