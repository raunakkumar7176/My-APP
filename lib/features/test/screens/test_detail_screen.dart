import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/result_batch.dart';
import '../domain/test_lifecycle.dart';
import '../state/attempt_launch_store.dart';
import '../state/test_detail_controller.dart';
import '../widgets/test_formatters.dart';

/// Detail by id. Every action delegates to the controller; the server
/// re-validates publish/start/generate.
class TestDetailScreen extends StatefulWidget {
  const TestDetailScreen({required this.testId, this.controller, super.key});

  final String testId;
  final TestDetailController? controller;

  @override
  State<TestDetailScreen> createState() => _TestDetailScreenState();
}

enum _MoreAction { delete }

class _TestDetailScreenState extends State<TestDetailScreen> {
  late final TestDetailController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? TestDetailController(testId: widget.testId);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.error : AppColors.success,
    ));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on AppError catch (e) {
      if (mounted) _snack(e.message, error: true);
    }
  }

  Future<void> _publish() => _run(() async {
        await _c.publish();
        if (mounted) _snack('Test published successfully');
      });

  Future<void> _start() => _run(() async {
        final launched = await _c.start();
        if (!mounted) return;
        // Hand the server response to the taking screen in memory; the route
        // itself carries ids only (a cold start falls back to server resume).
        AttemptLaunchStore.putLaunch(
          started: launched.started,
          questions: launched.questions,
          test: launched.test,
        );
        final a = launched.started.attempt;
        context.go('/attempts/${a.id}/take?test=${a.testId}');
      });

  Future<void> _generate() => _run(() async {
        final batch = await _c.generateResults();
        if (mounted) _snack(_batchMessage(batch), error: batch.isFailed);
      });

  /// Communicates exactly what the RPC returned; `errors > 0` is a partial
  /// outcome, not an RPC failure.
  static String _batchMessage(ResultBatch b) {
    final progress = '${b.reportsDone ?? 0} / ${b.reportsTotal ?? 0} reports';
    final errors = b.hasErrors ? ', ${b.errors} error(s)' : '';
    final prefix = b.reused ? 'Results already generated' : 'Results generated';
    switch (b.status) {
      case BatchStatus.completed:
        return '$prefix: $progress$errors';
      case BatchStatus.partiallyCompleted:
        return '$prefix (partial): $progress$errors';
      case BatchStatus.failed:
        return 'Result generation failed: $progress$errors';
      case BatchStatus.pending:
      case BatchStatus.processing:
        return b.reused
            ? 'Result generation already in progress: $progress'
            : 'Result generation started: $progress';
      case BatchStatus.unknown:
        return '$prefix: $progress$errors';
    }
  }

  Future<void> _edit() async {
    await context.push('/tests/${widget.testId}/edit');
    if (mounted) await _c.refresh();
  }

  /// Explicit confirmation; a single tap never deletes.
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Test?'),
        content: const Text(
          'This draft test will be removed from your test list. '
          'This cannot be undone from the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Test'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _delete();
  }

  Future<void> _delete() => _run(() async {
        await _c.deleteDraft();
        if (!mounted) return;
        // Feedback on the root messenger so it survives leaving this route.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Test deleted.')));
        // Opened from the listing → pop (the listing refreshes on return);
        // cold-started deep link → go to My Drafts.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/tests/drafts');
        }
      });

  @override
  Widget build(BuildContext context) {
    final test = _c.test;
    if (_c.isDeleted) {
      // Deleted in this session: nothing to act on while we navigate away.
      return Scaffold(
        appBar: AppBar(title: const Text('Test')),
        body: const Center(child: Text('Test deleted.')),
      );
    }
    if (_c.isLoading && test == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Test')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (test == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Test')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                Text(_c.error ?? 'Test not found.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _c.refresh, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final statusColor = TestFormatters.statusColor(test.status);
    final startReason = _c.startBlockReason(formatDateTime: TestFormatters.dateTime);

    return Scaffold(
      appBar: AppBar(
        title: Text(test.title),
        actions: [
          // Draft-only secondary action, tucked into "More" (never a
          // prominent destructive button on every detail screen).
          if (_c.canDelete)
            PopupMenuButton<_MoreAction>(
              tooltip: 'More',
              enabled: !_c.isBusy,
              onSelected: (a) {
                if (a == _MoreAction.delete) _confirmDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _MoreAction.delete,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete Test'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                _badge(TestLifecycle.statusLabel(test.status), statusColor),
                const SizedBox(width: 8),
                _badge(_c.kind.label, AppColors.primaryLight),
              ],
            ),
            if (test.description != null && test.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(test.description!),
            ],
            const SizedBox(height: 16),
            _section(context, 'Configuration', [
              _row('Duration', TestFormatters.duration(test.durationSec)),
              _row('Marks per question', test.marksPerQuestion?.toString() ?? '--'),
              _row('Negative marks', test.negativeMarks?.toString() ?? 'None'),
            ]),
            if (test.startsAt != null || test.endsAt != null)
              _section(context, 'Schedule', [
                _row('Starts', TestFormatters.dateTime(test.startsAt)),
                _row('Ends', TestFormatters.dateTime(test.endsAt)),
                if (test.maxParticipants != null)
                  _row('Max participants', '${test.maxParticipants}'),
                _row('Late join', test.allowLateJoin ? 'Allowed' : 'Not allowed'),
              ]),
            if (_c.isOwner && (test.accessCode != null || _c.showsJoinCode))
              _section(context, 'Access', [
                if (test.accessCode != null) _row('Access code', 'Set'),
                if (_c.showsJoinCode) _row('Join code', test.joinCode!),
              ]),
            if (_c.isOwner && _c.latestBatch != null)
              _section(context, 'Batch results', [
                _row('Status', _c.latestBatch!.status.name),
                _row('Reports',
                    '${_c.latestBatch!.reportsDone ?? 0} / ${_c.latestBatch!.reportsTotal ?? 0}'),
                if (_c.latestBatch!.hasErrors)
                  _row('Errors', '${_c.latestBatch!.errors}'),
                if (_c.latestBatch!.reused) _row('Note', 'Existing batch reused'),
              ]),
            const SizedBox(height: 16),
            ..._actions(startReason),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(String? startReason) {
    final busy = _c.isBusy;
    final widgets = <Widget>[];

    if (_c.canEdit) {
      widgets.add(FilledButton.icon(
        onPressed: busy ? null : _edit,
        icon: const Icon(Icons.edit),
        label: const Text('Continue Editing'),
      ));
    }
    if (_c.canPublish) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(OutlinedButton.icon(
        onPressed: busy ? null : _publish,
        icon: busy ? _spinner() : const Icon(Icons.publish),
        label: Text(busy ? 'Working…' : 'Publish'),
      ));
    }
    if (!_c.canEdit) {
      if (startReason == null) {
        widgets.add(FilledButton.icon(
          onPressed: busy ? null : _start,
          icon: busy ? _spinner() : const Icon(Icons.play_arrow),
          label: Text(busy ? 'Starting…' : 'Start Test'),
        ));
      } else {
        widgets.add(Text(
          startReason,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
          textAlign: TextAlign.center,
        ));
      }
    }
    if (_c.canGenerateResults) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(OutlinedButton.icon(
        onPressed: busy ? null : _generate,
        icon: const Icon(Icons.assessment_outlined),
        label: const Text('Generate Results'),
      ));
    }
    return widgets;
  }

  Widget _spinner() => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
