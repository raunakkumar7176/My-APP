import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/theme/app_colors.dart';
import '../../core/errors/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/answer.dart';
import '../../core/models/attempt.dart';
import '../../core/models/question.dart';
import '../../core/models/test.dart';
import '../../core/models/test_kind.dart';
import '../../core/models/self_reflection.dart';
import '../../core/services/answer_service.dart';
import '../../core/services/attempt_service.dart';
import '../../core/services/question_service.dart';
import '../../core/services/result_service.dart';
import 'widgets/answer_grid.dart';
import 'widgets/countdown_timer.dart';
import 'widgets/question_card.dart';
import 'widgets/self_reflection_dialog.dart';

/// Deterministic FNV-1a hash, truncated to 32-bit for use as a seed.
/// Produces identical output across runs, platforms, and Dart versions.
/// Uses 32-bit operations to avoid JavaScript integer overflow.
/// Algorithm: https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function
@visibleForTesting
int fnv1aHash(String input) {
  const int fnvOffsetBasis = 0x811c9dc5;
  const int fnvPrime = 0x01000193;
  var hash = fnvOffsetBasis;
  final bytes = utf8.encode(input);
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
}

class TestTakingScreen extends StatefulWidget {
  const TestTakingScreen({
    required this.attempt,
    required this.questions,
    required this.test,
    super.key,
  });

  final Attempt attempt;
  final List<Question> questions;
  final Test test;

  @override
  State<TestTakingScreen> createState() => _TestTakingScreenState();

  /// Deterministic question shuffle.
  /// Same attempt ID always produces the same question order.
  @visibleForTesting
  static List<Question> shuffleQuestions(List<Question> questions, String seed) {
    final rng = _deterministicRng(seed);
    final shuffled = List<Question>.from(questions)..shuffle(rng);
    return shuffled;
  }

  /// Deterministic option shuffle.
  /// Same attempt ID + question ID always produces the same option order.
  @visibleForTesting
  static List<QuestionOption> shuffleOptions(
      List<QuestionOption> options, String seed) {
    final rng = _deterministicRng(seed);
    final shuffled = List<QuestionOption>.from(options)..shuffle(rng);
    return shuffled;
  }

  static Random _deterministicRng(String seed) {
    return Random(fnv1aHash(seed));
  }
}

class _TestTakingScreenState extends State<TestTakingScreen> {
  late final PageController _pageController;
  Timer? _autosaveTimer;
  late final List<Question> _shuffledQuestions;
  late final Map<String, List<QuestionOption>> _shuffledOptions;

  final Map<String, Answer> _answers = {};
  bool _isDirty = false;
  bool _isSubmitting = false;
  int _currentIndex = 0;
  bool _initialized = false;
  late final bool _isInteractive;

  // ─── Test-kind awareness (R4.11b foundation) ───────────────────
  // Server semantics are untouched: kind only changes client presentation.

  TestKind get _kind => widget.test.testKind;

  /// True only when the server itself started a Practice attempt without a
  /// deadline. No start RPC in the repo does this yet, so this stays false
  /// until the backend gains an untimed practice mode.
  bool get _isUntimedPractice =>
      widget.attempt.deadlineAt == null &&
      widget.test.testMode == 'self' &&
      _kind == TestKind.practice;

  /// Practice / Quick skip the pre-submit self-reflection step.
  bool get _isLightweightFlow =>
      widget.test.testMode == 'self' &&
      (_kind == TestKind.practice || _kind == TestKind.quick);

  Widget _buildTitle() {
    final kindLabel = widget.test.testMode == 'self' && _kind != TestKind.self
        ? _kind.label
        : null;
    if (kindLabel == null) return Text(widget.test.title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.test.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(kindLabel, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // FIX 3: Determine interactivity from attempt status
    _isInteractive = widget.attempt.isInProgress;

    _shuffledQuestions = widget.test.shuffleQuestions
        ? TestTakingScreen.shuffleQuestions(
            widget.questions, widget.attempt.id)
        : List<Question>.from(widget.questions);

    _shuffledOptions = {};
    for (final q in _shuffledQuestions) {
      if (q.hasOptions) {
        _shuffledOptions[q.id] = widget.test.shuffleQuestions
            ? TestTakingScreen.shuffleOptions(
                q.options!, '${widget.attempt.id}_${q.id}')
            : List<QuestionOption>.from(q.options!);
      }
    }

    if (_isInteractive) {
      _loadExistingAnswers();
      _autosaveTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _autosaveIfDirty());
    } else {
      // Non-interactive: load answers for display, no autosave
      _loadExistingAnswers();
    }
  }

  Future<void> _loadExistingAnswers() async {
    try {
      final existing =
          await AnswerService.getAnswersForAttempt(widget.attempt.id);
      for (final a in existing) {
        _answers[a.questionId] = a;
      }
    } catch (e) {
      AppLogger.warning('Could not load existing answers: $e');
    }
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _pageController.dispose();
    if (_isInteractive) _autosaveIfDirty();
    super.dispose();
  }

  Answer _getOrCreateAnswer(String questionId) {
    return _answers[questionId] ??
        Answer(
          attemptId: widget.attempt.id,
          questionId: questionId,
        );
  }

  // FIX 3: Only allow answer changes when interactive
  void _onOptionSelected(String questionId, String? optionId) {
    if (!_isInteractive) return;
    final current = _getOrCreateAnswer(questionId);
    final updated = current.copyWith(
      selectedOptionId: optionId,
      isAnswered: optionId != null,
    );
    setState(() {
      _answers[questionId] = updated;
      _isDirty = true;
    });
  }

  /// Typed answers (numeric / short answer). The text is stored in
  /// `text_answer` and — until the live scoring contract is verified — also
  /// mirrored into `selected_option_id`, which is where the client wrote it
  /// before, so server-side handling is unchanged. Clearing the field resets
  /// the answer (Answer.copyWith cannot null a field).
  void _onTextAnswerChanged(String questionId, String? text) {
    if (!_isInteractive) return;
    final current = _getOrCreateAnswer(questionId);
    // Whitespace-only is "no answer" everywhere (grid, submit dialog, server).
    final value = (text == null || text.trim().isEmpty) ? null : text;
    final updated = Answer(
      attemptId: current.attemptId,
      questionId: current.questionId,
      selectedOptionId: value,
      textAnswer: value,
      isMarkedForReview: current.isMarkedForReview,
      isAnswered: value != null,
    );
    setState(() {
      _answers[questionId] = updated;
      _isDirty = true;
    });
  }

  // FIX 3: Only allow review mark when interactive
  void _onMarkReview(String questionId) {
    if (!_isInteractive) return;
    final current = _getOrCreateAnswer(questionId);
    setState(() {
      _answers[questionId] =
          current.copyWith(isMarkedForReview: !current.isMarkedForReview);
      _isDirty = true;
    });
  }

  void _goToQuestion(int index) {
    if (index >= 0 && index < _shuffledQuestions.length) {
      _pageController.jumpToPage(index);
    }
  }

  // FIX 7: Autosave safety — dirty state retained on failure, no infinite retry
  Future<void> _autosaveIfDirty() async {
    if (!_isDirty || _answers.isEmpty || _isSubmitting) return;
    _isDirty = false; // optimistically clear; re-set on failure
    try {
      await AnswerService.saveAnswers(
        attemptId: widget.attempt.id,
        answers: _answers.values.toList(),
      );
    } catch (e) {
      AppLogger.warning('Autosave failed: $e');
      _isDirty = true; // retain dirty state for next cycle
    }
  }

  Future<void> _flushAndSubmit({required bool timedOut, SelfReflection? selfReflection}) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      if (_answers.isNotEmpty) {
        await AnswerService.saveAnswers(
          attemptId: widget.attempt.id,
          answers: _answers.values.toList(),
        );
      }
      final result = await AttemptService.submitAttempt(
        attemptId: widget.attempt.id,
        timedOut: timedOut,
      );
      if (mounted) {
        context.go('/test-result', extra: {
          'result': result,
          'test': widget.test,
          'questions': _shuffledQuestions,
          'answers': Map<String, Answer>.from(_answers),
          'selfReflection': selfReflection,
        });
      }
    } on AppError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submission failed. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _onTimeUp() async {
    await _flushAndSubmit(timedOut: true);
  }

  Future<bool> _onWillPop() async {
    if (_isSubmitting) return false;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Test?'),
        content: const Text(
          'If you leave now, your answers will be saved and submitted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Submit & Leave'),
          ),
        ],
      ),
    );
    if (shouldLeave == true) {
      await _flushAndSubmit(timedOut: false, selfReflection: null);
      return false;
    }
    return false;
  }

  void _showSubmitDialog() {
    final answered = _answers.values
        .where((a) => a.isAnswered || a.selectedOptionId != null)
        .length;
    final marked = _answers.values.where((a) => a.isMarkedForReview).length;
    final total = _shuffledQuestions.length;
    final unanswered = total - answered;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Test?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow('Total questions', '$total'),
            _summaryRow('Answered', '$answered', color: AppColors.success),
            if (unanswered > 0)
              _summaryRow('Unanswered', '$unanswered',
                  color: AppColors.error),
            if (marked > 0)
              _summaryRow('Marked for review', '$marked',
                  color: AppColors.warning),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continue Test'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // Self-reflection before submission; Practice / Quick use the
              // lightweight flow and skip it (it is not persisted anyway).
              final reflection = _isLightweightFlow
                  ? null
                  : await SelfReflectionDialog.show(context);
              _flushAndSubmit(
                timedOut: false,
                selfReflection: reflection, // null if skipped
              );
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // FIX 3: Route to result flow for submitted attempts
  Future<void> _routeToResultIfAvailable() async {
    try {
      final result =
          await ResultService.getResultByAttemptId(widget.attempt.id);
      if (result != null && mounted) {
        // Fetch questions and answers for the review screen
        final questions =
            await QuestionService.getQuestionsSafe(testId: widget.test.id);
        final existing =
            await AnswerService.getAnswersForAttempt(widget.attempt.id);
        final answersMap = {for (final a in existing) a.questionId: a};
        if (!mounted) return;
        context.go('/test-result', extra: {
          'result': result,
          'test': widget.test,
          'questions': questions,
          'answers': answersMap,
          'selfReflection': null,
        });
        return;
      }
    } catch (_) {
      // Result not available yet, show safe state
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // FIX 3: Non-interactive attempt guard
    if (!_isInteractive) {
      return _buildReadOnlyScreen();
    }

    // FIX 2: Null deadlineAt — no fake timer, show error state.
    // Extension point (R4.11b): a Practice attempt that the *server* started
    // without a deadline is untimed. Today every start RPC in the repo sets
    // deadline_at, so this branch is dormant until the backend supports it;
    // the client never fabricates either a deadline or its absence.
    if (widget.attempt.deadlineAt == null && !_isUntimedPractice) {
      return _buildNoDeadlineScreen();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _buildTitle(),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onWillPop,
          ),
          actions: [
            if (_isUntimedPractice)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: Text('Untimed')),
              )
            else
              CountdownTimer(
                deadlineAt: widget.attempt.deadlineAt!,
                onTimeUp: _onTimeUp,
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _shuffledQuestions.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, index) {
                  final q = _shuffledQuestions[index];
                  return QuestionCard(
                    question: q,
                    shuffledOptions: _shuffledOptions[q.id] ?? q.options ?? [],
                    answer: _answers[q.id],
                    questionNumber: index + 1,
                    totalQuestions: _shuffledQuestions.length,
                    onOptionSelected: (optId) =>
                        _onOptionSelected(q.id, optId),
                    onTextAnswerChanged: (text) =>
                        _onTextAnswerChanged(q.id, text),
                    onMarkReview: () => _onMarkReview(q.id),
                    interactive: _isInteractive,
                  );
                },
              ),
            ),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  // FIX 3: Read-only screen for submitted/auto_submitted/scored attempts
  Widget _buildReadOnlyScreen() {
    String statusText;
    switch (widget.attempt.status) {
      case AttemptStatus.submitted:
        statusText = 'Test Submitted';
        break;
      case AttemptStatus.autoSubmitted:
        statusText = 'Test Auto-Submitted (Time Expired)';
        break;
      case AttemptStatus.scored:
        statusText = 'Test Scored';
        break;
      case AttemptStatus.unknown:
        statusText = 'Test Status Unknown';
        break;
      default:
        statusText = 'Test Not Active';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.test.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/tests'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 64,
                color: AppColors.primaryLight,
              ),
              const SizedBox(height: 16),
              Text(
                statusText,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your answers cannot be modified.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _routeToResultIfAvailable,
                child: const Text('View Result'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/tests'),
                child: const Text('Back to Tests'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // FIX 2: No-fallback screen when deadlineAt is null
  Widget _buildNoDeadlineScreen() {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.test.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/tests'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.warning,
              ),
              const SizedBox(height: 16),
              Text(
                'Timer Not Available',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'The server did not provide a deadline for this attempt. '
                'Please retry or contact support.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/tests'),
                child: const Text('Back to Tests'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: _showAnswerGrid,
              tooltip: 'Question grid',
            ),
            const SizedBox(width: 4),
            Text(
              '${_currentIndex + 1}/${_shuffledQuestions.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            if (_currentIndex > 0)
              TextButton.icon(
                onPressed: () => _goToQuestion(_currentIndex - 1),
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Prev'),
              ),
            if (_currentIndex < _shuffledQuestions.length - 1)
              TextButton.icon(
                onPressed: () => _goToQuestion(_currentIndex + 1),
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('Next'),
                iconAlignment: IconAlignment.end,
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isSubmitting ? null : _showSubmitDialog,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAnswerGrid() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AnswerGrid(
        questionIds: _shuffledQuestions.map((q) => q.id).toList(),
        answers: _answers,
        currentQuestionIndex: _currentIndex,
        onQuestionTap: (index) {
          Navigator.of(context).pop();
          _goToQuestion(index);
        },
      ),
    );
  }
}
