// Render smoke tests: every rebuilt screen draws its main states with
// fake-backed controllers (no Supabase). Guards against layout/null crashes
// before the device pass; not a substitute for it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/screens/question_review_screen.dart';
import 'package:my_praperation/features/test/screens/test_creation_screen.dart';
import 'package:my_praperation/features/test/screens/test_detail_screen.dart';
import 'package:my_praperation/features/test/screens/test_listing_screen.dart';
import 'package:my_praperation/features/test/screens/test_result_screen.dart';
import 'package:my_praperation/features/test/screens/test_taking_screen.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';
import 'package:my_praperation/features/test/state/results_controller.dart';
import 'package:my_praperation/features/test/state/test_creation_controller.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';
import 'package:my_praperation/features/test/state/test_listing_controller.dart';

import 'fakes.dart';

class _NoAnswers implements AnswerRepository {
  @override
  Future<void> save(String attemptId, List<Answer> answers) async {}
  @override
  Future<List<Answer>> forAttempt(String attemptId) async => const [];
}

const _q = Question(
  id: 'q-1', testId: 't-1', ordinal: 1, question: 'What is 2 + 2?',
  options: [QuestionOption(id: 'a', text: '3'), QuestionOption(id: 'b', text: '4')],
  difficulty: DifficultyLevel.easy, marks: 1, status: 'approved',
  questionType: QuestionType.mcqSingle,
);

Test _test({TestStatus status = TestStatus.published, String mode = 'self'}) => Test(
      id: 't-1', createdBy: 'u-1', title: 'Algebra basics', status: status,
      testMode: mode, durationSec: 600, marksPerQuestion: 1,
      settings: const {'test_kind': 'practice'},
    );

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  setUp(AttemptLaunchStore.clear);
  final now = DateTime(2026, 9, 16, 12);

  testWidgets('listing renders tabs, cards, drafts and join-by-code', (tester) async {
    final repo = FakeTestRepository()
      ..rows['t-1'] = _test()
      ..rows['t-2'] = _test(mode: 'live')
      ..rows['d-1'] = _test(status: TestStatus.draft);
    final c = TestListingController(repository: repo, clock: () => now);
    await tester.pumpWidget(_app(TestListingScreen(controller: c)));
    await tester.pumpAndSettle();

    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Challenge with Friends'), findsWidgets);
    expect(find.text('Algebra basics'), findsWidgets);
    expect(find.text('Practice Test'), findsWidgets);
    expect(find.text('Live Test'), findsNothing);

    await tester.tap(find.text('Challenge with Friends').first);
    await tester.pumpAndSettle();
    expect(find.text('Join with code'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('detail renders owner actions for a draft and start for published',
      (tester) async {
    final tests = FakeTestRepository()..rows['t-1'] = _test(status: TestStatus.draft);
    final draft = TestDetailController(
      testId: 't-1', tests: tests, questions: FakeQuestionRepository(),
      attempts: FakeAttemptRepository(), results: FakeResultRepository(),
      currentUserId: () => 'u-1', clock: () => now,
    );
    await tester.pumpWidget(_app(TestDetailScreen(testId: 't-1', controller: draft)));
    await tester.pumpAndSettle();
    expect(find.text('Continue Editing'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Practice Test'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    draft.dispose();

    tests.rows['t-1'] = _test();
    final published = TestDetailController(
      testId: 't-1', tests: tests, questions: FakeQuestionRepository(),
      attempts: FakeAttemptRepository(), results: FakeResultRepository(),
      currentUserId: () => 'u-2', clock: () => now,
    );
    await tester.pumpWidget(_app(TestDetailScreen(testId: 't-1', controller: published)));
    await tester.pumpAndSettle();
    expect(find.text('Start Test'), findsOneWidget);
    expect(find.text('Continue Editing'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    published.dispose();
  });

  testWidgets('creation wizard renders every step and gates Next', (tester) async {
    final c = TestCreationController(
      tests: FakeTestRepository(), questions: FakeQuestionRepository(),
      groups: FakeGroupRepository(), currentUserId: () => 'u-1',
    );
    await tester.pumpWidget(_app(TestCreationScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('Create Test'), findsOneWidget);
    expect(find.text('Test Type'), findsOneWidget);

    // Next is disabled until a title exists.
    final next = find.widgetWithText(FilledButton, 'Next');
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.enterText(find.byType(TextFormField).first, 'My test');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.textContaining('Duration'), findsWidgets); // configuration step

    c.setConfiguration(
      durationSec: 600, marksPerQuestion: 1, negativeMarks: 0, groupId: null,
      startsAt: null, endsAt: null, maxParticipants: null, allowLateJoin: false,
      accessCode: null, joinCode: null,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Add Question'), findsOneWidget); // questions step

    c.setLocalQuestions([
      const QuestionDraft(
        questionText: 'Q1',
        options: [QuestionOptionDraft(text: 'A'), QuestionOptionDraft(text: 'B')],
        correctOptionIndex: 0,
      ),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle(); // syllabus step (R3 services fail silently in tests)
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Review Test'), findsOneWidget);
    expect(find.text('Save Draft'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('taking renders question, timer, kind label and grid', (tester) async {
    final attempt = Attempt(
      id: 'a-1', testId: 't-1', userId: 'u-1', status: AttemptStatus.inProgress,
      startedAt: DateTime.now(), deadlineAt: DateTime.now().add(const Duration(hours: 1)),
    );
    AttemptLaunchStore.putLaunch(
        started: (attempt: attempt, testTitle: null), questions: const [_q], test: _test());
    final c = AttemptController(
      attemptId: 'a-1', testId: 't-1',
      attempts: FakeAttemptRepository(), questions: FakeQuestionRepository(),
      answers: _NoAnswers(), tests: FakeTestRepository(),
      autosaveInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(_app(TestTakingScreen(attemptId: 'a-1', testId: 't-1', controller: c)));
    await tester.pump();
    await tester.pump();

    expect(find.text('What is 2 + 2?'), findsOneWidget);
    expect(find.text('Practice Test'), findsOneWidget);
    expect(find.text('Untimed'), findsNothing, reason: 'server gave a deadline');
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.tap(find.text('4'));
    await tester.pump();
    expect(c.answeredCount, 1);

    await tester.pumpWidget(const SizedBox());
    c.dispose(); // external controller: the screen does not own it
  });

  testWidgets('result and review render from a server result', (tester) async {
    const r = Result(
      id: 'r-1', attemptId: 'a-1', testId: 't-1', userId: 'u-1',
      score: 4, maxScore: 5, percentage: 80, isPassed: true,
      correctCount: 4, wrongCount: 1, unansweredCount: 0, accuracy: 80,
    );
    final results = FakeResultRepository()..byAttemptId['a-1'] = r;
    final tests = FakeTestRepository()..rows['t-1'] = _test();
    final qs = FakeQuestionRepository()..byTest['t-1'] = const [_q];
    ResultsController make() => ResultsController(
          attemptId: 'a-1', results: results, tests: tests, questions: qs,
          answers: _NoAnswers(), attempts: FakeAttemptRepository(),
          subjectNames: () async => {},
        );

    final rc = make();
    await tester.pumpWidget(_app(TestResultScreen(attemptId: 'a-1', controller: rc)));
    await tester.pumpAndSettle();
    expect(find.text('80.0%'), findsWidgets); // percentage + accuracy
    expect(find.text('Passed'), findsOneWidget);
    expect(find.text('Review Answers'), findsOneWidget);
    // No attempt rows in the fake → policy unknown → no Re-attempt offered.
    expect(find.text('Repeat Test'), findsNothing);
    expect(find.text('Re-attempt'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    rc.dispose();

    final rv = make();
    await tester.pumpWidget(_app(QuestionReviewScreen(attemptId: 'a-1', controller: rv)));
    await tester.pumpAndSettle();
    expect(find.text('What is 2 + 2?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    rv.dispose();
  });
}
