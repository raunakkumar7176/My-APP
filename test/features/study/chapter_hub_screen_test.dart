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

  group('ChapterHubScreen UI Modernization Tests', () {
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

      // Header title & breadcrumb
      expect(find.text('Number Systems & Divisibility'), findsOneWidget);
      expect(find.text('Part 1: Arithmetic • Chapter 01'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);

      // Chapter progress hero card: 1 of 2 topics completed -> 50%
      expect(find.text('Chapter Mastery'), findsOneWidget);
      expect(find.text('50% Completed'), findsOneWidget);
      expect(find.text('1 of 2 Topics completed'), findsOneWidget);
      expect(
        find.text('Est. Time: 20 mins'),
        findsOneWidget,
      ); // 8 + 12 = 20 mins

      // Smart Action CTA for in-progress chapter
      expect(find.text('Continue Learning →'), findsOneWidget);

      // 2-tab segmented navigation bar (Learn & Assessment Hub)
      expect(find.text('Learn'), findsOneWidget);
      expect(find.text('Assessment Hub'), findsOneWidget);

      // "What you'll master" box in Learn Tab
      expect(find.text("What you'll master:"), findsOneWidget);

      // Both topics rendered with 2-digit badges and status pills (present in overview and list card)
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

      // Topic cards render Practice secondary action button
      expect(find.text('Practice'), findsNWidgets(2));

      // Chapter-Wide Practice Card
      expect(find.text('Chapter Practice'), findsOneWidget);
      expect(
        find.text('Practice questions across all topics in this chapter.'),
        findsOneWidget,
      );
      expect(find.text('15 Questions Available'), findsOneWidget);
      expect(find.text('Practice Chapter'), findsOneWidget);

      // Revision & Weak Areas Card
      expect(find.text('Revision & Recall'), findsOneWidget);
      expect(
        find.text(
          'No incorrect questions to review. Review key formulas and concept notes.',
        ),
        findsOneWidget,
      );
      expect(find.text('Review Q&A Flashcards'), findsOneWidget);

      // Official Assessment Bridge Card
      expect(find.text('Official Assessment'), findsOneWidget);
      expect(find.text('Take Assessment →'), findsOneWidget);
    });

    testWidgets(
      'switches to Assessment Hub tab and renders Smart Practice mode active recall flashcards',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createChapterHubScreen());
        await tester.pumpAndSettle();

        // Tap "Assessment Hub" tab
        await tester.tap(find.text('Assessment Hub'));
        await tester.pumpAndSettle();

        // Mode Switcher displays Smart Practice and Formal Exam
        expect(find.text('Smart Practice'), findsOneWidget);
        expect(find.text('Formal Exam'), findsOneWidget);

        // Revision notice banner
        expect(
          find.text('Active Recall & Revision Mode (1 Questions)'),
          findsOneWidget,
        );

        // Question rendered with Q1 badge
        expect(find.text('Q1'), findsOneWidget);
        expect(
          find.text('Which of the following numbers is prime?'),
          findsOneWidget,
        );

        // 4 options rendered
        expect(find.text('91'), findsOneWidget);
        expect(find.text('51'), findsOneWidget);
        expect(find.text('97'), findsOneWidget);
        expect(find.text('87'), findsOneWidget);

        // Correct option marked with "Correct" badge
        expect(find.text('Correct'), findsOneWidget);

        // Interactive practice button in Q&A banner
        expect(find.text('Interactive Practice Mode ⚡'), findsOneWidget);

        // Explanation callout open by default
        expect(find.text('Explanation & Concept Note:'), findsOneWidget);
        expect(
          find.text(
            '91 = 7 x 13, 51 = 3 x 17, 87 = 3 x 29. 97 has no divisors other than 1 and 97.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'switches to Formal Exam mode inside Assessment Hub and renders test generator hero card',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createChapterHubScreen());
        await tester.pumpAndSettle();

        // Tap "Assessment Hub" tab
        await tester.tap(find.text('Assessment Hub'));
        await tester.pumpAndSettle();

        // Tap "Formal Exam" mode
        await tester.tap(find.text('Formal Exam'));
        await tester.pumpAndSettle();

        // Hero card title and description
        expect(find.text('Test Your Knowledge'), findsOneWidget);
        expect(find.text('Timed Mode'), findsOneWidget);
        expect(find.text('Hidden Solutions'), findsOneWidget);
        expect(find.text('Instant Scorecard'), findsOneWidget);

        // CTA button
        expect(find.text('Start Chapter Test →'), findsOneWidget);
      },
    );

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

    testWidgets(
      'switches to Assessment Hub when Review Q&A Flashcards is tapped in Learn tab',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createChapterHubScreen());
        await tester.pumpAndSettle();

        // Tap "Review Q&A Flashcards" in Revision & Recall card
        final reviewButton = find.text('Review Q&A Flashcards');
        expect(reviewButton, findsOneWidget);
        await tester.tap(reviewButton);
        await tester.pumpAndSettle();

        // Tab should have changed to Assessment Hub in Smart Practice mode
        expect(find.text('Smart Practice'), findsOneWidget);
        expect(
          find.text('Active Recall & Revision Mode (1 Questions)'),
          findsOneWidget,
        );
        expect(find.text('Q1'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping option in Smart Practice gives immediate feedback and updates score',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createChapterHubScreen());
        await tester.pumpAndSettle();

        // Switch to Assessment Hub
        await tester.tap(find.text('Assessment Hub'));
        await tester.pumpAndSettle();

        // Tap correct option '97'
        await tester.tap(find.text('97'));
        await tester.pumpAndSettle();

        // Score badge appears in mode switcher
        expect(find.text('1/1'), findsOneWidget);
      },
    );

    testWidgets('toggles language between EN and HI smoothly', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createChapterHubScreen());
      await tester.pumpAndSettle();

      // Initially EN
      expect(find.text('EN'), findsOneWidget);
      expect(find.text('Chapter Mastery'), findsOneWidget);
      expect(find.text('Chapter Practice'), findsOneWidget);
      expect(find.text('Revision & Recall'), findsOneWidget);

      // Tap language switch button
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();

      // Now HI
      expect(find.text('HI'), findsOneWidget);
      expect(find.text('अध्याय प्रगति समीक्षा'), findsOneWidget);
      expect(find.text('अध्याय अभ्यास'), findsOneWidget);
      expect(find.text('पुनरावृत्ति एवं स्मरण'), findsOneWidget);
    });
  });
}
