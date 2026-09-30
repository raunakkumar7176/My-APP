import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/screens/test_taking_screen.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';

import '../../r4_restart/fakes.dart';

class _FakeAnswerRepository implements AnswerRepository {
  final Map<String, List<Answer>> stored = {};

  @override
  Future<void> save(String attemptId, List<Answer> answers) async {
    stored[attemptId] = List.of(answers);
  }

  @override
  Future<List<Answer>> forAttempt(String attemptId) async =>
      stored[attemptId] ?? const [];
}

const _q1 = Question(
  id: 'q-1',
  testId: 't-1',
  ordinal: 1,
  question: 'What is 2 + 2?',
  options: [
    QuestionOption(id: 'a', text: '3', index: 0),
    QuestionOption(id: 'b', text: '4', index: 1),
    QuestionOption(id: 'c', text: '5', index: 2),
    QuestionOption(id: 'd', text: '6', index: 3),
  ],
  difficulty: DifficultyLevel.easy,
  marks: 1,
  status: 'approved',
  questionType: QuestionType.mcqSingle,
);

const _q2 = Question(
  id: 'q-2',
  testId: 't-1',
  ordinal: 2,
  question: 'What is the capital of France?',
  options: [
    QuestionOption(id: 'a', text: 'London', index: 0),
    QuestionOption(id: 'b', text: 'Berlin', index: 1),
    QuestionOption(id: 'c', text: 'Paris', index: 2),
    QuestionOption(id: 'd', text: 'Madrid', index: 3),
  ],
  difficulty: DifficultyLevel.medium,
  marks: 2,
  status: 'approved',
  questionType: QuestionType.mcqSingle,
);

const _q3 = Question(
  id: 'q-3',
  testId: 't-1',
  ordinal: 3,
  question: 'What is H2O?',
  options: [
    QuestionOption(id: 'a', text: 'Water', index: 0),
    QuestionOption(id: 'b', text: 'Oxygen', index: 1),
  ],
  difficulty: DifficultyLevel.easy,
  marks: 1,
  status: 'approved',
  questionType: QuestionType.mcqSingle,
);

Test _test() => const Test(
  id: 't-1',
  createdBy: 'u-1',
  title: 'General Knowledge Exam',
  status: TestStatus.published,
  testMode: 'self',
  durationSec: 600,
  marksPerQuestion: 1,
  settings: {'test_kind': 'practice'},
);

Attempt _attempt() => Attempt(
  id: 'a-1',
  testId: 't-1',
  userId: 'u-1',
  status: AttemptStatus.inProgress,
  startedAt: DateTime.now(),
  deadlineAt: DateTime.now().add(const Duration(minutes: 10)),
);

AttemptController _controller(AnswerRepository answers) {
  AttemptLaunchStore.putLaunch(
    started: (attempt: _attempt(), testTitle: null),
    questions: const [_q1, _q2, _q3],
    test: _test(),
  );
  return AttemptController(
    attemptId: 'a-1',
    testId: 't-1',
    attempts: FakeAttemptRepository(),
    questions: FakeQuestionRepository(),
    answers: answers,
    tests: FakeTestRepository(),
    autosaveInterval: const Duration(hours: 1),
  );
}

void main() {
  setUp(() {
    AttemptLaunchStore.clear();
  });

  Future<AttemptController> pumpScreen(
    WidgetTester tester, {
    AnswerRepository? repo,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final answerRepo = repo ?? _FakeAnswerRepository();
    final c = _controller(answerRepo);
    await tester.pumpWidget(
      MaterialApp(
        home: TestTakingScreen(attemptId: 'a-1', testId: 't-1', controller: c),
      ),
    );
    await tester.pump();
    await tester.pump();
    return c;
  }

  group('TestTakingScreen Layout & Action Placements', () {
    testWidgets(
      '1. Top App Bar: Close leading, Centered Timer, Top Right Submit',
      (tester) async {
        final c = await pumpScreen(tester);

        // Leading: Close button
        expect(find.byIcon(Icons.close), findsOneWidget);

        // Centered Title: Timer capsule with clock icon
        expect(find.byIcon(Icons.access_time_rounded), findsOneWidget);
        expect(find.textContaining(':'), findsWidgets); // Timer MM:SS

        // Actions: Submit button in AppBar
        expect(find.byKey(const Key('submit_button')), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Submit'), findsOneWidget);

        // Tapping Submit opens confirmation sheet with stats
        await tester.tap(find.byKey(const Key('submit_button')));
        await tester.pumpAndSettle();

        expect(find.text('Submit Test?'), findsOneWidget);
        expect(find.text('Total questions'), findsOneWidget);
        expect(find.text('3'), findsWidgets);
        expect(find.text('Answered'), findsOneWidget);
        expect(find.text('Unanswered'), findsOneWidget);
        expect(find.text('Continue Test'), findsOneWidget);

        await tester.tap(find.text('Continue Test'));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets(
      '2. Upper Progress Strip: Index chip, realtime counters, bookmark, progress bar',
      (tester) async {
        final c = await pumpScreen(tester);

        // Left: Q 1 of 3
        expect(find.text('Q 1 of 3'), findsOneWidget);

        // Middle: Realtime counters (0 answered, 3 left initially)
        expect(find.text('● 0 Answered'), findsOneWidget);
        expect(find.text('○ 3 Left'), findsOneWidget);

        // Right: Bookmark toggle
        expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

        // Thin linear progress bar
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        // Selecting an option updates Answered and Left counts instantly
        await tester.tap(find.text('4'));
        await tester.pump();

        expect(find.text('● 1 Answered'), findsOneWidget);
        expect(find.text('○ 2 Left'), findsOneWidget);
        expect(c.answeredCount, 1);

        // Tapping bookmark toggles to bookmarked icon
        await tester.tap(find.byIcon(Icons.bookmark_border));
        await tester.pump();
        expect(find.byIcon(Icons.bookmark), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets(
      '3. Bottom Bar: Previous disabled on Q1, Next advances to Q2, Review & Submit on last Q',
      (tester) async {
        final c = await pumpScreen(tester);

        // Question 1:
        // Previous button is disabled (onPressed is null)
        final prevBtn = tester.widget<OutlinedButton>(
          find.byKey(const Key('previous_button')),
        );
        expect(prevBtn.onPressed, isNull);

        // Center: Question Palette button
        expect(find.byKey(const Key('palette_button')), findsOneWidget);

        // Right: "Next" button (elevated)
        expect(find.byKey(const Key('next_button')), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Next'), findsOneWidget);

        // No premature Submit button in bottom bar
        expect(find.byKey(const Key('review_submit_button')), findsNothing);

        // Clicking Next advances to Question 2
        await tester.tap(find.byKey(const Key('next_button')));
        await tester.pumpAndSettle();

        expect(c.currentIndex, 1);
        expect(find.text('Q 2 of 3'), findsOneWidget);
        expect(find.text('What is the capital of France?'), findsOneWidget);

        // On Question 2, Previous button is enabled
        final prevBtnQ2 = tester.widget<OutlinedButton>(
          find.byKey(const Key('previous_button')),
        );
        expect(prevBtnQ2.onPressed, isNotNull);

        // Advance to final Question (Q3)
        await tester.tap(find.byKey(const Key('next_button')));
        await tester.pumpAndSettle();

        expect(c.currentIndex, 2);
        expect(find.text('Q 3 of 3'), findsOneWidget);
        expect(find.text('What is H2O?'), findsOneWidget);

        // On final question, Next is replaced by "Review & Submit"
        expect(find.byKey(const Key('next_button')), findsNothing);
        expect(find.byKey(const Key('review_submit_button')), findsOneWidget);
        expect(find.text('Review & Submit'), findsOneWidget);

        // Clicking Review & Submit opens confirmation sheet
        await tester.tap(find.byKey(const Key('review_submit_button')));
        await tester.pumpAndSettle();

        expect(find.text('Submit Test?'), findsOneWidget);
        await tester.tap(find.text('Continue Test'));
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('4. Palette Modal Sheet shows question states', (tester) async {
      final c = await pumpScreen(tester);

      // Tap Palette button
      await tester.tap(find.byKey(const Key('palette_button')));
      await tester.pumpAndSettle();

      // Palette displays "Questions" header and legend items
      expect(find.text('Questions'), findsOneWidget);
      expect(find.text('Answered'), findsOneWidget);
      expect(find.text('Unanswered'), findsOneWidget);
      expect(find.text('Marked for review'), findsOneWidget);

      // Tapping question 2 tile jumps to question 2
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();

      expect(c.currentIndex, 1);
      expect(find.text('Q 2 of 3'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
