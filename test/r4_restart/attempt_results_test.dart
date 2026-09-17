// R4.6 / R4.7 — attempt and results controllers with in-memory repositories.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/domain/deterministic_shuffle.dart';
import 'package:my_praperation/features/test/domain/result_analytics_mapper.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';
import 'package:my_praperation/features/test/state/results_controller.dart';

import 'fakes.dart';

/// Read fails (network / RLS) — the controller must not fabricate answers.
class FailingReadAnswerRepository implements AnswerRepository {
  bool failReads = true;
  List<Answer> rows = const [];
  @override
  Future<void> save(String attemptId, List<Answer> answers) async {}
  @override
  Future<List<Answer>> forAttempt(String attemptId) async {
    if (failReads) throw const DataError(message: 'Failed to load.');
    return rows;
  }
}

class FakeAnswerRepository implements AnswerRepository {
  final List<List<Answer>> saves = [];
  List<Answer> existing = const [];
  bool failNextSave = false;

  @override
  Future<void> save(String attemptId, List<Answer> answers) async {
    if (failNextSave) {
      failNextSave = false;
      throw const DataError(message: 'save failed');
    }
    saves.add(List.of(answers));
  }

  @override
  Future<List<Answer>> forAttempt(String attemptId) async => existing;
}

const _q1 = Question(
  id: 'q-1', testId: 't-1', ordinal: 1, question: 'Q1',
  options: [QuestionOption(id: 'a', text: 'A'), QuestionOption(id: 'b', text: 'B')],
  difficulty: DifficultyLevel.easy, marks: 1, status: 'approved',
  questionType: QuestionType.mcqSingle,
);
const _q2 = Question(
  id: 'q-2', testId: 't-1', ordinal: 2, question: 'Q2', options: null,
  difficulty: DifficultyLevel.easy, marks: 1, status: 'approved',
  questionType: QuestionType.integer,
);

Test _test({bool shuffle = false, Map<String, dynamic>? settings}) => Test(
      id: 't-1', createdBy: 'u-1', title: 'T', status: TestStatus.published,
      testMode: 'self', shuffleQuestions: shuffle, settings: settings,
    );

Attempt _attempt(String id, {AttemptStatus status = AttemptStatus.inProgress}) =>
    Attempt(
      id: id, testId: 't-1', userId: 'u-1', status: status,
      startedAt: DateTime(2026, 9, 16), deadlineAt: DateTime(2026, 9, 16, 1),
    );

void main() {
  setUp(AttemptLaunchStore.clear);

  group('AttemptController', () {
    test('uses the in-memory launch handoff without calling the server', () async {
      final attempts = FakeAttemptRepository();
      final answers = FakeAnswerRepository();
      AttemptLaunchStore.putLaunch(
        started: (attempt: _attempt('a-1'), testTitle: null),
        questions: const [_q1, _q2],
        test: _test(),
      );
      final c = AttemptController(
        attemptId: 'a-1', testId: 't-1',
        attempts: attempts, questions: FakeQuestionRepository(),
        answers: answers, tests: FakeTestRepository(),
        autosaveInterval: const Duration(hours: 1),
      );
      await c.load();

      expect(attempts.calls, isEmpty);
      expect(c.questions.map((q) => q.id), ['q-1', 'q-2']);
      expect(c.isInteractive, isTrue);
      expect(c.deadlineAt, isNotNull);
      c.dispose();
    });

    test('cold start: server resume + safe questions + existing answers', () async {
      final attempts = FakeAttemptRepository()..rows.add(_attempt('a-1')); // in_progress exists
      final qs = FakeQuestionRepository()..byTest['t-1'] = const [_q1, _q2];
      final tests = FakeTestRepository()..rows['t-1'] = _test();
      final answers = FakeAnswerRepository()
        ..existing = const [
          Answer(attemptId: 'a-1', questionId: 'q-1', selectedOption: 1),
        ];
      final c = AttemptController(
        attemptId: 'a-1', testId: 't-1',
        attempts: attempts, questions: qs, answers: answers, tests: tests,
        autosaveInterval: const Duration(hours: 1),
      );
      await c.load();

      expect(attempts.calls, ['mine:t-1', 'start:t-1']); // guard read, then resume
      expect(qs.calls, ['safe:t-1']);
      expect(c.answerFor('q-1')?.selectedOption, 1);
      expect(c.answeredCount, 1);
      c.dispose();
    });

    test('answers: select / typed / clear / review; autosave retries after failure',
        () async {
      final answers = FakeAnswerRepository();
      AttemptLaunchStore.putLaunch(
        started: (attempt: _attempt('a-1'), testTitle: null),
        questions: const [_q1, _q2],
        test: _test(),
      );
      final c = AttemptController(
        attemptId: 'a-1', testId: 't-1',
        attempts: FakeAttemptRepository(), questions: FakeQuestionRepository(),
        answers: answers, tests: FakeTestRepository(),
        autosaveInterval: const Duration(hours: 1),
      );
      await c.load();

      // Selection is by server-array index (live: answers.selected_option int).
      c.selectOption('q-1', 1);
      c.toggleMarkForReview('q-2');
      expect(c.answeredCount, 1);
      expect(c.markedCount, 1);
      expect(c.answerFor('q-1')!.selectedOption, 1);
      expect(c.answerFor('q-1')!.toRpcJson(),
          {'question_id': 'q-1', 'selected_option': 1, 'marked_for_review': false});

      c.selectOption('q-1', null);
      expect(c.answerFor('q-1')!.isAnswered, isFalse);
      expect(c.answerFor('q-2')!.markedForReview, isTrue, reason: 'review flag kept');
      c.selectOption('q-1', 0);

      answers.failNextSave = true;
      await c.autosaveIfDirty();
      expect(answers.saves, isEmpty);
      expect(c.isDirty, isTrue, reason: 'restored for retry');

      await c.autosaveIfDirty();
      expect(answers.saves.length, 1);
      expect(c.isDirty, isFalse);

      await c.autosaveIfDirty();
      expect(answers.saves.length, 1, reason: 'nothing dirty → no call');
      c.dispose();
    });

    test('submit flushes, calls the RPC once, parks the result, blocks re-entry',
        () async {
      final attempts = FakeAttemptRepository();
      final answers = FakeAnswerRepository();
      AttemptLaunchStore.putLaunch(
        started: (attempt: _attempt('a-1'), testTitle: null),
        questions: const [_q1],
        test: _test(),
      );
      final c = AttemptController(
        attemptId: 'a-1', testId: 't-1',
        attempts: attempts, questions: FakeQuestionRepository(),
        answers: answers, tests: FakeTestRepository(),
        autosaveInterval: const Duration(hours: 1),
      );
      await c.load();
      c.selectOption('q-1', 0);

      final first = c.submit(timedOut: false);
      await expectLater(c.submit(timedOut: false), throwsA(isA<ValidationError>()));
      final result = await first;

      expect(answers.saves.length, 1);
      expect(attempts.calls, ['submit:a-1:false']);
      expect(result?.attemptId, 'a-1');
      expect(AttemptLaunchStore.takeResult('a-1')?.id, result?.id);
      expect(c.isInteractive, isFalse);
      c.dispose();
    });

    test('non-interactive attempt from the server is not editable', () async {
      AttemptLaunchStore.putLaunch(
        started: (attempt: _attempt('a-1', status: AttemptStatus.submitted), testTitle: null),
        questions: const [_q1],
        test: _test(),
      );
      final c = AttemptController(
        attemptId: 'a-1', testId: 't-1',
        attempts: FakeAttemptRepository(), questions: FakeQuestionRepository(),
        answers: FakeAnswerRepository(), tests: FakeTestRepository(),
      );
      await c.load();
      expect(c.isInteractive, isFalse);
      c.selectOption('q-1', 0);
      expect(c.answerFor('q-1'), isNull);
      c.dispose();
    });


    test('shuffle is deterministic per attempt and off by default', () async {
      final many = [
        for (var i = 0; i < 12; i++)
          Question(id: 'q$i', testId: 't-1', question: '$i',
              difficulty: DifficultyLevel.easy, marks: 1, status: 'approved'),
      ];
      final a = DeterministicShuffle.questions(many, 'seed-1');
      final b = DeterministicShuffle.questions(many, 'seed-1');
      final other = DeterministicShuffle.questions(many, 'seed-2');
      expect(a.map((q) => q.id), b.map((q) => q.id));
      expect(a.map((q) => q.id), isNot(other.map((q) => q.id)));
      expect(a.map((q) => q.id).toSet(), many.map((q) => q.id).toSet());
      expect(fnv1aHash('abc'), fnv1aHash('abc'));
    });
  });

  group('ResultsController', () {
    Result r(String id, String attemptId, {double? pct, DateTime? at}) => Result(
          id: id, attemptId: attemptId, testId: 't-1', userId: 'u-1',
          score: 3, maxScore: 5, percentage: pct, computedAt: at,
          subjectBreakdown: const {
            's-1': {'attempted': 3, 'correct': 2, 'wrong': 1, 'unanswered': 0},
          },
        );

    test('uses the parked result, then loads test/history/analytics', () async {
      AttemptLaunchStore.putResult(r('r-2', 'a-2', pct: 80, at: DateTime(2026, 9, 16)));
      final results = FakeResultRepository()
        ..mine.addAll([
          r('r-2', 'a-2', pct: 80, at: DateTime(2026, 9, 16)),
          r('r-1', 'a-1', pct: 60, at: DateTime(2026, 9, 15)),
        ]);
      final tests = FakeTestRepository()..rows['t-1'] = _test();
      final c = ResultsController(
        attemptId: 'a-2',
        results: results, tests: tests,
        questions: FakeQuestionRepository(), answers: FakeAnswerRepository(),
        attempts: FakeAttemptRepository(),
        subjectNames: () async => {'s-1': 'Maths'},
      );
      await c.load();

      expect(results.calls, isEmpty, reason: 'parked result used, no byAttempt read');
      expect(c.result?.id, 'r-2');
      expect(c.test?.id, 't-1');
      expect(c.subjectBreakdown.single.subjectName, 'Maths');
      expect(c.previousResult?.id, 'r-1');
      expect(c.history.length, 2);
    });

    test('falls back to the results row and reports absence honestly', () async {
      final results = FakeResultRepository()..byAttemptId['a-9'] = r('r-9', 'a-9');
      final c = ResultsController(
        attemptId: 'a-9',
        results: results, tests: FakeTestRepository(),
        questions: FakeQuestionRepository(), answers: FakeAnswerRepository(),
        attempts: FakeAttemptRepository(), subjectNames: () async => {},
      );
      await c.load();
      expect(c.result?.id, 'r-9');

      final missing = ResultsController(
        attemptId: 'a-none',
        results: FakeResultRepository(), tests: FakeTestRepository(),
        questions: FakeQuestionRepository(), answers: FakeAnswerRepository(),
        attempts: FakeAttemptRepository(), subjectNames: () async => {},
      );
      await missing.load();
      expect(missing.result, isNull);
      expect(missing.error, contains('not available'));
    });

    test('re-attempt (allowed) starts attempt 2 explicitly and parks the launch', () async {
      AttemptLaunchStore.putResult(r('r-1', 'a-1'));
      final attempts = FakeAttemptRepository()
        ..rows.add(_attempt('a-1', status: AttemptStatus.scored))
        ..testSettings['t-1'] = {'allow_reattempt': true, 'max_attempts': 2};
      final qs = FakeQuestionRepository()..byTest['t-1'] = const [_q1];
      final tests = FakeTestRepository()
        ..rows['t-1'] = _test(settings: {'allow_reattempt': true, 'max_attempts': 2});
      final c = ResultsController(
        attemptId: 'a-1',
        results: FakeResultRepository(), tests: tests, questions: qs,
        answers: FakeAnswerRepository(), attempts: attempts,
        subjectNames: () async => {},
      );
      await c.load();
      expect(c.canReattempt, isTrue);
      final launch = await c.reattempt();
      expect(attempts.calls, contains('start:t-1:reattempt'));
      expect(attempts.rows.last.attemptNumber, 2);
      expect(AttemptLaunchStore.takeLaunch(launch.attemptId)?.questions.single.id, 'q-1');
    });

    test('analytics mapper never fabricates data', () {
      expect(ResultAnalyticsMapper.subjects(null), isEmpty);
      expect(ResultAnalyticsMapper.topics({}), isEmpty);
      expect(ResultAnalyticsMapper.previous(const [], 'x'), isNull);
    });
  });
}
