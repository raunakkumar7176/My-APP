import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_error.dart';
import '../../../test/state/attempt_controller.dart';
import '../../../test/state/attempt_launch_store.dart';
import '../../../test/state/test_detail_controller.dart';
import '../widgets/common/question_palette_grid.dart';
import '../widgets/common/test_card.dart';
import '../widgets/common/timer_pill.dart';

/// Screen 4: Live Exam Hall
/// Distraction-free academic test taking interface with:
/// - Top bar: Question index, TimerPill, autosave badge, palette drawer button
/// - Rich question view with diagrams / math statements
/// - Option cards (A, B, C, D) with haptic feedback
/// - Bottom Dock: Mark for Review, Prev, Save & Next, Submit Test
/// - Submission Audit Dialog with unanswered/marked warnings.
///
/// Backed by the real, server-authoritative [AttemptController] — the
/// timer, autosave, scoring and points are never computed here; this
/// screen only renders the controller's state and forwards intent.
class TestAttemptScreen extends StatefulWidget {
  const TestAttemptScreen({
    this.testId,
    this.testData,
    this.detailController,
    this.attemptController,
    super.key,
  });

  final String? testId;
  final TestCardData? testData;

  /// Injectable for deterministic testing — starts/resumes the attempt.
  /// When null, a real [TestDetailController] is created from [testId].
  final TestDetailController? detailController;

  /// Injectable for deterministic testing — when provided, the screen skips
  /// its own start/resume bootstrap entirely and renders this controller's
  /// state directly (it is assumed already loaded).
  final AttemptController? attemptController;

  @override
  State<TestAttemptScreen> createState() => _TestAttemptScreenState();
}

class _TestAttemptScreenState extends State<TestAttemptScreen> {
  AttemptController? _c;
  bool _ownsController = false;
  bool _bootstrapping = true;
  String? _bootstrapError;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    if (widget.attemptController != null) {
      _c = widget.attemptController;
      _ownsController = false;
      _bootstrapping = false;
      _c!.addListener(_onUpdate);
      _startCountdown();
    } else {
      _bootstrap();
    }
  }

  /// Ticks every second purely to refresh the displayed remaining time —
  /// the deadline itself is server-authoritative (`_c!.deadlineAt`), never
  /// computed here. Auto-submits once the deadline passes, exactly like the
  /// existing `CountdownTimer` widget used by the other (singular) attempt
  /// screen.
  void _startCountdown() {
    final deadline = _c?.deadlineAt;
    if (deadline == null) return; // untimed practice test
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _countdownTimer?.cancel();
        _onSubmitFinalTest(autoSubmitted: true);
      } else {
        setState(() {});
      }
    });
  }

  /// Starts (or resumes) the attempt via the same launch path
  /// `TestDetailScreen`'s "Start Test" button already uses
  /// (`TestDetailController.start()` — start attempt 1 / resume the
  /// in-progress one; never allocates attempt N+1), then hands the result
  /// to a fresh [AttemptController] via the existing [AttemptLaunchStore]
  /// so `load()` doesn't re-fetch what `start()` just returned.
  Future<void> _bootstrap() async {
    final testId = widget.testId;
    if (testId == null || testId.isEmpty) {
      setState(() {
        _bootstrapError = 'No test was specified.';
        _bootstrapping = false;
      });
      return;
    }
    try {
      final detail = widget.detailController ?? TestDetailController(testId: testId);
      await detail.load();
      final launched = await detail.start();
      AttemptLaunchStore.putLaunch(
        started: launched.started,
        questions: launched.questions,
        test: launched.test,
      );
      final c = AttemptController(
        attemptId: launched.started.attempt.id,
        testId: testId,
      );
      await c.load();
      if (!mounted) {
        c.dispose();
        return;
      }
      c.addListener(_onUpdate);
      setState(() {
        _c = c;
        _ownsController = true;
        _bootstrapping = false;
      });
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapError = e is AppError
            ? e.message
            : 'Could not start the test. Please try again.';
        _bootstrapping = false;
      });
    }
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _c?.removeListener(_onUpdate);
    if (_ownsController) _c?.dispose();
    super.dispose();
  }

  void _onSelectOption(String questionId, int optionIndex) {
    HapticFeedback.selectionClick();
    _c!.selectOption(questionId, optionIndex);
  }

  void _toggleMarkForReview(String questionId) {
    HapticFeedback.lightImpact();
    _c!.toggleMarkForReview(questionId);
  }

  /// Palette jump / Prev / Next all force an immediate sync (never wait for
  /// the debounce timer) before moving on, per the step-navigation contract.
  void _goTo(int index) {
    _c!.goTo(index);
    unawaited(_c!.retrySave());
  }

  void _onNextQuestion() {
    final c = _c!;
    if (c.currentIndex < c.questions.length - 1) {
      _goTo(c.currentIndex + 1);
    } else {
      _showSubmissionAuditDialog();
    }
  }

  void _onPrevQuestion() {
    final c = _c!;
    if (c.currentIndex > 0) _goTo(c.currentIndex - 1);
  }

  void _showPaletteModal() {
    final c = _c!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Question Navigation Palette',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              QuestionPaletteGrid(
                totalQuestions: c.questions.length,
                currentIndex: c.currentIndex,
                answeredIndices: {
                  for (var i = 0; i < c.questions.length; i++)
                    if (c.answerFor(c.questions[i].id)?.isAnswered ?? false) i,
                },
                markedIndices: {
                  for (var i = 0; i < c.questions.length; i++)
                    if (c.answerFor(c.questions[i].id)?.markedForReview ?? false) i,
                },
                onQuestionSelected: (selectedIdx) {
                  Navigator.of(ctx).pop();
                  _goTo(selectedIdx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubmissionAuditDialog() {
    final c = _c!;
    final total = c.questions.length;
    final answered = c.answeredCount;
    final unanswered = total - answered;
    final marked = c.markedCount;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Submit Examination?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Review your exam progress before final evaluation:',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _auditRow(
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF10B981),
                    label: 'Answered Questions',
                    value: '$answered / $total',
                  ),
                  const Divider(height: 16),
                  _auditRow(
                    icon: Icons.help_outline_rounded,
                    color: const Color(0xFF64748B),
                    label: 'Unanswered (Skipped)',
                    value: '$unanswered Qs',
                  ),
                  const Divider(height: 16),
                  _auditRow(
                    icon: Icons.star_rounded,
                    color: const Color(0xFF8B5CF6),
                    label: 'Marked for Review',
                    value: '$marked Qs',
                  ),
                ],
              ),
            ),
            if (unanswered > 0 || marked > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Color(0xFFD97706),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You still have pending or marked questions!',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Return to Test'),
          ),
          FilledButton(
            key: const Key('confirm_submit_audit_btn'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _onSubmitFinalTest();
            },
            child: const Text('Confirm & Submit'),
          ),
        ],
      ),
    );
  }

  Widget _auditRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  /// Cancels all debouncers, flushes current answers, and calls
  /// `rpc_submit_and_score_test` via [AttemptController.submitAttempt].
  /// On success: a celebratory snackbar when points were awarded, then
  /// routes to the result screen — or, when the server says the result
  /// isn't published yet (unpublished group test), to the pending screen.
  Future<void> _onSubmitFinalTest({bool autoSubmitted = false}) async {
    final c = _c;
    if (c == null) return;
    try {
      final scorecard = await c.submitAttempt(isAutoSubmit: autoSubmitted);
      if (!mounted) return;
      if (scorecard.pointsAwarded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 +${scorecard.pointsAwarded} points earned!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
      final testId = widget.testId ?? scorecard.testId;
      if (!scorecard.resultPublished) {
        context.pushReplacement('/tests/$testId/submission_pending');
        return;
      }
      final resultData = TestCardData(
        id: testId,
        title: widget.testData?.title ?? '',
        subject: widget.testData?.subject ?? '',
        difficulty: widget.testData?.difficulty ?? TestCardDifficulty.medium,
        mode: widget.testData?.mode ?? '',
        questionCount: scorecard.totalQuestions ?? c.questions.length,
        totalMarks: widget.testData?.totalMarks ?? (scorecard.maxScore ?? 0),
        durationMinutes: widget.testData?.durationMinutes ?? 0,
        status: TestCardStatus.completed,
        scoreObtained: scorecard.score,
        accuracyPercentage: scorecard.accuracy,
        correctCount: scorecard.correctCount,
        incorrectCount: scorecard.incorrectCount,
        unansweredCount: scorecard.unansweredCount,
        marksPerQuestion: scorecard.marksPerQuestion,
        negativeMarks: scorecard.negativeMarks,
        startedAt: c.attempt?.startedAt,
        submittedAt: c.attempt?.submittedAt,
      );
      context.pushReplacement('/tests/$testId/result', extra: resultData);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is AppError ? e.message : 'Could not submit. Please try again.',
          ),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_bootstrapError != null || _c == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFEF4444)),
                const SizedBox(height: 12),
                Text(_bootstrapError ?? 'Could not load the test.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final c = _c!;
    if (c.isLoading && c.questions.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (c.error != null && c.questions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: c.load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    if (c.questions.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('This test has no questions.')),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentQ = c.questions[c.currentIndex];
    final currentOptions = c.optionsFor(currentQ);
    final selectedOpt = c.answerFor(currentQ.id)?.selectedOption;
    final isMarked = c.answerFor(currentQ.id)?.markedForReview ?? false;
    final remaining = c.deadlineAt != null
        ? c.deadlineAt!.difference(DateTime.now())
        : Duration.zero;
    final totalSeconds = c.test?.durationSec ?? 0;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Q ${c.currentIndex + 1} / ${c.questions.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (c.deadlineAt != null)
              Expanded(
                child: Center(
                  child: TimerPill(
                    remainingSeconds: remaining.isNegative ? 0 : remaining.inSeconds,
                    totalSeconds: totalSeconds,
                  ),
                ),
              )
            else
              const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.saveStatus == SaveStatus.saving
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                    : c.saveStatus == SaveStatus.failed
                    ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                    : const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                key: const Key('autosave_status_badge'),
                switch (c.saveStatus) {
                  SaveStatus.saving => 'Saving...',
                  SaveStatus.failed => 'Retrying...',
                  SaveStatus.saved => 'Saved ✓',
                  SaveStatus.idle => 'Saved ✓',
                },
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: c.saveStatus == SaveStatus.saving
                      ? const Color(0xFFD97706)
                      : c.saveStatus == SaveStatus.failed
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF059669),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('open_palette_drawer_btn'),
            icon: const Icon(Icons.grid_view_rounded),
            tooltip: 'Question Palette',
            onPressed: _showPaletteModal,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Marks: ${currentQ.marks}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            if (currentQ.negativeMarks != null)
                              Text(
                                '-${currentQ.negativeMarks} / Wrong',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD97706),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Text(
                            currentQ.question,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(currentOptions.length, (optIdx) {
                          final option = currentOptions[optIdx];
                          final isChosen = selectedOpt == option.index;
                          final optionChar = String.fromCharCode(65 + optIdx);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                key: Key('option_card_${c.currentIndex}_$optIdx'),
                                onTap: () => _onSelectOption(currentQ.id, option.index),
                                borderRadius: BorderRadius.circular(14),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isChosen
                                        ? const Color(0xFF2563EB).withValues(alpha: 0.08)
                                        : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isChosen
                                          ? const Color(0xFF2563EB)
                                          : (isDark
                                                ? const Color(0xFF334155)
                                                : const Color(0xFFE2E8F0)),
                                      width: isChosen ? 2.0 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isChosen
                                              ? const Color(0xFF2563EB)
                                              : (isDark
                                                    ? const Color(0xFF334155)
                                                    : const Color(0xFFF1F5F9)),
                                        ),
                                        child: Text(
                                          optionChar,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isChosen
                                                ? Colors.white
                                                : (isDark
                                                      ? const Color(0xFF94A3B8)
                                                      : const Color(0xFF475569)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          option.text,
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: isChosen
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isChosen ? const Color(0xFF2563EB) : null,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildBottomExamDock(theme, isDark, isMarked, c),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomExamDock(
    ThemeData theme,
    bool isDark,
    bool isMarked,
    AttemptController c,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Row(
            children: [
              OutlinedButton.icon(
                key: const Key('mark_for_review_btn'),
                onPressed: () => _toggleMarkForReview(c.questions[c.currentIndex].id),
                icon: Icon(
                  isMarked ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 16,
                  color: const Color(0xFF8B5CF6),
                ),
                label: Text(
                  isMarked ? 'Marked' : 'Review',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF8B5CF6),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF8B5CF6)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                key: const Key('prev_question_btn'),
                onPressed: c.currentIndex > 0 ? _onPrevQuestion : null,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous Question',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('save_and_next_btn'),
                  onPressed: _onNextQuestion,
                  icon: const Icon(Icons.navigate_next_rounded, size: 18),
                  label: Text(
                    c.currentIndex < c.questions.length - 1
                        ? 'Save & Next ›'
                        : 'Review & Submit',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('submit_test_btn'),
                tooltip: 'Submit Test',
                onPressed: _showSubmissionAuditDialog,
                icon: const Icon(
                  Icons.done_all_rounded,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
