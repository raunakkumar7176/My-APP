import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/answer.dart';
import '../domain/test_kind.dart';
import '../state/attempt_controller.dart';
import '../widgets/answer_grid.dart';
import '../widgets/countdown_timer.dart';
import '../widgets/question_card.dart';
import '../widgets/save_status_bar.dart';

/// Taking screen by attempt id. No backend orchestration lives here: the
/// controller loads (or server-resumes) the attempt, autosaves and submits;
/// the server owns the deadline and the score.
class TestTakingScreen extends StatefulWidget {
  const TestTakingScreen({
    required this.attemptId,
    required this.testId,
    this.accessCode,
    this.controller,
    super.key,
  });

  final String attemptId;
  final String testId;
  final String? accessCode;
  final AttemptController? controller;

  @override
  State<TestTakingScreen> createState() => _TestTakingScreenState();
}

class _TestTakingScreenState extends State<TestTakingScreen> {
  late final AttemptController _c;
  late final bool _owns;
  final _pages = PageController();

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c =
        widget.controller ??
        AttemptController(
          attemptId: widget.attemptId,
          testId: widget.testId,
          accessCode: widget.accessCode,
        );
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_pages.hasClients && _pages.page?.round() != _c.currentIndex) {
      _pages.jumpToPage(_c.currentIndex);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _pages.dispose();
    if (_owns) _c.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool timedOut}) async {
    try {
      // The RPC may or may not return the results row; the result screen
      // reads it by attempt id either way.
      await _c.submit(timedOut: timedOut);
      if (!mounted) return;
      context.go('/attempts/${_c.attempt?.id ?? widget.attemptId}/result');
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _confirmSubmit() async {
    final total = _c.questions.length;
    final answered = _c.answeredCount;
    final marked = _c.markedCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Test?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Total questions', '$total'),
            _row('Answered', '$answered', color: AppColors.success),
            if (total - answered > 0)
              _row('Unanswered', '${total - answered}', color: AppColors.error),
            if (marked > 0)
              _row('Marked for review', '$marked', color: AppColors.warning),
            if (_c.hasUnsavedAnswers) ...[
              const SizedBox(height: 8),
              Text(
                'Some answers are not saved yet. They will be sent with your '
                'submission; if that fails you can retry without losing them.',
                key: const Key('submit_unsaved_note'),
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: Theme.of(ctx).textTheme.bodySmall?.fontSize,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continue Test'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _submit(timedOut: false);
  }

  Future<void> _onLeave() async {
    if (!_c.isInteractive) {
      context.go('/tests');
      return;
    }
    final unsaved = _c.hasUnsavedAnswers;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Test?'),
        content: Text(
          unsaved
              ? 'Some answers are not saved yet. "Save & Leave" sends them '
                    'first and only leaves once they are safely stored. You can '
                    'resume this attempt until its time limit ends.'
              : 'Your answers are saved automatically and you can resume this '
                    'attempt until its time limit ends. Submit now to get your result.',
          key: Key(unsaved ? 'leave_unsaved_note' : 'leave_saved_note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('Stay'),
          ),
          TextButton(
            key: const Key('leave_action'),
            onPressed: () => Navigator.of(ctx).pop('leave'),
            child: Text(unsaved ? 'Save & Leave' : 'Leave'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('submit'),
            child: const Text('Submit & Leave'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'submit':
        await _submit(timedOut: false);
        break;
      case 'leave':
        // Only leave once the server has the latest answers; otherwise stay
        // so nothing is lost (the timer keeps retrying, "Retry now" too).
        final ok = await _c.retrySave();
        if (!mounted) return;
        if (ok) {
          context.go('/tests');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _c.saveError ?? 'Could not save your answers. Check your connection and try again.',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        break;
      default:
        break;
    }
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_c.error != null || _c.attempt == null) {
      return _message(
        icon: Icons.error_outline,
        title: 'Could not open the test',
        body: _c.error ?? 'Attempt not found.',
        action: FilledButton(onPressed: _c.load, child: const Text('Retry')),
      );
    }
    if (!_c.isInteractive) {
      return _message(
        icon: Icons.lock_clock,
        title: 'This attempt is no longer active',
        body: 'It has already been submitted.',
        action: FilledButton(
          onPressed: () => context.go('/attempts/${_c.attempt!.id}/result'),
          child: const Text('View Result'),
        ),
      );
    }
    // No fake timers: a missing server deadline is an error state, except
    // for a Practice attempt the server itself started untimed (dormant
    // until the backend supports it).
    final untimedPractice =
        _c.deadlineAt == null && _c.kind == TestKind.practice;
    if (_c.deadlineAt == null && !untimedPractice) {
      return _message(
        icon: Icons.timer_off_outlined,
        title: 'Timer Not Available',
        body:
            'The server did not provide a deadline for this attempt. '
            'Please go back and start again.',
        action: FilledButton(
          onPressed: () => context.go('/tests'),
          child: const Text('Back to Tests'),
        ),
      );
    }

    final questions = _c.questions;
    final kindLabel = _c.kind == TestKind.self ? null : _c.kind.label;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onLeave,
          ),
          title: kindLabel == null
              ? Text(_c.test?.title ?? '')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _c.test?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      kindLabel,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
          actions: [
            if (untimedPractice)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: Text('Untimed')),
              )
            else
              CountdownTimer(
                deadlineAt: _c.deadlineAt!,
                onTimeUp: () => _submit(timedOut: true),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            SaveStatusBar(
              status: _c.saveStatus,
              lastSavedAt: _c.lastSavedAt,
              error: _c.saveError,
              failures: _c.saveFailures,
              onRetry: _c.retrySave,
            ),
            if (_c.answersLoadFailed)
              MaterialBanner(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                leading: const Icon(Icons.info_outline, size: 20),
                content: const Text(
                  'Your earlier answers could not be restored right now. '
                  'New answers are still saved and scored.',
                ),
                actions: [
                  TextButton(
                    onPressed: _c.reloadSavedAnswers,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: questions.length,
                onPageChanged: _c.goTo,
                itemBuilder: (context, index) {
                  final q = questions[index];
                  return QuestionCard(
                    question: q,
                    shuffledOptions: _c.optionsFor(q),
                    answer: _c.answerFor(q.id),
                    questionNumber: index + 1,
                    totalQuestions: questions.length,
                    onOptionSelected: (id) => _c.selectOption(q.id, id),
                    onMarkReview: () => _c.toggleMarkForReview(q.id),
                    interactive: true,
                  );
                },
              ),
            ),
            _bottomBar(questions.length),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(int total) {
    final index = _c.currentIndex;
    final answers = <String, Answer>{
      for (final q in _c.questions)
        if (_c.answerFor(q.id) != null) q.id: _c.answerFor(q.id)!,
    };
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            IconButton(
              onPressed: index > 0 ? () => _c.goTo(index - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Question grid',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => AnswerGrid(
                  questionIds: [for (final q in _c.questions) q.id],
                  answers: answers,
                  currentQuestionIndex: index,
                  onQuestionTap: (i) {
                    Navigator.of(context).pop();
                    _c.goTo(i);
                  },
                ),
              ),
              icon: const Icon(Icons.grid_view),
            ),
            Expanded(
              child: Text('${index + 1} / $total', textAlign: TextAlign.center),
            ),
            IconButton(
              onPressed: index < total - 1 ? () => _c.goTo(index + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('submit_button'),
              onPressed: _c.isSubmitting ? null : _confirmSubmit,
              child: Text(_c.isSubmitting ? 'Submitting…' : 'Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    required Widget action,
  }) {
    return Scaffold(
      appBar: AppBar(title: Text(_c.test?.title ?? 'Test')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: AppColors.warning),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
