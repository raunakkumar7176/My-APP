import 'dart:async';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/answer.dart';
import '../../../core/models/attempt.dart';
import '../../../core/models/question.dart';
import '../../../core/models/result.dart';
import '../../../core/models/submit_scorecard.dart';
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

/// Client-side view of the last autosave. Purely informational: the server
/// row is the truth; this only tells the user whether the latest local
/// answers have reached it.
enum SaveStatus { idle, saving, saved, failed }

/// One question's palette state, derived from its [Answer] — never stored
/// separately, so it can't drift from the actual answer data.
enum QuestionPaletteStatus { unanswered, answered, markedForReview, answeredAndMarked }

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
    this.autosaveInterval = const Duration(milliseconds: 2500),
  }) : _attempts = attempts ?? const SupabaseAttemptRepository(),
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

  // ── save status (informational; the server row is the truth) ──
  SaveStatus _saveStatus = SaveStatus.idle;
  DateTime? _lastSavedAt;
  String? _saveError;
  int _saveFailures = 0;

  SaveStatus get saveStatus => _saveStatus;
  DateTime? get lastSavedAt => _lastSavedAt;

  /// User-facing message of the last failed save (mapped by the repository).
  String? get saveError => _saveError;

  /// Consecutive failed saves since the last success.
  int get saveFailures => _saveFailures;

  /// True when local answers may not be on the server yet: something changed
  /// since the last successful save, a save is in flight, or the last save
  /// failed. The screen uses this before Leave / Submit.
  bool get hasUnsavedAnswers =>
      _answersById.isNotEmpty &&
      (_dirty ||
          _saveStatus == SaveStatus.saving ||
          _saveStatus == SaveStatus.failed);

  /// Forces a save now regardless of the timer. Returns true on success (or
  /// when there was nothing to save).
  Future<bool> retrySave() async {
    if (_answersById.isEmpty || _submitting) return true;
    _dirty = true;
    await autosaveIfDirty();
    return _saveStatus != SaveStatus.failed;
  }

  TestKind get kind =>
      BackendMapping.fromBackend(_test?.testMode, _test?.settings);

  /// True while the server-side attempt is still in progress.
  bool get isInteractive =>
      _attempt != null && AttemptLifecycle.isInteractive(_attempt!.status);

  /// Server deadline; null only if the server sent none (no client fallback).
  DateTime? get deadlineAt => _attempt?.deadlineAt;

  // ── integrity events (anti-cheat) ──
  //
  // The server (rpc_record_integrity_event) owns the count, the threshold
  // and any resulting auto-submit; this controller only reports occurrences
  // and reflects back whatever the server decided. It never computes or
  // trusts a local count.

  bool _recordingIntegrity = false;
  bool _integrityAutoSubmitted = false;

  /// Server-held count as of the last successful report (or attempt load).
  int? get integrityEventCount => _attempt?.integrityEventCount;
  int? get autoSubmitThreshold => _attempt?.autoSubmitThreshold;

  /// True once the server has told this controller it auto-submitted the
  /// attempt because the integrity threshold was reached. The screen should
  /// stop accepting input and show the limit-reached message when this
  /// flips true (mirrors how a normal submit() completes).
  bool get integrityAutoSubmitted => _integrityAutoSubmitted;

  /// Reports one client-observed integrity event. Fire-and-forget from the
  /// caller's perspective (never blocks the answering UI): failures are
  /// logged and swallowed, since a lost integrity report must not prevent
  /// the user from continuing to answer — the server's own deadline/
  /// idempotency checks remain the real security boundary regardless of
  /// whether any given event report arrives. In-flight reports are
  /// single-flighted (a report already in progress is skipped, not queued)
  /// so a burst of lifecycle callbacks cannot fan out into a burst of RPCs.
  void recordIntegrityEvent(String eventType, {Map<String, dynamic>? details}) {
    if (_recordingIntegrity || !isInteractive || _attempt == null) return;
    _recordingIntegrity = true;
    unawaited(_recordIntegrityEvent(eventType, details));
  }

  Future<void> _recordIntegrityEvent(
    String eventType,
    Map<String, dynamic>? details,
  ) async {
    try {
      final outcome = await _attempts.recordIntegrityEvent(
        attemptId: attemptId,
        testId: testId,
        eventType: eventType,
        details: details,
      );
      if (isDisposed || _attempt == null) return;
      _attempt = Attempt(
        id: _attempt!.id,
        testId: _attempt!.testId,
        userId: _attempt!.userId,
        status: outcome.autoSubmitted
            ? AttemptStatus.autoSubmitted
            : _attempt!.status,
        startedAt: _attempt!.startedAt,
        attemptNumber: _attempt!.attemptNumber,
        deadlineAt: _attempt!.deadlineAt,
        submittedAt: _attempt!.submittedAt,
        integrityEventCount: outcome.integrityEventCount,
        autoSubmitThreshold: outcome.autoSubmitThreshold,
      );
      if (outcome.autoSubmitted) {
        _autosaveTimer?.cancel();
        _integrityAutoSubmitted = true;
      }
    } catch (e) {
      AppLogger.warning('recordIntegrityEvent($eventType) failed: $e');
    } finally {
      _recordingIntegrity = false;
      if (!isDisposed) notifyListeners();
    }
  }

  List<QuestionOption> optionsFor(Question q) =>
      _optionsInOrder[q.id] ?? q.options ?? const [];

  Answer? answerFor(String questionId) => _answersById[questionId];

  int get answeredCount =>
      _answersById.values.where((a) => a.isAnswered).length;
  int get markedCount =>
      _answersById.values.where((a) => a.markedForReview).length;

  /// This question's palette state, derived on demand from [answerFor] —
  /// there is no separate stored map, so the palette can never disagree
  /// with the actual answer.
  QuestionPaletteStatus paletteStatusFor(String questionId) {
    final a = _answersById[questionId];
    final answered = a?.isAnswered ?? false;
    final marked = a?.markedForReview ?? false;
    if (answered && marked) return QuestionPaletteStatus.answeredAndMarked;
    if (answered) return QuestionPaletteStatus.answered;
    if (marked) return QuestionPaletteStatus.markedForReview;
    return QuestionPaletteStatus.unanswered;
  }

  /// The whole question palette as a `questionId -> status` map, in test
  /// order — a computed view, not additional state.
  Map<String, QuestionPaletteStatus> get questionPalette => {
        for (final q in _questionsInOrder) q.id: paletteStatusFor(q.id),
      };

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
        message:
            'This attempt has already been submitted. Open its result instead.',
      );
    }
    if (requested == null && !hasInProgress) {
      throw const ValidationError(
        message: 'No attempt is in progress for this test. Start it from the test page.',
      );
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
            'Server resumed a different attempt (${started.attempt.id}) than requested ($attemptId)',
          );
        }
        _attempt = started.attempt;
        _test =
            await _tests.getById(started.attempt.testId) ??
            _fallbackTest(started.attempt.testId, started.testTitle);
        _applyQuestions(
          await _questions.safeQuestions(
            started.attempt.testId,
            accessCode: accessCode,
          ),
        );
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
    _questionsInOrder = shuffle
        ? DeterministicShuffle.questions(qs, seed)
        : List.of(qs);
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
    _answersById[questionId] = _answerOrNew(questionId)
        .withSelection(optionIndex);
    _markDirty();
  }

  void toggleMarkForReview(String questionId) {
    if (!isInteractive) return;
    final current = _answerOrNew(questionId);
    _answersById[questionId] = current.withMarkedForReview(
      !current.markedForReview,
    );
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
    if (_saveStatus == SaveStatus.saving) return; // one in flight at a time
    _dirty = false;
    _saveStatus = SaveStatus.saving;
    notifyListeners();
    try {
      await _answers.save(_attempt!.id, _answersById.values.toList());
      _saveStatus = SaveStatus.saved;
      _lastSavedAt = DateTime.now();
      _saveError = null;
      _saveFailures = 0;
    } catch (e) {
      AppLogger.warning('Autosave failed: $e');
      _dirty = true;
      _saveStatus = SaveStatus.failed;
      _saveFailures++;
      _saveError = e is AppError
          ? e.message
          : 'Could not save your answers. We will keep retrying.';
    }
    notifyListeners();
  }

  /// Alias of [submit] under the requested name — `isAutoSubmit` is exactly
  /// [submit]'s existing `timedOut` flag; this delegates to the same,
  /// already-tested submission path rather than a second implementation.
  Future<SubmitScorecard> submitAttempt({bool isAutoSubmit = false}) =>
      submit(timedOut: isAutoSubmit);

  // ── last submission outcome (set by [submit], read by the screen for the
  // celebratory-points snackbar and the publish-aware result navigation) ──
  int? _lastPointsAwarded;
  bool? _lastResultPublished;

  /// `points_awarded` from the last successful [submit] call — 0 on an
  /// idempotent repeat submit or a hit daily cap, null before any submit.
  int? get lastPointsAwarded => _lastPointsAwarded;

  /// `result_published` from the last successful [submit] call — always
  /// true for a self/practice test; only ever false for an unpublished
  /// group test. Null before any submit.
  bool? get lastResultPublished => _lastResultPublished;

  /// Flushes answers and submits via `rpc_submit_and_score_test`. Scoring,
  /// the +15 `test_completion` points award, and the publish gate are all
  /// server-side — this never re-awards points itself (that used to happen
  /// here via GamificationService.awardTestCompleted, which is now removed
  /// to avoid double-awarding on top of the RPC's own award).
  /// Re-entrancy safe: a second call while submitting throws.
  Future<SubmitScorecard> submit({required bool timedOut}) async {
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
          _saveStatus = SaveStatus.saved;
          _lastSavedAt = DateTime.now();
          _saveError = null;
          _saveFailures = 0;
        } catch (e) {
          // On time-out the server still scores what it has; otherwise the
          // user should know their last answers may not have been saved.
          _dirty = true;
          _saveStatus = SaveStatus.failed;
          _saveFailures++;
          if (e is AppError) _saveError = e.message;
          if (!timedOut) {
            _startAutosave(); // keep retrying while the user stays
            rethrow;
          }
          AppLogger.warning('Final save failed before timed-out submit: $e');
        }
      }
      final scorecard = await _attempts.submit(_attempt!.id, timedOut: timedOut);
      _lastPointsAwarded = scorecard.pointsAwarded;
      _lastResultPublished = scorecard.resultPublished;
      // Park a Result for the existing result-screen handoff (same
      // AttemptLaunchStore/ResultsController path as before) — userId comes
      // from the attempt itself since the scorecard never carries it (the
      // RPC always operates on the caller's own attempt).
      AttemptLaunchStore.putResult(Result(
        id: scorecard.attemptId,
        attemptId: scorecard.attemptId,
        testId: scorecard.testId,
        userId: _attempt!.userId,
        correctCount: scorecard.correctCount,
        wrongCount: scorecard.incorrectCount,
        unansweredCount: scorecard.unansweredCount,
        totalQuestions: scorecard.totalQuestions,
        score: scorecard.score,
        maxScore: scorecard.maxScore,
        percentage: scorecard.percentage,
        accuracy: scorecard.accuracy,
      ));
      _attempt = Attempt(
        id: _attempt!.id,
        testId: _attempt!.testId,
        userId: _attempt!.userId,
        status: timedOut
            ? AttemptStatus.autoSubmitted
            : AttemptStatus.submitted,
        startedAt: _attempt!.startedAt,
        attemptNumber: _attempt!.attemptNumber,
        deadlineAt: _attempt!.deadlineAt,
        submittedAt: _attempt!.submittedAt ?? DateTime.now(),
      );
      return scorecard;
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
