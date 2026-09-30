import 'dart:async';
import 'dart:typed_data';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/answer.dart';
import '../../../core/models/attempt.dart';
import '../../../core/models/question.dart';
import '../../../core/models/result.dart';
import '../../../core/models/result_analytics.dart';
import '../../../core/models/test.dart';
import '../../../core/services/subject_service.dart';
import '../data/answer_repository.dart';
import '../data/attempt_repository.dart';
import '../data/question_repository.dart';
import '../data/result_repository.dart';
import '../data/test_repository.dart';
import '../domain/attempt_history.dart';
import '../domain/attempt_policy.dart';
import '../domain/backend_mapping.dart';
import '../domain/result_analytics_mapper.dart';
import '../domain/test_kind.dart';
import '../domain/test_pdf.dart';
import '../../../core/services/pdf/exam_report_pdf_generator.dart';
import '../../../core/services/profile_service.dart';
import 'attempt_launch_store.dart';
import 'disposable_notifier.dart';

/// Loads a submitted attempt's server result by attempt id, plus what the
/// result and review screens display: the test, the user's history for
/// that test, safe questions and the user's answers. Nothing is scored or
/// graded on the client; per-question correctness is not available from
/// the backend and is not fabricated.
class ResultsController extends DisposableNotifier {
  ResultsController({
    required this.attemptId,
    ResultRepository? results,
    TestRepository? tests,
    QuestionRepository? questions,
    AnswerRepository? answers,
    AttemptRepository? attempts,
    Future<Map<String, String>> Function()? subjectNames,
  }) : _results = results ?? const SupabaseResultRepository(),
       _tests = tests ?? const SupabaseTestRepository(),
       _questions = questions ?? const SupabaseQuestionRepository(),
       _answers = answers ?? const SupabaseAnswerRepository(),
       _attempts = attempts ?? const SupabaseAttemptRepository(),
       _subjectNames = subjectNames ?? _loadSubjectNames;

  final String attemptId;
  final ResultRepository _results;
  final TestRepository _tests;
  final QuestionRepository _questions;
  final AnswerRepository _answers;
  final AttemptRepository _attempts;
  final Future<Map<String, String>> Function() _subjectNames;

  Result? _result;
  Test? _test;
  List<Result> _history = const [];
  List<Attempt> _myAttempts = const [];
  List<SubjectBreakdownItem> _subjects = const [];
  List<TopicBreakdownItem> _topics = const [];
  List<Question> _questionsList = const [];
  Map<String, Answer> _answersById = const {};
  Map<String, int> _answerKey = const {};
  bool _loading = false;
  bool _reviewLoaded = false;
  bool _answersLoadFailed = false;
  bool _busy = false;
  String? _error;

  Result? get result => _result;
  Test? get test => _test;
  List<Result> get history => _history;
  List<SubjectBreakdownItem> get subjectBreakdown => _subjects;
  List<TopicBreakdownItem> get topicBreakdown => _topics;
  List<Question> get questions => _questionsList;
  Answer? answerFor(String questionId) => _answersById[questionId];

  /// The real correct option for [questionId], from `rpc_get_my_answer_key`
  /// (0079) — null until it loads, or if it couldn't (never fabricated).
  int? correctOptionFor(String questionId) => _answerKey[questionId];
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  bool get reviewLoaded => _reviewLoaded;

  /// True when the user's saved answers could not be loaded for the review
  /// (network/RLS); questions and explanations are still shown, selections
  /// are not fabricated.
  bool get answersLoadFailed => _answersLoadFailed;
  String? get error => _error;

  TestKind get kind =>
      BackendMapping.fromBackend(_test?.testMode, _test?.settings);

  Result? get previousResult => _result == null
      ? null
      : ResultAnalyticsMapper.previous(_history, _result!.id);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _result =
          AttemptLaunchStore.takeResult(attemptId) ??
          await _results.byAttempt(attemptId);
      if (_result == null) {
        _error = 'Result not available yet. Please try again shortly.';
        return;
      }
      final r = _result!;
      // Points for test completion are now awarded server-side, atomically,
      // inside rpc_submit_and_score_test (+15 'test_completion') — calling
      // GamificationService.awardTestCompleted here (as this screen used to)
      // would double-award on top of that every time the result is viewed.
      final loads = await Future.wait<Object?>([
        _tests.getById(r.testId).catchError((Object e) {
          AppLogger.warning('Result test row unavailable: $e');
          return null;
        }),
        _results.mineForTest(r.testId).catchError((Object e) {
          AppLogger.warning('History unavailable: $e');
          return <Result>[];
        }),
        _subjectNames().catchError((Object e) => <String, String>{}),
        _attempts.mine(r.testId).catchError((Object e) {
          AppLogger.warning('Own attempts unavailable: ');
          return <Attempt>[];
        }),
      ]);
      _test = loads[0] as Test?;
      _history = loads[1] as List<Result>;
      _myAttempts = loads[3] as List<Attempt>;
      final names = loads[2] as Map<String, String>;
      _subjects = ResultAnalyticsMapper.subjects(
        r.subjectBreakdown,
        subjectNames: names,
      );
      _topics = ResultAnalyticsMapper.topics(r.topicBreakdown);
    } on AppError catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Safe questions + the user's answers for the review screen (lazy).
  Future<void> loadReview() async {
    final r = _result;
    if (r == null || _reviewLoaded) return;
    _busy = true;
    notifyListeners();
    try {
      _questionsList = await _questions.safeQuestions(r.testId);
      try {
        final answers = await _answers.forAttempt(attemptId);
        _answersById = {for (final a in answers) a.questionId: a};
        _answersLoadFailed = false;
      } on AppError catch (e) {
        AppLogger.warning(
          'Review: saved answers could not be loaded: ${e.message}',
        );
        _answersLoadFailed = true;
        _answersById = const {};
      }
      try {
        _answerKey = await _results.myAnswerKey(attemptId);
      } catch (e) {
        // Best-effort: an empty key just means every question falls back to
        // the plain "Answered"/"Unanswered" status, never a fabricated verdict.
        AppLogger.warning('Review: answer key unavailable: $e');
        _answerKey = const {};
      }
      _reviewLoaded = true;
    } on AppError catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── attempt history / policy (stored rows only) ──

  List<AttemptHistoryEntry> get attemptHistory =>
      AttemptHistory.build(_history, _myAttempts);
  AttemptHistoryEntry? get latestEntry => AttemptHistory.latest(attemptHistory);
  AttemptHistoryEntry? get bestEntry => AttemptHistory.best(attemptHistory);
  AttemptHistoryEntry? get currentEntry {
    final id = _result?.attemptId;
    if (id == null) return null;
    for (final e in attemptHistory) {
      if (e.result.attemptId == id) return e;
    }
    return null;
  }

  AttemptHistoryEntry? get previousEntry => _result == null
      ? null
      : AttemptHistory.previousOf(attemptHistory, _result!.attemptId);

  /// Current vs immediately previous attempt; null without a previous one.
  ResultDelta? get deltaFromPrevious {
    final c = currentEntry;
    final p = previousEntry;
    return (c == null || p == null) ? null : ResultDelta.between(c, p);
  }

  AttemptPolicyState? get attemptState => _test == null
      ? null
      : AttemptPolicyState(
          settings: AttemptSettings.fromSettings(_test!.settings),
          attempts: _myAttempts,
        );

  /// Re-attempt is offered only when the policy allows it. When the own
  /// attempts read failed the button is hidden rather than guessed.
  bool get canReattempt => attemptState?.canReattempt ?? false;

  /// Result report from the stored rows already loaded on this screen.
  /// [studentName] is taken from the profile/email by the caller.
  Future<Uint8List> buildResultPdf({required String studentName}) async {
    final r = _result;
    if (r == null) throw const ValidationError(message: 'No result loaded.');
    try {
      return await TestPdf.resultReport(
        studentName: studentName,
        test: _test,
        kind: kind,
        result: r,
        attemptNumber: currentEntry?.attemptNumber,
        submittedAt: currentEntry?.completedAt ?? r.computedAt,
        subjects: _subjects,
        topics: _topics,
        deltaFromPrevious: deltaFromPrevious,
        previousAttemptNumber: previousEntry?.attemptNumber,
        history: attemptHistory,
      );
    } catch (e, st) {
      AppLogger.error('Result PDF failed: $e', stackTrace: st);
      throw const DataError(message: 'Could not generate the result PDF.');
    }
  }

  /// The attempt row behind [r]: the history join first, then the own-attempts
  /// list read independently on load (the two reads fail independently).
  Attempt? _attemptFor(Result r) {
    final joined = currentEntry?.attempt;
    if (joined != null) return joined;
    for (final a in _myAttempts) {
      if (a.id == r.attemptId) return a;
    }
    return null;
  }

  /// Generates the consolidated 2-column detailed report card PDF with
  /// Devanagari font support, candidate responses, scorecard, and watermark.
  Future<Uint8List> buildDetailedReportPdf({
    required String studentName,
    String? studentCode,
  }) async {
    final r = _result;
    if (r == null) throw const ValidationError(message: 'No result loaded.');
    final t = _test;

    if (!_reviewLoaded) {
      await loadReview();
    }
    if (_answersLoadFailed) {
      // Never generate a report whose header says "67 correct" while every
      // question body says "Not Attempted" — that contradiction is worse
      // than a clear error. Let the caller retry instead.
      throw const DataError(
        message:
            'Could not load your saved answers for this report. Please try again.',
      );
    }

    // Best-effort: rpc_get_my_answer_key (0079) only returns rows for the
    // caller's own already-submitted attempt, so this is empty (never an
    // error) if the RPC isn't deployed yet or the attempt somehow isn't
    // submitted — the report still generates, just without verdicts.
    Map<String, int> answerKey = const {};
    try {
      answerKey = await _results.myAnswerKey(attemptId);
    } catch (e) {
      AppLogger.warning('buildDetailedReportPdf: answer key unavailable: $e');
    }

    final questionItems = <ExamReportQuestionResponse>[];
    for (var i = 0; i < _questionsList.length; i++) {
      final q = _questionsList[i];
      final a = _answersById[q.id];
      final optList = q.options?.map((o) => o.text).toList() ?? <String>[];

      String? userOptionStr;
      if (a?.selectedOption != null && a!.selectedOption! >= 0) {
        // One source of truth for the label the PDF parses back.
        userOptionStr = ExamReportPdfGenerator.optionLetter(a.selectedOption!);
      }

      final correctIndex = answerKey[q.id];
      final correctOptionStr = correctIndex != null
          ? ExamReportPdfGenerator.optionLetter(correctIndex)
          : null;
      final isCorrect = (correctIndex != null && a?.selectedOption != null)
          ? a!.selectedOption == correctIndex
          : null;

      questionItems.add(
        ExamReportQuestionResponse(
          index: i,
          questionText: q.question,
          options: optList,
          userOption: userOptionStr,
          // Only populated once the attempt is actually submitted (0079's
          // RPC withholds it otherwise) — null here still renders a neutral
          // answer line rather than inventing a verdict.
          correctOption: correctOptionStr,
          isCorrect: isCorrect,
          explanation: q.explanation,
        ),
      );
    }

    var attempt = _attemptFor(r);
    if (attempt == null) {
      // The own-attempts read can fail on load (RLS/network), which leaves
      // the history join empty. Retry once so the Performance Matrix gets a
      // real duration instead of an empty "Time Taken" cell.
      try {
        final mine = await _attempts.mine(r.testId);
        for (final a in mine) {
          if (a.id == r.attemptId) {
            attempt = a;
            _myAttempts = mine;
            break;
          }
        }
      } catch (e) {
        AppLogger.warning('Attempt re-read for report timing failed: $e');
      }
    }
    final start = attempt?.startedAt;
    final end =
        attempt?.submittedAt ?? currentEntry?.completedAt ?? r.computedAt;
    final timeTaken = (start != null && end != null && !end.isBefore(start))
        ? end.difference(start)
        : null;

    final totalQ =
        r.totalQuestions ??
        (_questionsList.isNotEmpty ? _questionsList.length : 0);
    final correct = r.correctCount ?? 0;
    final wrong = r.wrongCount ?? 0;
    final unans = r.unansweredCount ?? (totalQ - correct - wrong);
    final attempted = correct + wrong;
    final totalMarks = r.score ?? r.marksObtained ?? 0.0;
    final maxMarks = r.maxScore ?? (r.totalMarks?.toDouble());
    final pct =
        r.percentage ??
        (maxMarks != null && maxMarks > 0
            ? (totalMarks / maxMarks * 100)
            : 0.0);
    final acc =
        r.accuracy ?? (attempted > 0 ? (correct / attempted * 100) : 0.0);

    final scorecard = ExamReportScorecard(
      totalQuestions: totalQ,
      attempted: attempted,
      correct: correct,
      incorrect: wrong,
      skipped: unans,
      totalMarks: totalMarks,
      maxMarks: maxMarks,
      percentage: pct,
      accuracy: acc,
      timeTaken: timeTaken,
    );

    final candidate = ExamReportCandidateInfo(
      fullName: studentName,
      studentCode:
          studentCode ??
          ProfileService.currentProfile?.studentCode ??
          'MP-STUDENT',
    );

    final metadata = ExamReportTestMetadata(
      testTitle: t?.title ?? 'Official Assessment',
      attemptDate: currentEntry?.completedAt ?? r.computedAt ?? DateTime.now(),
      duration: t?.durationSec != null
          ? Duration(seconds: t!.durationSec!)
          : null,
      timeTaken: timeTaken,
    );

    try {
      return await ExamReportPdfGenerator.generate(
        candidateInfo: candidate,
        testMetadata: metadata,
        testResult: scorecard,
        testQuestionsWithResponses: questionItems,
      );
    } catch (e, st) {
      AppLogger.error('Detailed report PDF failed: $e', stackTrace: st);
      throw const DataError(message: 'Could not generate the report card.');
    }
  }

  /// Question paper for the student after submission: the review already
  /// loaded the safe questions (no answer key); nothing new is fetched.
  Future<Uint8List> buildQuestionPaperPdf() async {
    final t = _test;
    if (t == null) throw const DataError(message: 'Test not loaded.');
    if (_questionsList.isEmpty) {
      throw const DataError(message: 'Questions are not loaded yet.');
    }
    try {
      return await TestPdf.questionPaper(
        test: t,
        kind: kind,
        questions: _questionsList,
      );
    } catch (e, st) {
      AppLogger.error('Question paper PDF failed: $e', stackTrace: st);
      throw const DataError(message: 'Could not generate the question paper.');
    }
  }

  /// OMR-style answer sheet for the student's own marked bubbles, from the
  /// already-loaded review questions/answers — no new fetch, no correctness
  /// judgement (the backend never exposes `correct_option`).
  Future<Uint8List> buildAnswerSheetPdf({String? studentName}) async {
    final t = _test;
    if (t == null) throw const DataError(message: 'Test not loaded.');
    if (_questionsList.isEmpty) {
      throw const DataError(message: 'Questions are not loaded yet.');
    }
    try {
      final attempt = currentEntry?.attempt;
      return await TestPdf.answerSheet(
        test: t,
        kind: kind,
        questions: _questionsList,
        answers: _answersById,
        result: _result,
        startedAt: attempt?.startedAt,
        submittedAt: attempt?.submittedAt ?? currentEntry?.completedAt,
        studentName: studentName,
      );
    } catch (e, st) {
      AppLogger.error('Answer sheet PDF failed: $e', stackTrace: st);
      throw const DataError(message: 'Could not generate the answer sheet.');
    }
  }

  /// Explicit re-attempt (the only client path that asks for attempt N+1;
  /// the server enforces the limit) and parks the launch for taking.
  Future<({String attemptId, String testId})> reattempt() async {
    final r = _result;
    if (r == null) throw const ValidationError(message: 'No result loaded.');
    if (_busy) throw const ValidationError(message: 'Please wait…');
    if (!canReattempt) {
      throw const ValidationError(
        message: 'Re-attempt is not available for this test.',
      );
    }
    _busy = true;
    notifyListeners();
    try {
      final started = await _attempts.start(r.testId, reattempt: true);
      final qs = await _questions.safeQuestions(r.testId);
      final test = _test ?? await _tests.getById(r.testId);
      if (test == null) {
        throw const DataError(message: 'Test not found.');
      }
      AttemptLaunchStore.putLaunch(started: started, questions: qs, test: test);
      return (attemptId: started.attempt.id, testId: r.testId);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static Future<Map<String, String>> _loadSubjectNames() async {
    final subjects = await SubjectService.loadSubjects();
    return {for (final s in subjects) s.id: s.name};
  }
}
