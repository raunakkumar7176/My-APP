import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/study/data/study_repository.dart';
import 'package:my_praperation/features/study/domain/study_question.dart';
import 'package:my_praperation/features/study/presentation/controllers/topic_practice_controller.dart';
import 'package:my_praperation/features/study/presentation/screens/topic_practice_screen.dart';

class FakeTopicPracticeStudyRepository implements StudyRepository {
  FakeTopicPracticeStudyRepository({
    this.questions = const [],
    this.shouldThrow = false,
  });

  final List<StudyQuestion> questions;
  final bool shouldThrow;
  bool fetchTopicQuestionsCalled = false;
  bool fetchChapterQuestionsCalled = false;

  @override
  Future<List<StudyQuestion>> fetchTopicQuestions({
    required String topicId,
    String? chapterId,
    required String languageCode,
    int limit = 30,
    int offset = 0,
  }) async {
    fetchTopicQuestionsCalled = true;
    if (shouldThrow) throw Exception('Simulated network error');
    return questions;
  }

  @override
  Future<List<StudyQuestion>> fetchChapterQuestions({
    required String chapterId,
    required String languageCode,
    int limit = 20,
    int offset = 0,
  }) async {
    fetchChapterQuestionsCalled = true;
    if (shouldThrow) throw Exception('Simulated network error');
    return questions;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const sampleQuestions = [
    StudyQuestion(
      id: 'q-01',
      chapterId: 'chap-01',
      topicId: 'top-01',
      question: 'What is the smallest prime number?',
      options: ['0', '1', '2', '3'],
      correctOption: 2, // '2'
      explanation: '2 is the only even prime and the smallest prime number.',
      difficulty: 'easy',
    ),
    StudyQuestion(
      id: 'q-02',
      chapterId: 'chap-01',
      topicId: 'top-01',
      question: 'Which of the following numbers is divisible by 3?',
      options: ['10', '14', '21', '25'],
      correctOption: 2, // '21'
      explanation:
          'The sum of digits of 21 is 2 + 1 = 3, which is divisible by 3.',
      difficulty: 'medium',
    ),
  ];

  Widget buildTestScreen({
    TopicPracticeController? controller,
    FakeTopicPracticeStudyRepository? repo,
    List<StudyQuestion>? questions,
    bool shouldThrow = false,
  }) {
    final effectiveRepo =
        repo ??
        FakeTopicPracticeStudyRepository(
          questions: questions ?? sampleQuestions,
          shouldThrow: shouldThrow,
        );

    final effectiveController =
        controller ??
        TopicPracticeController(
          topicId: 'top-01',
          chapterId: 'chap-01',
          topicTitle: 'Prime Numbers',
          chapterTitle: 'Number Systems',
          subjectTitle: 'Mathematics',
          subjectId: 'sub-01',
          repository: effectiveRepo,
        );

    return MaterialApp(
      home: TopicPracticeScreen(
        topicId: 'top-01',
        chapterId: 'chap-01',
        topicTitle: 'Prime Numbers',
        chapterTitle: 'Number Systems',
        subjectTitle: 'Mathematics',
        subjectId: 'sub-01',
        controller: effectiveController,
      ),
    );
  }

  void setSurfaceSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('TopicPracticeScreen UI & Interaction Tests', () {
    testWidgets(
      'renders compact header, breadcrumbs, topic practice badge and counter',
      (tester) async {
        setSurfaceSize(tester);
        await tester.pumpWidget(buildTestScreen());
        await tester.pumpAndSettle();

        // Verify breadcrumbs
        expect(
          find.text('Mathematics • Number Systems • Prime Numbers'),
          findsOneWidget,
        );

        // Verify Topic Practice badge
        expect(find.text('Topic Practice'), findsOneWidget);

        // Verify Question counter
        expect(find.text('Question 1/2'), findsOneWidget);

        // Verify Language toggle
        expect(find.text('EN'), findsOneWidget);
      },
    );

    testWidgets(
      'renders question card, difficulty pill and all 4 options with letters',
      (tester) async {
        await tester.pumpWidget(buildTestScreen());
        await tester.pumpAndSettle();

        // Verify question badge and difficulty
        expect(find.text('Q1'), findsOneWidget);
        expect(find.text('Easy'), findsOneWidget);

        // Verify question text
        expect(find.text('What is the smallest prime number?'), findsOneWidget);

        // Verify 4 options with badges A, B, C, D
        expect(find.text('A'), findsOneWidget);
        expect(find.text('B'), findsOneWidget);
        expect(find.text('C'), findsOneWidget);
        expect(find.text('D'), findsOneWidget);

        expect(find.text('0'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
      },
    );

    testWidgets('check answer is disabled until an option is selected', (
      tester,
    ) async {
      final controller = TopicPracticeController(
        topicId: 'top-01',
        chapterId: 'chap-01',
        repository: FakeTopicPracticeStudyRepository(
          questions: sampleQuestions,
        ),
      );

      await tester.pumpWidget(buildTestScreen(controller: controller));
      await tester.pumpAndSettle();

      // Check Answer button is present
      expect(find.text('Check Answer'), findsOneWidget);
      expect(controller.selectedOptionIndex, isNull);

      // Tap Check Answer without selection -> does nothing
      await tester.tap(find.text('Check Answer'));
      await tester.pump();
      expect(controller.isAnswerChecked, isFalse);

      // Tap option C ('2')
      await tester.tap(find.text('2'));
      await tester.pump();
      expect(controller.selectedOptionIndex, equals(2));

      // Now tap Check Answer
      await tester.tap(find.text('Check Answer'));
      await tester.pumpAndSettle();

      expect(controller.isAnswerChecked, isTrue);
      expect(controller.isCurrentAnswerCorrect, isTrue);
      expect(controller.correctCount, equals(1));
    });

    testWidgets(
      'reveals correct feedback, explanation callout, and updates metrics',
      (tester) async {
        final controller = TopicPracticeController(
          topicId: 'top-01',
          chapterId: 'chap-01',
          repository: FakeTopicPracticeStudyRepository(
            questions: sampleQuestions,
          ),
        );

        await tester.pumpWidget(buildTestScreen(controller: controller));
        await tester.pumpAndSettle();

        // Select correct option '2' (index 2)
        await tester.tap(find.text('2'));
        await tester.pump();

        await tester.tap(find.text('Check Answer'));
        await tester.pumpAndSettle();

        // Check success callout
        expect(find.text('✓ Correct! Well done.'), findsOneWidget);
        expect(find.text('EXPLANATION & CONCEPT'), findsOneWidget);
        expect(
          find.text('2 is the only even prime and the smallest prime number.'),
          findsOneWidget,
        );

        // Check Next Question button
        expect(find.text('Next Question →'), findsOneWidget);

        // Check metrics strip
        expect(find.text('✓ 1 Correct'), findsOneWidget);
        expect(find.text('✗ 0 Incorrect'), findsOneWidget);
      },
    );

    testWidgets(
      'reveals incorrect choice and highlights correct answer on mistake',
      (tester) async {
        final controller = TopicPracticeController(
          topicId: 'top-01',
          chapterId: 'chap-01',
          repository: FakeTopicPracticeStudyRepository(
            questions: sampleQuestions,
          ),
        );

        await tester.pumpWidget(buildTestScreen(controller: controller));
        await tester.pumpAndSettle();

        // Select wrong option '1' (index 1)
        await tester.tap(find.text('1'));
        await tester.pump();

        await tester.tap(find.text('Check Answer'));
        await tester.pumpAndSettle();

        // Check review callout
        expect(find.text('Needs Review • Learn from this'), findsOneWidget);
        expect(find.text('✗ Your Choice'), findsOneWidget);
        expect(find.text('✓ Correct'), findsOneWidget);

        // Verify metrics
        expect(find.text('✓ 0 Correct'), findsOneWidget);
        expect(find.text('✗ 1 Incorrect'), findsOneWidget);
        expect(controller.mistakeCount, equals(1));
      },
    );

    testWidgets(
      'advances to question 2 and completes session on final question',
      (tester) async {
        setSurfaceSize(tester);
        final controller = TopicPracticeController(
          topicId: 'top-01',
          chapterId: 'chap-01',
          repository: FakeTopicPracticeStudyRepository(
            questions: sampleQuestions,
          ),
        );

        await tester.pumpWidget(buildTestScreen(controller: controller));
        await tester.pumpAndSettle();

        // Question 1: Answer correct
        await tester.tap(find.text('2'));
        await tester.pump();
        await tester.tap(find.text('Check Answer'));
        await tester.pumpAndSettle();

        // Advance to Question 2
        await tester.tap(find.text('Next Question →'));
        await tester.pumpAndSettle();

        // Verify on Question 2
        expect(find.text('Question 2/2'), findsOneWidget);
        expect(find.text('Q2'), findsOneWidget);
        expect(
          find.text('Which of the following numbers is divisible by 3?'),
          findsOneWidget,
        );
        expect(
          find.text('Finish Practice 🎉'),
          findsNothing,
        ); // not answered yet

        // Select option '21' (index 2)
        await tester.tap(find.text('21'));
        await tester.pump();
        await tester.tap(find.text('Check Answer'));
        await tester.pumpAndSettle();

        // Verify Finish Practice button appears for final question
        expect(find.text('Finish Practice 🎉'), findsOneWidget);

        // Finish Practice
        await tester.tap(find.text('Finish Practice 🎉'));
        await tester.pumpAndSettle();

        // Verify Session Summary Screen is shown
        expect(find.text('Practice Complete'), findsOneWidget);
        expect(find.text('Total Questions'), findsOneWidget);
        expect(find.text('2'), findsWidgets);
        expect(find.text('Accuracy'), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);
        expect(find.text('Correct Answers'), findsOneWidget);
        expect(find.text('Practice Again 🔁'), findsOneWidget);
        expect(find.text('Take Chapter Test 📝'), findsOneWidget);
      },
    );

    testWidgets('allows review mistakes when session has incorrect answers', (
      tester,
    ) async {
      setSurfaceSize(tester);
      final controller = TopicPracticeController(
        topicId: 'top-01',
        chapterId: 'chap-01',
        repository: FakeTopicPracticeStudyRepository(
          questions: sampleQuestions,
        ),
      );

      await tester.pumpWidget(buildTestScreen(controller: controller));
      await tester.pumpAndSettle();

      // Question 1: Answer wrong ('0')
      await tester.tap(find.text('0'));
      await tester.pump();
      await tester.tap(find.text('Check Answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Question →'));
      await tester.pumpAndSettle();

      // Question 2: Answer correct ('21')
      await tester.tap(find.text('21'));
      await tester.pump();
      await tester.tap(find.text('Check Answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish Practice 🎉'));
      await tester.pumpAndSettle();

      // Summary screen should show Review Mistakes button
      expect(find.text('Review Mistakes (1) 🔄'), findsOneWidget);

      // Tap Review Mistakes
      await tester.tap(find.text('Review Mistakes (1) 🔄'));
      await tester.pumpAndSettle();

      // Now back in practice in Review mode for Question 1
      expect(controller.isReviewMode, isTrue);
      expect(find.text('Mistake Review'), findsOneWidget);
      expect(find.text('What is the smallest prime number?'), findsOneWidget);
      expect(find.text('Question 1/1'), findsOneWidget);
    });

    testWidgets(
      'displays educational empty state when topic has no questions',
      (tester) async {
        final repo = FakeTopicPracticeStudyRepository(questions: []);

        await tester.pumpWidget(buildTestScreen(repo: repo));
        await tester.pumpAndSettle();

        expect(
          find.text('No Practice Questions Available Yet'),
          findsOneWidget,
        );
        expect(find.text('Practice Full Chapter'), findsOneWidget);

        // Tap Practice Full Chapter
        await tester.tap(find.text('Practice Full Chapter'));
        await tester.pump();
        expect(repo.fetchChapterQuestionsCalled, isTrue);
      },
    );

    testWidgets('displays error state with retry button on network failure', (
      tester,
    ) async {
      final repo = FakeTopicPracticeStudyRepository(shouldThrow: true);

      await tester.pumpWidget(buildTestScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Failed to Load Questions'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets(
      'shows exit confirmation dialog when user taps back with unsaved answers',
      (tester) async {
        final controller = TopicPracticeController(
          topicId: 'top-01',
          chapterId: 'chap-01',
          repository: FakeTopicPracticeStudyRepository(
            questions: sampleQuestions,
          ),
        );

        await tester.pumpWidget(buildTestScreen(controller: controller));
        await tester.pumpAndSettle();

        // Select an option
        await tester.tap(find.text('2'));
        await tester.pump();
        expect(controller.hasUnsavedProgress, isTrue);

        // Tap back button
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        // Dialog should appear
        expect(find.text('Exit Practice Session?'), findsOneWidget);
        expect(find.text('Keep Practicing'), findsOneWidget);
        expect(find.text('Exit'), findsOneWidget);

        // Tap Keep Practicing
        await tester.tap(find.text('Keep Practicing'));
        await tester.pumpAndSettle();

        // Dialog dismissed, still on practice screen
        expect(find.text('Exit Practice Session?'), findsNothing);
        expect(find.text('What is the smallest prime number?'), findsOneWidget);
      },
    );
  });
}
