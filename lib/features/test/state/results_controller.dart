import 'package:flutter/foundation.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/answer.dart';
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
import '../domain/backend_mapping.dart';
import '../domain/result_analytics_mapper.dart';
import '../domain/test_kind.dart';
import 'attempt_launch_store.dart';

/// Loads a submitted attempt's server result by attempt id, plus what the
/// result and review screens display: the test, the user's history for
/// that test, safe questions and the user's answers. Nothing is scored or
/// graded on the client; per-question correctness is not available from
/// the backend and is not fabricated.
class ResultsController extends ChangeNotifier {
  ResultsController({
    required this.attemptId,
    ResultRepository? results,
    TestRepository? tests,
    QuestionRepository? questions,
    AnswerRepository? answers,
    AttemptRepository? attempts,
    Future<Map<String, String>> Function()? subjectNames,
  })  : _results = results ?? const SupabaseResultRepository(),
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
  List<SubjectBreakdownItem> _subjects = const [];
  List<TopicBreakdownItem> _topics = const [];
  List<Question> _questionsList = const [];
  Map<String, Answer> _answersById = const {};
  bool _loading = false;
  bool _reviewLoaded = false;
  bool _busy = false;
  String? _error;

  Result? get result => _result;
  Test? get test => _test;
  List<Result> get history => _history;
  List<SubjectBreakdownItem> get subjectBreakdown => _subjects;
  List<TopicBreakdownItem> get topicBreakdown => _topics;
  List<Question> get questions => _questionsList;
  Answer? answerFor(String questionId) => _answersById[questionId];
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  bool get reviewLoaded => _reviewLoaded;
  String? get error => _error;

  TestKind get kind => BackendMapping.fromBackend(_test?.testMode, _test?.settings);

  Result? get previousResult =>
      _result == null ? null : ResultAnalyticsMapper.previous(_history, _result!.id);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _result = AttemptLaunchStore.takeResult(attemptId) ??
          await _results.byAttempt(attemptId);
      if (_result == null) {
        _error = 'Result not available yet. Please try again shortly.';
        return;
      }
      final r = _result!;
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
      ]);
      _test = loads[0] as Test?;
      _history = loads[1] as List<Result>;
      final names = loads[2] as Map<String, String>;
      _subjects = ResultAnalyticsMapper.subjects(r.subjectBreakdown, subjectNames: names);
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
      final qs = await _questions.safeQuestions(r.testId);
      final answers = await _answers.forAttempt(attemptId);
      _questionsList = qs;
      _answersById = {for (final a in answers) a.questionId: a};
      _reviewLoaded = true;
    } on AppError catch (e) {
      _error = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Starts another attempt of the same test (server decides whether repeats
  /// are allowed) and parks the launch for the taking screen.
  Future<({String attemptId, String testId})> repeat() async {
    final r = _result;
    if (r == null) throw const ValidationError(message: 'No result loaded.');
    if (_busy) throw const ValidationError(message: 'Please wait…');
    _busy = true;
    notifyListeners();
    try {
      final started = await _attempts.start(r.testId);
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
