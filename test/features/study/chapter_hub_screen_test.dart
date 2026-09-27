// Chapter Hub — streamlined to exactly 3 modes (Learn, Read MCQ, Chapter
// Practice). No test-builder navigation exists anywhere in this screen:
// the old "Assessment Hub" / "Formal Exam" mode (which bridged to
// /tests/create) has been removed entirely, per the explicit product
// requirement that Chapter Hub never opens the standalone test-creation
// flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/study/data/study_repository.dart';
import 'package:my_praperation/features/study/domain/study_chapter.dart';
import 'package:my_praperation/features/study/domain/study_question.dart';
import 'package:my_praperation/features/study/domain/study_subject.dart';
import 'package:my_praperation/features/study/domain/study_topic.dart';
import 'package:my_praperation/features/study/presentation/controllers/chapter_hub_controller.dart';
import 'package:my_praperation/features/study/presentation/screens/chapter_hub_screen.dart';

class FakeChapterHubStudyRepository implements StudyRepository {
  FakeChapterHubStudyRepository({
    this.chapter,
    this.topics = const [],
    this.questions = const [],
    this.shouldThrow = false,
  });

  final StudyChapter? chapter;
  final List<StudyTopic> topics;
  final List<StudyQuestion> questions;
  final bool shouldThrow;

  @override
  Future<StudyChapter> fetchChapterById({
    required String chapterId,
    required String languageCode,
    String? userId,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    return chapter ??
        StudyChapter(
          id: chapterId,
          subjectId: 'sub-1',
          chapterKey: 'test_chapter',
          title: 'Number Systems & Divisibility',
          orderIndex: 1,
          partTitle: 'Part 1: Arithmetic',
          topicCount: topics.length,
          questionCount: questions.length,
          progressPercentage: 50.0,
        );
  }

  @override
  Future<List<StudyTopic>> fetchTopics({
    required String chapterId,
    required String languageCode,
    String? userId,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    return topics;
  }

  @override
  Future<List<StudyQuestion>> fetchChapterQuestions({
    required String chapterId,
    required String languageCode,
    int limit = 20,
    int offset = 0,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    return questions;
  }

  @override
  Future<List<StudySubject>> fetchSubjects({
    required String languageCode,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const testChapter = StudyChapter(
    id: 'chap-math-01',
    subjectId: 'sub-math-1',
    chapterKey: 'number_systems',
    title: 'Number Systems & Divisibility',
    description:
        'Foundational properties of prime numbers and modulo arithmetic.',
    orderIndex: 1,
    partKey: 'arithmetic',
    partTitle: 'Part 1: Arithmetic',
    topicCount: 2,
    questionCount: 15,
    progressPercentage: 50.0,
  );

  final testTopics = [
    const StudyTopic(
      id: 'topic-01',
      chapterId: 'chap-math-01',
      topicKey: 'prime_numbers',
      title: 'Prime Numbers & Prime Factorization',
      summary: 'Definition of primes, fundamental theorem of arithmetic.',
      orderIndex: 1,
      estimatedMinutes: 8,
      isCompleted: true,
    ),
    const StudyTopic(
      id: 'topic-02',
      chapterId: 'chap-math-01',
      topicKey: 'divisibility_rules',
      title: 'Divisibility Rules & Modular Arithmetic',
      summary: 'Rules for 2, 3, 4, 7, 11, and congruence relations.',
      orderIndex: 2,
      estimatedMinutes: 12,
      isCompleted: false,
    ),
  ];

  final testQuestions = [
    const StudyQuestion(
      id: 'q-01',
      chapterId: 'chap-math-01',
      question: 'Which of the following numbers is prime?',
      options: ['91', '51', '97', '87'],
      correctOption: 2, // 97 is prime
      explanation: '91 = 7 x 13, 51 = 3 x 17, 87 = 3 x 29. 97 has no divisors other than 1 and 97.',
    ),
  ];

  Widget createChapterHubScreen({
    StudyRepository? repo,
    ChapterHubController? controller,
    int initialTab = 0,
  }) {
    return MaterialApp(
      home: ChapterHubScreen(
        chapterId: 'chap-math-01',
        initialTab: initialTab,
        repository:
            repo ??
            FakeChapterHubStudyRepository(
              chapter: testChapter,
              topics: testTopics,
              questions: testQuestions,
            ),
        controller: controller,
      ),
    );
  }

  group('ChapterHubScreen — 3-mode structure', () {
    testWidgets('renders chapter header, breadcrumbs, and progress hero card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      expect(find.text('Number Systems & Divisibility'), findsOneWidget);
      expect(find.text('Part 1: Arithmetic • Chapter 01'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);

      expect(find.text('Chapter Mastery'), findsOneWidget);
      expect(find.text('50% Completed'), findsOneWidget);
      expect(find.text('1 of 2 Topics completed'), findsOneWidget);
      expect(find.text('Est. Time: 20 mins'), findsOneWidget);
      expect(find.text('Continue Learning →'), findsOneWidget);

      // Exactly 3 tabs: Learn, Read MCQ, Practice — no 4th "test" tab.
      expect(find.text('Learn'), findsOneWidget);
      expect(find.text('Read MCQ'), findsOneWidget);
      expect(find.text('Practice'), findsWidgets); // tab label + card title

      expect(find.text("What you'll master:"), findsOneWidget);
      expect(
        find.text('Prime Numbers & Prime Factorization'),
        findsNWidgets(2),
      );
      expect(
        find.text('Divisibility Rules & Modular Arithmetic'),
        findsNWidgets(2),
      );
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Read →'), findsOneWidget);
      expect(find.text('8 mins'), findsOneWidget);
      expect(find.text('12 mins'), findsOneWidget);

      expect(find.text('Chapter Practice'), findsOneWidget);
      expect(
        find.text('Practice questions across all topics in this chapter.'),
        findsOneWidget,
      );
      expect(find.text('15 Questions Available'), findsOneWidget);
      expect(find.text('Practice Chapter'), findsOneWidget);

      expect(find.text('Revision & Recall'), findsOneWidget);
      expect(find.text('Review Q&A Flashcards'), findsOneWidget);

      // The old "Official Assessment" / test-builder bridge card is gone.
      expect(find.text('Official Assessment'), findsNothing);
      expect(find.text('Take Assessment →'), findsNothing);
      expect(find.text('Start Chapter Test →'), findsNothing);
    });

    testWidgets('Read MCQ tab shows the question, highlighted correct answer, and explanation — read-only', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chapter_hub_tab_read_mcq')));
      await tester.pumpAndSettle();

      expect(find.text('Q1'), findsOneWidget);
      expect(
        find.text('Which of the following numbers is prime?'),
        findsOneWidget,
      );
      expect(find.text('91'), findsOneWidget);
      expect(find.text('97'), findsOneWidget);
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Explanation & Concept Note:'), findsOneWidget);
      expect(
        find.text(
          '91 = 7 x 13, 51 = 3 x 17, 87 = 3 x 29. 97 has no divisors other than 1 and 97.',
        ),
        findsOneWidget,
      );

      // Read-only: tapping an option does nothing (no InkWell/selection
      // state on options in this tab) — the correct answer was already
      // shown before any tap, and remains the only "Correct" badge.
      await tester.tap(find.text('91'));
      await tester.pumpAndSettle();
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Your Choice'), findsNothing);
    });

    testWidgets('Chapter Practice tab is interactive: tapping the correct option shows feedback and a Next button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chapter_hub_tab_practice')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('practice_question_q-01')), findsOneWidget);
      expect(find.byKey(const Key('practice_bookmark_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice_option_q-01_2')));
      await tester.pumpAndSettle();

      // Feedback snackbar + finish button (this is the last/only question).
      expect(find.textContaining('Correct'), findsWidgets);
      expect(find.byKey(const Key('practice_next_button')), findsOneWidget);

      // Explanation stays collapsed until explicitly expanded.
      expect(find.byKey(const Key('practice_explanation_text')), findsNothing);
      await tester.tap(find.byKey(const Key('practice_toggle_explanation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('practice_explanation_text')), findsOneWidget);
    });

    testWidgets('bookmarking a question in Chapter Practice is a local-only toggle', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chapter_hub_tab_practice')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('practice_bookmark_button')));
      await tester.pumpAndSettle();
      expect(find.text('Saved to bookmarks'), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice_bookmark_button')));
      await tester.pumpAndSettle();
      expect(find.text('Bookmark removed'), findsOneWidget);
    });

    testWidgets('completing Chapter Practice shows the session summary with a restart option', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chapter_hub_tab_practice')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('practice_option_q-01_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('practice_next_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chapter_practice_summary')), findsOneWidget);
      expect(find.text('1 / 1 Correct'), findsOneWidget);
    });

    testWidgets('displays error state with retry button on failure', (
      tester,
    ) async {
      final repo = FakeChapterHubStudyRepository(shouldThrow: true);
      await tester.pumpWidget(createChapterHubScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load chapter information.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('displays empty state when chapter has zero topics', (
      tester,
    ) async {
      final repo = FakeChapterHubStudyRepository(
        chapter: testChapter,
        topics: [],
        questions: [],
      );
      await tester.pumpWidget(createChapterHubScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('No topics available for this chapter'), findsOneWidget);
      expect(
        find.text('Content will be added for this chapter shortly.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping Review Q&A Flashcards in Learn tab switches to Read MCQ', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      final reviewButton = find.text('Review Q&A Flashcards');
      expect(reviewButton, findsOneWidget);
      await tester.tap(reviewButton);
      await tester.pumpAndSettle();

      expect(find.text('Q1'), findsOneWidget);
      expect(
        find.text('Which of the following numbers is prime?'),
        findsOneWidget,
      );
      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('tapping Practice Chapter in Learn tab switches to Chapter Practice', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Practice Chapter'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('practice_question_q-01')), findsOneWidget);
    });

    testWidgets('toggles language between EN and HI smoothly', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      expect(find.text('EN'), findsOneWidget);
      expect(find.text('Chapter Mastery'), findsOneWidget);
      expect(find.text('Chapter Practice'), findsOneWidget);
      expect(find.text('Revision & Recall'), findsOneWidget);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();

      expect(find.text('HI'), findsOneWidget);
      expect(find.text('अध्याय प्रगति समीक्षा'), findsOneWidget);
      expect(find.text('अध्याय अभ्यास'), findsOneWidget);
      expect(find.text('पुनरावृत्ति एवं स्मरण'), findsOneWidget);
    });
  });
}
