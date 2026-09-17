import 'dart:async';


import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/answer.dart';
import '../../../core/models/attempt.dart';
import '../../../core/models/question.dart';
import '../../../core/models/result.dart';
import '../../../core/models/test.dart';
import '../data/answer_repository.dart';
import '../data/attempt_repository.dart';
import '../data/question_repository.dart';
import '../data/test_repository.dart';
import '../domain/attempt_lifecycle.dart';
import '../domain/backend_mapping.dart';
import '../domain/deterministic_shuffle.dart';
import '../domain/test_kind.dart';
import 'attempt_launch_store.dart';
import 'disposable_notifier.dart';

/// Owns one attempt on the client: questions (safe RPC), answers, dirty
/// tracking, autosave and submission. The server owns access, the deadline,
/// answer validation and scoring; nothing here computes a score or a
/// deadline.
class AttemptController extends DisposableNotifier {
  AttemptController({
    required this.attemptId,
    required this.testId,
    this.accessCode,
    AttemptRepository? attempts,
    QuestionRepository? questions,
    AnswerRepository? answers,
    TestRepository? tests,
    this.autosaveInterval = const Duration(seconds: 5),
  })  : _attempts = attempts ?? const SupabaseAttemptRepository(),
        _questions = questions ?? const SupabaseQuestionRepository(),
        _answers = answers ?? const SupabaseAnswerRepository(),
        _tests = tests ?? const SupabaseTestRepository();

  final String attemptId;
  final String testId;

  /// Present when the attempt was entered with a code (Challenge with Friends).
  final String? accessCode;
  final Duration autosaveInterval;

  final AttemptRepository _attempts;
  final QuestionRepository _questions;
  final AnswerRepository _answers;
  final TestRepository _tests;

  Attempt? _attempt;
  Test? _test;
  List<Question> _questionsInOrder = const [];
  final Map<String, List<QuestionOption>> _optionsInOrder = {};
  final Map<String, Answer> _answersById = {};
  bool _loading = false;
  bool _dirty = false;
  bool _submitting = false;
  String? _error;
  int _currentIndex = 0;
  Timer? _autosaveTimer;
  bool _answersLoadFailed = false;

  Attempt? get attempt => _attempt;
  Test? get test => _test;
  List<Question> get questions => _questionsInOrder;
  bool get isLoading => _loading;
  bool get isSubmitting => _submitting;
  bool get isDirty => _dirty;
  String? get error => _error;
  int get currentIndex => _currentIndex;

  /// True when the saved-answers read failed on this load (network/RLS).
  /// The attempt still works and new answers are still saved; the screen
  /// tells the user that earlier selections could not be restored.
  bool get answersLoadFailed => _answersLoadFailed;

  TestKind get kind => BackendMapping.fromBackend(_test?.testMode, _test?.settings);

  /// True while the server-side attempt is still in progress.
  bool get isInteractive =>
      _attempt != null && AttemptLifecycle.isInteractive(_attempt!.status);

  /// Server deadline; null only if the server sent none (no client fallback).
  DateTime? get deadlineAt => _attempt?.deadlineAt;

  List<QuestionOption> optionsFor(Question q) =>
      _optionsInOrder[q.id] ?? q.options ?? const [];

  Answer? answerFor(String questionId) => _answersById[questionId];

  int get answeredCount => _answersById.values.where((a) => a.isAnswered).length;
  int get markedCount =>
      _answersById.values.where((a) => a.markedForReview).length;

  // ── loading ──

  /// Reads the user's own attempts for this test (RLS). If the requested
  /// attempt is known and not in_progress, or no in_progress attempt exists
  /// at all, throw before any start RPC. When the read itself fails the
  /// server stays the authority (it refuses to allocate after a terminal
  /// attempt anyway).
  Future<void> _guardColdStart() async {
    List<Attempt> mine;
    try {
      mine = await _attempts.mine(testId);
    } catch (e) {
      AppLogger.warning('Own attempts unavailable on cold start: $e');
      return;
    }
    final requested = mine.where((a) => a.id == attemptId).firstOrNull;
    final hasInProgress = mine.any((a) => a.status == AttemptStatus.inProgress);
    if (requested != null && requested.status != AttemptStatus.inProgress) {
      throw const ValidationError(
          message: 'This attempt has already been submitted. Open its result instead.');
    }
    if (requested == null && !hasInProgress) {
      throw const ValidationError(
          message: 'No attempt is in progress for this test. Start it from the test page.');
    }
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final handoff = AttemptLaunchStore.takeLaunch(attemptId);
      if (handoff != null) {
        _attempt = handoff.started.attempt;
        _test = handoff.test;
        _applyQuestions(handoff.questions);
      } else {
        // Cold start / deep link: only an existing in_progress attempt may be
        // resumed here. Opening a taking URL must never allocate an attempt
        // (RULE 1/2): if the requested attempt is already terminal, stop with
        // a clear message instead of calling the start RPC.
        await _guardColdStart();
        // The server resumes the in-progress attempt (never creates one when
        // a terminal attempt exists — ATTEMPT_ALREADY_COMPLETED otherwise).
        final started = accessCode != null
            ? await _attempts.startByCode(accessCode!)
            : await _attempts.start(testId);
        if (started.attempt.id != attemptId) {
          AppLogger.warning(
              'Server resumed a different attempt (${started.attempt.id}) than requested ($attemptId)');
        }
        _attempt = started.attempt;
        _test = await _tests.getById(started.attempt.testId) ??
            _fallbackTest(started.attempt.testId, started.testTitle);
        _applyQuestions(await _questions.safeQuestions(
          started.attempt.testId,
          accessCode: accessCode,
        ));
      }
      await _loadExistingAnswers();
      if (isInteractive) _startAutosave();
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Attempt load failed: $e', stackTrace: st);
      _error = 'Failed to load the test. Please try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _applyQuestions(List<Question> qs) {
    final shuffle = _test?.shuffleQuestions ?? false;
    final seed = _attempt!.id;
    _questionsInOrder =
        shuffle ? DeterministicShuffle.questions(qs, seed) : List.of(qs);
    _optionsInOrder.clear();
    for (final q in _questionsInOrder) {
      if (!q.hasOptions) continue;
      _optionsInOrder[q.id] = shuffle
          ? DeterministicShuffle.options(q.options!, '${seed}_${q.id}')
          : List.of(q.options!);
    }
  }

  /// Resume: restores saved `selected_option` (server array index) and
  /// `marked_for_review` per question id. Questions without a row stay
  /// unanswered. On failure nothing is fabricated; [answersLoadFailed] lets
  /// the screen say so.
  Future<void> _loadExistingAnswers() async {
    try {
      for (final a in await _answers.forAttempt(_attempt!.id)) {
        // Unsaved local edits made before a retry win over the server copy.
        if (_dirty && _answersById.containsKey(a.questionId)) continue;
        _answersById[a.questionId] = a;
      }
      _answersLoadFailed = false;
    } catch (e) {
      _answersLoadFailed = true;
      AppLogger.warning('Saved answers could not be loaded: $e');
    }
  }

  /// Retry restoring saved answers without restarting the attempt.
  Future<void> reloadSavedAnswers() async {
    if (_attempt == null) return;
    await _loadExistingAnswers();
    notifyListeners();
  }

  static Test _fallbackTest(String id, String? title) => Test(
        id: id,
        createdBy: '',
        title: (title == null || title.trim().isEmpty)
            ? TestKind.challengeWithFriends.label
            : title.trim(),
        status: TestStatus.live,
        testMode: 'live',
      );

  // ── answering ──

  void goTo(int index) {
    if (index < 0 || index >= _questionsInOrder.length) return;
    _currentIndex = index;
    notifyListeners();
  }

  Answer _answerOrNew(String questionId) =>
      _answersById[questionId] ??
      Answer(attemptId: _attempt!.id, questionId: questionId);

  /// Selects an option by its index in the server's `options` array
  /// (`QuestionOption.index`) — the value `rpc_save_answers` validates and
  /// `fn_score_attempt` compares against `correct_option`. Null clears.
  ///
  /// Typed (numeric / short-answer) questions have no storage on the live
  /// backend (no `text_answer` column): BACKEND GAP — nothing is recorded.
  void selectOption(String questionId, int? optionIndex) {
    if (!isInteractive) return;
    _answersById[questionId] =
        _answerOrNew(questionId).withSelection(optionIndex);
    _markDirty();
  }

  void toggleMarkForReview(String questionId) {
    if (!isInteractive) return;
    final current = _answerOrNew(questionId);
    _answersById[questionId] =
        current.withMarkedForReview(!current.markedForReview);
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    notifyListeners();
  }

  // ── autosave / submit ──

  void _startAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(autosaveInterval, (_) => autosaveIfDirty());
  }

  /// Saves when dirty. On failure the dirty flag is restored so the next tick
  /// retries; no infinite loop, no data loss.
  Future<void> autosaveIfDirty() async {
    if (!_dirty || _answersById.isEmpty || _submitting) return;
    _dirty = false;
    try {
      await _answers.save(_attempt!.id, _answersById.values.toList());
    } catch (e) {
      AppLogger.warning('Autosave failed: $e');
      _dirty = true;
    }
  }

  /// Flushes answers and submits. Returns the server result when the RPC
  /// includes it, else null (the result screen reads the row via RLS).
  /// Re-entrancy safe: a second call while submitting throws.
  Future<Result?> submit({required bool timedOut}) async {
    if (_submitting) {
      throw const ValidationError(message: 'Submission already in progress.');
    }
    _submitting = true;
    notifyListeners();
    try {
      _autosaveTimer?.cancel();
      if (_answersById.isNotEmpty) {
        try {
          await _answers.save(_attempt!.id, _answersById.values.toList());
          _dirty = false;
        } catch (e) {
          // On time-out the server still scores what it has; otherwise the
          // user should know their last answers may not have been saved.
          if (!timedOut) rethrow;
          AppLogger.warning('Final save failed before timed-out submit: $e');
        }
      }
      final result = await _attempts.submit(_attempt!.id, timedOut: timedOut);
      if (result != null) AttemptLaunchStore.putResult(result);
      _attempt = Attempt(
        id: _attempt!.id,
        testId: _attempt!.testId,
        userId: _attempt!.userId,
        status: timedOut ? AttemptStatus.autoSubmitted : AttemptStatus.submitted,
        startedAt: _attempt!.startedAt,
        attemptNumber: _attempt!.attemptNumber,
        deadlineAt: _attempt!.deadlineAt,
      );
      return result;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    if (isInteractive && _dirty) {
      // Fire-and-forget: keep the last answers if the user leaves abruptly.
      unawaited(autosaveIfDirty());
    }
    super.dispose();
  }
}
