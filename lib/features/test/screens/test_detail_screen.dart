import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/result_batch.dart';
import '../domain/attempt_policy.dart';
import '../domain/test_kind.dart';
import '../domain/test_lifecycle.dart';
import '../state/attempt_launch_store.dart';
import '../state/challenge_controller.dart';
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

enum _MoreAction { delete, questionPaper }

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
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

  /// Mandatory pre-test disclaimer + instructions gate: shown before a NEW
  /// attempt (Start Test and Re-attempt) — never before an attempt exists,
  /// so Cancel/back/outside-tap never creates one. Resuming an in_progress
  /// attempt skips it — the timer is already running. Returns the accepted
  /// language ("en"/"hi") only when the explicit acknowledgement button was
  /// pressed with the checkbox checked; null otherwise (declined/backed out).
  Future<String?> _acknowledgeInstructions({required bool reattempt}) async {
    final t = _c.test;
    if (t == null) return null;
    final testLines = <String>[
      '${_c.kind.label} · ${_c.questionCountLabel} question(s) · ${TestFormatters.duration(t.durationSec)}',
      if (t.endsAt != null)
        'Your answers are submitted automatically at the deadline or at ${TestFormatters.dateTime(t.endsAt)}, whichever is first.'
      else
        'Your answers are submitted automatically when the time is up.',
      'Attempts: ${_c.attemptPolicyLabel}.',
      if (t.negativeMarks != null && t.negativeMarks! > 0)
        'Negative marking: ${t.negativeMarks} per wrong answer.',
      if (t.instructions != null && t.instructions!.trim().isNotEmpty)
        t.instructions!.trim(),
    ];
    final language = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DisclaimerDialog(
        reattempt: reattempt,
        testLines: testLines,
      ),
    );
    return mounted ? language : null;
  }

  Future<void> _start() async {
    // Resume needs no gate; only a brand-new attempt does.
    final resuming =
        _c.attemptState?.inProgress != null && !_c.attemptsLoadFailed;
    String? language;
    if (!resuming) {
      language = await _acknowledgeInstructions(reattempt: false);
      if (language == null) return;
    }
    await _launch(_c.start, disclaimerLanguage: language);
  }

  Future<void> _reattempt() async {
    final language = await _acknowledgeInstructions(reattempt: true);
    if (language == null) return;
    await _launch(_c.reattempt, disclaimerLanguage: language);
  }

  /// Builds the student question paper from `get_test_questions_safe` (the
  /// server applies access rules; the response never carries the key) and
  /// hands it to the platform share/save sheet.
  Future<void> _downloadQuestionPaper() => _run(() async {
    final bytes = await _c.buildQuestionPaperPdf();
    if (!mounted) return;
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_c.test?.title ?? 'test'} - question paper.pdf',
    );
  });

  Future<void> _copyJoinCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _snack('Join code copied');
  }

  bool _hostingChallenge = false;

  /// Mints a Peer Challenge session for this test (`rpc_create_challenge_session`,
  /// migration 0061) and opens the waiting room. Supersedes the old
  /// join-code sharing flow for challengeWithFriends tests going forward —
  /// that flow is left in place (untouched) rather than removed.
  Future<void> _hostChallenge() async {
    final test = _c.test;
    if (test == null || _hostingChallenge) return;
    setState(() => _hostingChallenge = true);
    final controller = ChallengeController();
    try {
      await controller.createSession(
        testId: test.id,
        title: test.title,
        subject: 'General Studies',
        durationMinutes: ((test.durationSec ?? 1800) / 60).round(),
      );
      if (!mounted) return;
      if (controller.error != null) {
        _snack(controller.error!, error: true);
        return;
      }
      context.push(
        '/challenge/${controller.session!.id}/waiting-room',
        extra: controller,
      );
    } finally {
      if (mounted) setState(() => _hostingChallenge = false);
    }
  }

  Future<void> _launch(
    Future<LaunchedAttempt> Function() action, {
    String? disclaimerLanguage,
  }) => _run(() async {
    final launched = await action();
    if (!mounted) return;
    // Hand the server response to the taking screen in memory; the route
    // itself carries ids only (a cold start falls back to server resume).
    AttemptLaunchStore.putLaunch(
      started: launched.started,
      questions: launched.questions,
      test: launched.test,
    );
    final a = launched.started.attempt;
    // Only ever called with an attempt that was just created by the
    // disclaimer-gated action above — never for a resumed attempt (the
    // disclaimer, and therefore this call, is skipped entirely on resume).
    if (disclaimerLanguage != null) {
      unawaited(
        _c.acceptDisclaimer(
          attemptId: a.id,
          version: testDisclaimerVersion,
          language: disclaimerLanguage,
        ),
      );
    }
    context.push('/attempts/${a.id}/take?test=${a.testId}');
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
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Test?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This draft test will be removed from your test list. '
              'This cannot be undone from the app.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('delete_reason'),
              controller: reason,
              maxLength: 140,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                isDense: true,
              ),
            ),
          ],
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
    final text = reason.text.trim();
    // The dialog route is still animating out; dispose once it is gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => reason.dispose());
    if (confirmed != true || !mounted) return;
    await _delete(reason: text.isEmpty ? null : text);
  }

  Future<void> _delete({String? reason}) => _run(() async {
    await _c.deleteDraft(reason: reason);
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
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 12),
                Text(
                  _c.error ?? 'Test not found.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _c.refresh, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final statusColor = TestFormatters.statusColor(test.status);
    final startReason = _c.startBlockReason(
      formatDateTime: TestFormatters.dateTime,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(test.title),
        actions: [
          // Draft-only secondary action, tucked into "More" (never a
          // prominent destructive button on every detail screen).
          if (_c.canDelete || _c.isOwner)
            PopupMenuButton<_MoreAction>(
              tooltip: 'More',
              enabled: !_c.isBusy,
              onSelected: (a) {
                switch (a) {
                  case _MoreAction.delete:
                    _confirmDelete();
                  case _MoreAction.questionPaper:
                    _downloadQuestionPaper();
                }
              },
              itemBuilder: (_) => [
                // Creator-only: the paper is built from the safe question
                // path (no answer key) and shared via the platform sheet.
                if (_c.isOwner)
                  const PopupMenuItem(
                    value: _MoreAction.questionPaper,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('Download question paper'),
                    ),
                  ),
                if (_c.canDelete)
                  const PopupMenuItem(
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
            // ── Pre-test information: every value comes from the stored row
            //    (nothing fabricated; absent data shows as "--"). ──
            _section(context, 'About this test', [
              _row('Test type', _c.kind.label),
              _row('What it is', _c.kind.purpose),
              _row('Questions', _c.questionCountLabel),
              _row('Duration', TestFormatters.duration(test.durationSec)),
              _row(
                'Marks per question',
                test.marksPerQuestion?.toString() ?? '--',
              ),
              _row('Negative marks', test.negativeMarks?.toString() ?? 'None'),
              _row('Attempts', _c.attemptPolicyLabel),
              if (_c.kind.supportsLateJoin)
                _row('Late joining', _c.lateJoinLabel),
              if (_c.scopeLabel != null) _row('Syllabus scope', _c.scopeLabel!),
              if (test.groupId != null) _row('Group', _c.groupLabel),
              if (test.instructions != null && test.instructions!.isNotEmpty)
                _row('Instructions', test.instructions!),
            ]),
            if (test.startsAt != null || test.endsAt != null)
              _section(context, 'Schedule', [
                _row('Starts', TestFormatters.dateTime(test.startsAt)),
                _row('Ends', TestFormatters.dateTime(test.endsAt)),
                if (test.maxParticipants != null)
                  _row('Max participants', '${test.maxParticipants}'),
              ]),
            if (_c.isOwner && (test.accessCode != null || _c.showsJoinCode))
              _section(context, 'Access', [
                if (test.accessCode != null) _row('Access code', 'Set'),
                if (_c.showsJoinCode)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'Join code',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        SelectableText(
                          test.joinCode!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          tooltip: 'Copy join code',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => _copyJoinCode(test.joinCode!),
                        ),
                      ],
                    ),
                  ),
              ]),
            if (_c.isOwner && _c.kind == TestKind.challengeWithFriends)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FilledButton.icon(
                  key: const Key('host_peer_challenge_btn'),
                  onPressed: _hostingChallenge ? null : _hostChallenge,
                  icon: _hostingChallenge
                      ? _spinner()
                      : const Icon(Icons.pin_outlined),
                  label: Text(
                    _hostingChallenge
                        ? 'Creating session…'
                        : 'Host as Peer Challenge (Get PIN)',
                  ),
                ),
              ),
            if (_c.isOwner && _c.latestBatch != null)
              _section(context, 'Batch results', [
                _row('Status', _c.latestBatch!.status.name),
                _row(
                  'Reports',
                  '${_c.latestBatch!.reportsDone ?? 0} / ${_c.latestBatch!.reportsTotal ?? 0}',
                ),
                if (_c.latestBatch!.hasErrors)
                  _row('Errors', '${_c.latestBatch!.errors}'),
                if (_c.latestBatch!.reused)
                  _row('Note', 'Existing batch reused'),
              ]),
            const SizedBox(height: 16),
            ..._actions(startReason),
          ],
        ),
      ),
    );
  }

  /// State machine for the student CTA (mirrors [AttemptPolicyState.cta]):
  /// Start Test → Continue Test → View Result [+ Re-attempt | limit reached].
  /// "Back to Tests" is navigation only; only Re-attempt asks for attempt N+1.
  List<Widget> _attemptActions(bool busy) {
    final s = _c.attemptState;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.outline);
    FilledButton primary(IconData icon, String label, VoidCallback onTap) =>
        FilledButton.icon(
          onPressed: busy ? null : onTap,
          icon: busy ? _spinner() : Icon(icon),
          label: Text(busy ? 'Starting…' : label),
        );

    // Attempts unreadable: offer a plain start; the server resumes or rejects.
    if (s == null || _c.attemptsLoadFailed) {
      return [primary(Icons.play_arrow, 'Start Test', _start)];
    }

    switch (s.cta) {
      case AttemptCta.startTest:
        return [primary(Icons.play_arrow, 'Start Test', _start)];
      case AttemptCta.continueTest:
        return [
          Text(
            'Attempt ${s.inProgress!.attemptNumber} · In progress',
            textAlign: TextAlign.center,
            style: muted,
          ),
          const SizedBox(height: 8),
          primary(Icons.play_arrow, 'Continue Test', _start),
        ];
      case AttemptCta.reattempt:
      case AttemptCta.limitReached:
        final last = s.latestCompleted!;
        return [
          Text(
            'Attempt ${last.attemptNumber} · Completed · ${s.usageLabel}',
            textAlign: TextAlign.center,
            style: muted,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => context.push('/attempts/${last.id}/result'),
            icon: const Icon(Icons.assessment_outlined),
            label: const Text('View Result'),
          ),
          const SizedBox(height: 8),
          if (s.cta == AttemptCta.reattempt)
            primary(Icons.replay, 'Re-attempt', _reattempt)
          else
            Text(
              s.settings.allowReattempt
                  ? 'Re-attempt limit reached'
                  : 'This test allows a single attempt',
              textAlign: TextAlign.center,
              style: muted,
            ),
        ];
    }
  }

  List<Widget> _actions(String? startReason) {
    final busy = _c.isBusy;
    final widgets = <Widget>[];

    if (_c.canEdit) {
      widgets.add(
        FilledButton.icon(
          onPressed: busy ? null : _edit,
          icon: const Icon(Icons.edit),
          label: const Text('Continue Editing'),
        ),
      );
    }
    if (_c.canPublish) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        OutlinedButton.icon(
          onPressed: busy ? null : _publish,
          icon: busy ? _spinner() : const Icon(Icons.publish),
          label: Text(busy ? 'Working…' : 'Publish'),
        ),
      );
    }
    if (!_c.canEdit) {
      if (startReason == null) {
        widgets.addAll(_attemptActions(busy));
      } else {
        // Window closed / not open: a completed attempt's result stays reachable.
        final last = _c.attemptState?.latestCompleted;
        if (last != null) {
          widgets.add(
            OutlinedButton.icon(
              onPressed: () => context.push('/attempts/${last.id}/result'),
              icon: const Icon(Icons.assessment_outlined),
              label: Text('View Result (Attempt ${last.attemptNumber})'),
            ),
          );
          widgets.add(const SizedBox(height: 8));
        }
        widgets.add(
          Text(
            startReason,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        );
      }
    }
    if (_c.canGenerateResults) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        OutlinedButton.icon(
          onPressed: busy ? null : _generate,
          icon: const Icon(Icons.assessment_outlined),
          label: const Text('Generate Results'),
        ),
      );
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
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed disclaimer text version — bump only alongside a real content
/// change, per this feature's own "do not hardcode a future versioning
/// system unless needed" instruction.
const String testDisclaimerVersion = 'v1';

const List<String> _disclaimerPointsEn = [
  'Once the test starts, the timer will run according to the configured test duration.',
  'Leaving the app, changing screens, or other suspicious activities may be recorded by the system.',
  'Question order may be different for each student. Therefore, question numbers should not be used to assume that another student has the same question at the same position.',
  'Each answer is saved against the actual question identity.',
  'After submission, answers may not be editable where the configured test rules prohibit changes.',
  'Report technical problems immediately to your teacher or group leader.',
  'Make sure you have sufficient time and a stable internet connection before starting.',
  'Do not use unauthorized assistance or unfair means during the test.',
  'Once the test starts, the configured test rules and time limit must be followed.',
];

const List<String> _disclaimerPointsHi = [
  'टेस्ट शुरू करने के बाद निर्धारित समय के अनुसार टाइमर चलेगा।',
  'टेस्ट के दौरान ऐप से बाहर जाने, स्क्रीन बदलने या अन्य संदिग्ध गतिविधियों को सिस्टम द्वारा रिकॉर्ड किया जा सकता है।',
  'टेस्ट में प्रश्नों का क्रम प्रत्येक विद्यार्थी के लिए अलग हो सकता है। इसलिए प्रश्न संख्या देखकर दूसरे विद्यार्थी से उत्तर मिलाना संभव नहीं माना जाएगा।',
  'प्रत्येक प्रश्न का उत्तर उसी प्रश्न की पहचान के आधार पर सेव किया जाएगा।',
  'टेस्ट सबमिट करने के बाद उत्तरों में बदलाव की अनुमति नहीं होगी, यदि टेस्ट नियम ऐसा निर्धारित करते हैं।',
  'तकनीकी समस्या होने पर तुरंत अपने शिक्षक/ग्रुप लीडर को सूचित करें।',
  'टेस्ट शुरू करने से पहले सुनिश्चित करें कि आपके पास पर्याप्त समय और स्थिर इंटरनेट कनेक्शन है।',
  'टेस्ट के दौरान अनुचित साधनों या सहायता का उपयोग न करें।',
  'टेस्ट शुरू करने के बाद लागू टेस्ट नियमों और समय सीमा का पालन करना आवश्यक है।',
];

/// Mandatory pre-test disclaimer. Purely a client-side gate: no attempt
/// exists yet when this is shown (Cancel/back/outside-tap/barrier never
/// creates one — `barrierDismissible: false` plus `PopScope`-equivalent
/// AlertDialog default already refuses a bare back-press dismissal on
/// Android; the only ways out are the two explicit buttons). Language
/// toggle and the checkbox are local UI state — neither one, by itself,
/// can close the dialog or start the test.
class _DisclaimerDialog extends StatefulWidget {
  const _DisclaimerDialog({required this.reattempt, required this.testLines});

  final bool reattempt;
  final List<String> testLines;

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _hindi = false;
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = _hindi ? _disclaimerPointsHi : _disclaimerPointsEn;
    return AlertDialog(
      title: Text(
        widget.reattempt
            ? (_hindi ? 'क्या आप दोबारा प्रयास करना चाहते हैं?' : 'Re-attempt this test?')
            : (_hindi ? 'शुरू करने से पहले' : 'Before you start'),
      ),
      content: ConstrainedBox(
        // Bounded on all platforms: a fixed max width keeps the dialog
        // readable on desktop/tablet without ever demanding unbounded
        // width, and the content itself scrolls rather than assuming any
        // fixed height — safe on the smallest phone screens too.
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: SegmentedButton<bool>(
                  key: const Key('disclaimer_language_toggle'),
                  segments: const [
                    ButtonSegment(value: false, label: Text('English')),
                    ButtonSegment(value: true, label: Text('हिंदी')),
                  ],
                  selected: {_hindi},
                  onSelectionChanged: (s) => setState(() => _hindi = s.first),
                ),
              ),
              const SizedBox(height: 12),
              for (final l in widget.testLines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $l', style: theme.textTheme.bodyMedium),
                ),
              const Divider(height: 24),
              Text(
                _hindi
                    ? 'टेस्ट शुरू करने से पहले कृपया निम्न बातों को ध्यानपूर्वक पढ़ें:'
                    : 'Please read the following instructions carefully before starting the test:',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < points.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${i + 1}. ${points[i]}', style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const Key('disclaimer_acknowledge_checkbox'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                title: Text(
                  _hindi
                      ? 'मैं इन टेस्ट निर्देशों को समझता/समझती हूँ और उनका पालन करने के लिए सहमत हूँ।'
                      : 'I understand and agree to follow these test instructions.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('disclaimer_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_hindi ? 'रद्द करें' : 'Cancel'),
        ),
        FilledButton(
          key: const Key('disclaimer_start'),
          onPressed: _agreed
              ? () => Navigator.of(context).pop(_hindi ? 'hi' : 'en')
              : null,
          child: Text(
            _hindi
                ? 'मैं समझता/समझती हूँ और टेस्ट शुरू करें'
                : (widget.reattempt ? 'Start Re-attempt' : 'I Understand & Start Test'),
          ),
        ),
      ],
    );
  }
}
