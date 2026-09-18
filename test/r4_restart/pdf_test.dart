// Question paper + result PDFs: built only from authorized, already-loaded
// data; never contain an answer key; fail honestly on empty/missing data.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/result_analytics.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/domain/attempt_history.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/domain/test_pdf.dart';
import 'package:my_praperation/features/test/state/results_controller.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';

import 'fakes.dart';

class _NoAnswers implements AnswerRepository {
  @override
  Future<void> save(String attemptId, List<Answer> answers) async {}
  @override
  Future<List<Answer>> forAttempt(String attemptId) async => const [];
}

const _q = Question(
  id: 'q-1',
  testId: 't-1',
  ordinal: 1,
  question: 'Capital of France?',
  options: [
    QuestionOption(id: 'a', text: 'Paris'),
    QuestionOption(id: 'b', text: 'Rome'),
    QuestionOption(id: 'c', text: 'Berlin'),
    QuestionOption(id: 'd', text: 'Madrid'),
  ],
  difficulty: DifficultyLevel.easy,
  marks: 2,
  status: 'approved',
  questionType: QuestionType.mcqSingle,
  subjectId: 's-1',
);

const _test = Test(
  id: 't-1',
  createdBy: 'u-1',
  title: 'Geo Basics',
  status: TestStatus.published,
  testMode: 'self',
  durationSec: 1800,
  marksPerQuestion: 2,
  negativeMarks: 0.5,
  instructions: 'No maps allowed.',
);

bool _isPdf(List<int> bytes) => String.fromCharCodes(bytes.take(5)) == '%PDF-';

void main() {
  group('TestPdf.questionPaper', () {
    test('produces a PDF and refuses an empty question list', () async {
      final bytes = await TestPdf.questionPaper(
        test: _test,
        kind: TestKind.self,
        questions: const [_q],
        subjectNames: const {'s-1': 'Geography'},
      );
      expect(_isPdf(bytes), isTrue);
      expect(bytes.length, greaterThan(1000));
      await expectLater(
        TestPdf.questionPaper(
          test: _test,
          kind: TestKind.self,
          questions: const [],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('the safe question model cannot carry an answer key', () {
      // Question has no correct_option field; QuestionOption has no
      // correctness flag — nothing exists for the PDF to print.
      expect(_q.toJson().containsKey('correct_option'), isFalse);
      expect(const QuestionOption(id: 'a', text: 'x').toJson().keys, [
        'id',
        'text',
      ]);
    });
  });

  group('TestPdf.resultReport', () {
    test('produces a PDF from stored fields only', () async {
      final r = Result(
        id: 'a-2',
        attemptId: 'a-2',
        testId: 't-1',
        userId: 'u-1',
        score: 8,
        maxScore: 10,
        percentage: 80,
        accuracy: 88.9,
        correctCount: 4,
        wrongCount: 1,
        unansweredCount: 0,
        computedAt: DateTime(2026, 9, 17, 12),
      );
      final bytes = await TestPdf.resultReport(
        studentName: 'Raunak',
        test: _test,
        kind: TestKind.practice,
        result: r,
        attemptNumber: 2,
        submittedAt: DateTime(2026, 9, 17, 12),
        subjects: const [
          SubjectBreakdownItem(
            subjectId: 's-1',
            subjectName: 'Geography',
            attempted: 5,
            correct: 4,
            wrong: 1,
            unanswered: 0,
          ),
        ],
        topics: const [],
        history: [
          AttemptHistoryEntry(result: r),
          AttemptHistoryEntry(result: r),
        ],
      );
      expect(_isPdf(bytes), isTrue);
    });
  });

  group('controllers', () {
    test(
      'detail: question paper uses the safe RPC and fails honestly when empty',
      () async {
        final tests = FakeTestRepository()..rows['t-1'] = _test;
        final qs = FakeQuestionRepository();
        final c = TestDetailController(
          testId: 't-1',
          tests: tests,
          questions: qs,
          attempts: FakeAttemptRepository(),
          results: FakeResultRepository(),
          currentUserId: () => 'u-1',
        );
        await c.load();
        await expectLater(
          c.buildQuestionPaperPdf(),
          throwsA(
            predicate(
              (e) => e is AppError && e.message.contains('no questions'),
            ),
          ),
        );
        qs.byTest['t-1'] = const [_q];
        final bytes = await c.buildQuestionPaperPdf();
        expect(_isPdf(bytes), isTrue);
        expect(
          qs.calls.where((x) => x == 'safe:t-1').length,
          greaterThanOrEqualTo(1),
        );
      },
    );

    test('results: report from the loaded result; no result → error', () async {
      const r = Result(
        id: 'a-1',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
        score: 1,
        maxScore: 2,
      );
      final attempts = FakeAttemptRepository()
        ..rows.add(
          Attempt(
            id: 'a-1',
            testId: 't-1',
            userId: 'u-1',
            status: AttemptStatus.scored,
            startedAt: DateTime(2026, 9, 17, 9),
            submittedAt: DateTime(2026, 9, 17, 9, 20),
            attemptNumber: 1,
          ),
        );
      final c = ResultsController(
        attemptId: 'a-1',
        results: FakeResultRepository()
          ..byAttemptId['a-1'] = r
          ..mine.add(r),
        tests: FakeTestRepository()..rows['t-1'] = _test,
        questions: FakeQuestionRepository()..byTest['t-1'] = const [_q],
        answers: _NoAnswers(),
        attempts: attempts,
        subjectNames: () async => {},
      );
      await expectLater(
        c.buildResultPdf(studentName: 'S'),
        throwsA(isA<ValidationError>()),
      );
      await c.load();
      expect(_isPdf(await c.buildResultPdf(studentName: 'S')), isTrue);
      await expectLater(
        c.buildQuestionPaperPdf(),
        throwsA(isA<DataError>()),
      ); // review not loaded
      await c.loadReview();
      expect(_isPdf(await c.buildQuestionPaperPdf()), isTrue);
    });
  });
}
