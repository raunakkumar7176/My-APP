import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/answer.dart';
import '../../../core/widgets/xp_celebration_overlay.dart';
import '../data/challenge_repository.dart';
import '../domain/creation_settings.dart';
import '../domain/test_integrity_monitor.dart';
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
    this.challengeSessionId,
    this.controller,
    super.key,
  });

  final String attemptId;
  final String testId;
  final String? accessCode;

  /// Present when this attempt was launched from a Peer Challenge waiting
  /// room (migration 0061). On submit, the score/accuracy/time are written
  /// back to `challenge_participants` and the student is routed to the
  /// session's merit list instead of the normal result screen.
  final String? challengeSessionId;
  final AttemptController? controller;

  @override
  State<TestTakingScreen> createState() => _TestTakingScreenState();
}

class _TestTakingScreenState extends State<TestTakingScreen> {
  late final AttemptController _c;
  late final bool _owns;
  late final TestIntegrityMonitor _integrity;
  final _pages = PageController();
  bool _warnedOnce = false;
  bool _handledAutoSubmit = false;
  bool _timeExpiredManualSubmit = false;

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
    _integrity = TestIntegrityMonitor(controller: _c)..start();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_pages.hasClients && _pages.page?.round() != _c.currentIndex) {
      _pages.jumpToPage(_c.currentIndex);
    }
    if (!_warnedOnce && _c.isInteractive) {
      _warnedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showIntegrityWarning(),
      );
    }
    if (!_handledAutoSubmit && _c.integrityAutoSubmitted) {
      _handledAutoSubmit = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleIntegrityAutoSubmit(),
      );
    }
  }

  void _showIntegrityWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('integrity_warning_banner'),
        content: Text(
          'Test से बाहर जाने पर integrity violation दर्ज हो सकता है.',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _handleIntegrityAutoSubmit() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('integrity_auto_submit_banner'),
        content: Text(
          'Integrity limit reached. Your test has been automatically submitted.',
        ),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 5),
      ),
    );
    context.pushReplacement(
      '/attempts/${_c.attempt?.id ?? widget.attemptId}/result',
    );
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _integrity.stop();
    _pages.dispose();
    if (_owns) _c.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool timedOut}) async {
    try {
      final scorecard = await _c.submit(timedOut: timedOut);
      if (!mounted) return;
      XpCelebrationOverlay.show(context, points: scorecard.pointsAwarded);
      final challengeSessionId = widget.challengeSessionId;
      if (challengeSessionId != null) {
        final started = _c.attempt?.startedAt;
        final submitted = _c.attempt?.submittedAt ?? DateTime.now();
        final timeTaken = started == null
            ? 0
            : submitted.difference(started).inSeconds.clamp(0, 1 << 30);
        try {
          await const SupabaseChallengeRepository().reportResult(
            sessionId: challengeSessionId,
            score: scorecard.score ?? 0,
            accuracy: scorecard.accuracy ?? 0,
            timeTakenSeconds: timeTaken,
          );
        } catch (e) {
          // The attempt itself is already submitted and scored server-side;
          // a failed merit-list write-back must never strand the student on
          // an error implying their exam wasn't recorded.
          AppLogger.warning('Challenge reportResult failed: $e');
        }
        if (!mounted) return;
        context.pushReplacement('/challenge/$challengeSessionId/merit-list');
        return;
      }
      context.pushReplacement(
        '/attempts/${_c.attempt?.id ?? widget.attemptId}/result',
      );
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
    final unanswered = (total - answered).clamp(0, total);
    final marked = _c.markedCount;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.primary
                          .withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.assignment_turned_in_rounded,
                      color: Theme.of(ctx).colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Submit Test?',
                      style: Theme.of(ctx).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(ctx).colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    _row('Total questions', '$total'),
                    const Divider(height: 16),
                    _row('Answered', '$answered', color: AppColors.success),
                    if (unanswered > 0) ...[
                      const Divider(height: 16),
                      _row('Unanswered', '$unanswered', color: AppColors.error),
                    ],
                    if (marked > 0) ...[
                      const Divider(height: 16),
                      _row(
                        'Marked for review',
                        '$marked',
                        color: const Color(0xFF8B5CF6),
                      ),
                    ],
                  ],
                ),
              ),
              if (_c.hasUnsavedAnswers) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Some answers are not saved yet. They will be sent with your '
                    'submission; if that fails you can retry without losing them.',
                    key: const Key('submit_unsaved_note'),
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: Theme.of(ctx).textTheme.bodySmall?.fontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Continue Test'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(ctx).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) await _submit(timedOut: false);
  }

  Future<void> _onLeave() async {
    if (!_c.isInteractive) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/tests');
      }
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
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/tests');
          }
        } else {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
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
          onPressed: () => context.push('/attempts/${_c.attempt!.id}/result'),
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
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/tests');
            }
          },
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
            tooltip: 'Leave test',
            onPressed: _onLeave,
          ),
          centerTitle: true,
          title: untimedPractice
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_off_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Untimed',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              : CountdownTimer(
                  deadlineAt: _c.deadlineAt!,
                  onTimeUp: () {
                    if (AutoSubmitSettings.fromSettings(_c.test?.settings)
                        .enabled) {
                      _submit(timedOut: true);
                    } else if (mounted) {
                      setState(() => _timeExpiredManualSubmit = true);
                    }
                  },
                ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: FilledButton(
                  key: const Key('submit_button'),
                  onPressed: _c.isSubmitting ? null : _confirmSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 0,
                    ),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _c.isSubmitting ? 'Submitting…' : 'Submit',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
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
            if (_timeExpiredManualSubmit && _c.isInteractive)
              MaterialBanner(
                key: const Key('time_expired_manual_submit_banner'),
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                leading: const Icon(Icons.timer_off_outlined, size: 20),
                content: const Text(
                  "Time's up. Tap Submit whenever you're ready.",
                ),
                actions: [
                  FilledButton(
                    onPressed: () => _submit(timedOut: true),
                    child: const Text('Submit'),
                  ),
                ],
              ),
            _buildUpperProgressStrip(questions.length, kindLabel),
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
                    showProgressHeader: false,
                    kindLabel: kindLabel,
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

  Widget _buildUpperProgressStrip(int total, String? kindLabel) {
    final theme = Theme.of(context);
    final currentIndex = _c.currentIndex;
    final answeredCount = _c.answeredCount;
    final unansweredCount = (total - answeredCount).clamp(0, total);
    final currentQ = total > 0 && currentIndex < total
        ? _c.questions[currentIndex]
        : null;
    final currentAnswer = currentQ != null ? _c.answerFor(currentQ.id) : null;
    final isMarked = currentAnswer?.markedForReview ?? false;
    final progress = total > 0 ? (answeredCount / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                // Left: Capsule chip with current index: Q {currentIndex + 1} of {totalQuestions}
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    'Q ${currentIndex + 1} of $total',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Middle: Realtime counters
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '● $answeredCount Answered',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF64748B)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '○ $unansweredCount Left',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Right: Bookmark toggle icon button
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: isMarked ? 'Remove Bookmark' : 'Bookmark Question',
                  icon: Icon(
                    isMarked ? Icons.bookmark : Icons.bookmark_border,
                    color: isMarked
                        ? const Color(0xFF7C3AED)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    size: 22,
                  ),
                  onPressed: currentQ != null
                      ? () => _c.toggleMarkForReview(currentQ.id)
                      : null,
                ),
              ],
            ),
          ),
          // Below this row: A thin 3px linear progress indicator: answeredCount / totalQuestions
          LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(int total) {
    final theme = Theme.of(context);
    final index = _c.currentIndex;
    final isFirst = index <= 0;
    final isLast = index >= total - 1;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left Button: [ < Previous ] (outlined, disabled on question 0)
              OutlinedButton.icon(
                key: const Key('previous_button'),
                onPressed: isFirst ? null : () => _c.goTo(index - 1),
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                label: const Text('Previous'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Center: Question Grid / Palette trigger icon button [ ▦ ]
              IconButton.filledTonal(
                key: const Key('palette_button'),
                tooltip: 'Question Palette',
                onPressed: () {
                  final answers = <String, Answer>{
                    for (final q in _c.questions)
                      if (_c.answerFor(q.id) != null) q.id: _c.answerFor(q.id)!,
                  };
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AnswerGrid(
                      questionIds: [for (final q in _c.questions) q.id],
                      answers: answers,
                      currentQuestionIndex: index,
                      onQuestionTap: (i) {
                        Navigator.of(context).pop();
                        _c.goTo(i);
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.grid_view_rounded, size: 20),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  visualDensity: VisualDensity.compact,
                ),
              ),

              // Right Button:
              // For questions 0 to N - 2: Render [ Next > ] (ElevatedButton, Primary Theme Color)
              // For the final question (N - 1): Automatically change to [ Review & Submit ➔ ]
              if (!isLast)
                ElevatedButton.icon(
                  key: const Key('next_button'),
                  onPressed: () => _c.goTo(index + 1),
                  label: const Text('Next'),
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  iconAlignment: IconAlignment.end,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                )
              else
                ElevatedButton.icon(
                  key: const Key('review_submit_button'),
                  onPressed: _c.isSubmitting ? null : _confirmSubmit,
                  label: Text(
                    _c.isSubmitting ? 'Submitting…' : 'Review & Submit',
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  iconAlignment: IconAlignment.end,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
            ],
          ),
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
