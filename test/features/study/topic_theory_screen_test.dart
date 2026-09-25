import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/study/data/study_repository.dart';
import 'package:my_praperation/features/study/domain/content_block.dart';
import 'package:my_praperation/features/study/domain/study_chapter.dart';
import 'package:my_praperation/features/study/domain/study_question.dart';
import 'package:my_praperation/features/study/domain/study_subject.dart';
import 'package:my_praperation/features/study/domain/study_topic.dart';
import 'package:my_praperation/features/study/presentation/controllers/topic_theory_controller.dart';
import 'package:my_praperation/features/study/presentation/screens/topic_theory_screen.dart';

class FakeTopicTheoryStudyRepository implements StudyRepository {
  FakeTopicTheoryStudyRepository({
    this.chapter,
    this.topics = const [],
    this.blocks = const [],
    this.shouldThrow = false,
  });

  final StudyChapter? chapter;
  final List<StudyTopic> topics;
  final List<ContentBlock> blocks;
  final bool shouldThrow;
  bool completionToggled = false;

  @override
  Future<StudyChapter> fetchChapterById({
    required String chapterId,
    required String languageCode,
    String? userId,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    return chapter ??
        const StudyChapter(
          id: 'chap-math-01',
          subjectId: 'sub-math-1',
          chapterKey: 'number_systems',
          title: 'Number Systems & Divisibility',
          orderIndex: 1,
          partTitle: 'Part 1: Arithmetic',
          topicCount: 2,
          questionCount: 15,
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
  Future<StudyTopic> fetchTopicById({
    required String topicId,
    required String languageCode,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    return topics.firstWhere(
      (t) => t.id == topicId,
      orElse: () => StudyTopic(
        id: topicId,
        chapterId: 'chap-math-01',
        topicKey: 'prime_numbers',
        title: 'Prime Numbers & Prime Factorization',
        orderIndex: 1,
        estimatedMinutes: 10,
        isCompleted: false,
      ),
    );
  }

  @override
  Future<List<ContentBlock>> fetchContentBlocks({
    required String topicId,
    required String languageCode,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    return blocks;
  }

  @override
  Future<void> toggleTopicCompletion({
    required String topicId,
    required String chapterId,
    required String userId,
    required bool isCompleted,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    completionToggled = true;
  }

  @override
  Future<List<StudyQuestion>> fetchChapterQuestions({
    required String chapterId,
    required String languageCode,
    int limit = 20,
    int offset = 0,
  }) async => [];

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
    description: 'Foundational properties of prime numbers.',
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
      title: 'Prime Numbers & Factorization',
      summary: 'Definition of primes and composite numbers.',
      orderIndex: 1,
      estimatedMinutes: 8,
      isCompleted: false,
    ),
    const StudyTopic(
      id: 'topic-02',
      chapterId: 'chap-math-01',
      topicKey: 'divisibility_rules',
      title: 'Divisibility Rules & Modulo',
      summary: 'Rules for 2, 3, 4, 7, 11.',
      orderIndex: 2,
      estimatedMinutes: 12,
      isCompleted: true,
    ),
  ];

  final testBlocks = [
    const ContentBlock(
      id: 'block-01',
      topicId: 'topic-01',
      blockType: ContentBlockType.heading,
      orderIndex: 1,
      content: {'text': 'Core Definition of Prime Numbers'},
    ),
    const ContentBlock(
      id: 'block-02',
      topicId: 'topic-01',
      blockType: ContentBlockType.paragraph,
      orderIndex: 2,
      content: {
        'text': 'A natural number strictly greater than 1 that cannot be formed by multiplying two smaller natural numbers.',
      },
    ),
    const ContentBlock(
      id: 'block-03',
      topicId: 'topic-01',
      blockType: ContentBlockType.definition,
      orderIndex: 3,
      content: {
        'text': 'Fundamental Theorem of Arithmetic: Every integer greater than 1 is either a prime itself or can be represented uniquely as a product of prime numbers.',
      },
    ),
    const ContentBlock(
      id: 'block-04',
      topicId: 'topic-01',
      blockType: ContentBlockType.formula,
      orderIndex: 4,
      content: {
        'text': 'Prime Factorization Form',
        'latex':
            r'N = p_1^{a_1} \times p_2^{a_2} \times \dots \times p_k^{a_k}',
      },
    ),
    const ContentBlock(
      id: 'block-05',
      topicId: 'topic-01',
      blockType: ContentBlockType.example,
      orderIndex: 5,
      content: {
        'problem': 'Find the number of divisors of 360.',
        'solution':
            '360 = 2^3 * 3^2 * 5^1. Total divisors = (3+1)(2+1)(1+1) = 24.',
      },
    ),
    const ContentBlock(
      id: 'block-06',
      topicId: 'topic-01',
      blockType: ContentBlockType.importantPoint,
      orderIndex: 6,
      content: {
        'text': 'Exam Pitfalls to Avoid',
        'points': [
          '1 is neither prime nor composite.',
          '2 is the only even prime number.',
        ],
      },
    ),
    const ContentBlock(
      id: 'block-07',
      topicId: 'topic-01',
      blockType: ContentBlockType.commonMistake,
      orderIndex: 7,
      content: {
        'mistake': 'Assuming all odd numbers are prime (e.g. 9, 15, 21).',
        'correction':
            'Odd composite numbers have factors besides 1 and itself.',
      },
    ),
  ];

  Widget createTopicTheoryScreen({
    StudyRepository? repo,
    TopicTheoryController? controller,
    String topicId = 'topic-01',
  }) {
    return MaterialApp(
      home: TopicTheoryScreen(
        topicId: topicId,
        chapterId: 'chap-math-01',
        repository:
            repo ??
            FakeTopicTheoryStudyRepository(
              chapter: testChapter,
              topics: testTopics,
              blocks: testBlocks,
            ),
        controller: controller,
      ),
    );
  }

  group('TopicTheoryScreen UI Modernization Tests', () {
    testWidgets('renders header with breadcrumbs, topic title, and controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTopicTheoryScreen());
      await tester.pumpAndSettle();

      // Breadcrumb & Topic Title
      expect(
        find.text('Part 1: Arithmetic • Number Systems & Divisibility'),
        findsOneWidget,
      );
      expect(find.text('Prime Numbers & Factorization'), findsOneWidget);

      // Language Switch Pill & Bookmark
      expect(find.text('EN'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);

      // Reading progress metadata chip
      expect(find.text('Topic Progress: 0% • ⏱️ 8 min read'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
    });

    testWidgets(
      'renders modular content blocks with distinct academic callouts',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createTopicTheoryScreen());
        await tester.pumpAndSettle();

        // Heading
        expect(find.text('Core Definition of Prime Numbers'), findsOneWidget);

        // Paragraph
        expect(
          find.text(
            'A natural number strictly greater than 1 that cannot be formed by multiplying two smaller natural numbers.',
          ),
          findsOneWidget,
        );

        // Definition card with DEFINITION badge
        expect(find.text('DEFINITION'), findsOneWidget);
        expect(
          find.textContaining('Fundamental Theorem of Arithmetic'),
          findsOneWidget,
        );

        // Formula container with LaTeX
        expect(find.text('Prime Factorization Form'), findsOneWidget);
        expect(find.byIcon(Icons.functions_rounded), findsOneWidget);
        expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

        // Worked Example with Problem & Solution
        expect(find.text('WORKED EXAMPLE'), findsOneWidget);
        expect(
          find.text('Find the number of divisors of 360.'),
          findsOneWidget,
        );
        expect(
          find.text(
            '360 = 2^3 * 3^2 * 5^1. Total divisors = (3+1)(2+1)(1+1) = 24.',
          ),
          findsOneWidget,
        );

        // Important to Remember
        expect(find.text('IMPORTANT TO REMEMBER'), findsOneWidget);
        expect(find.text('1 is neither prime nor composite.'), findsOneWidget);
        expect(find.text('2 is the only even prime number.'), findsOneWidget);

        // Common Pitfall / Mistake
        expect(find.text('COMMON PITFALL / MISTAKE'), findsOneWidget);
        expect(
          find.textContaining('Assuming all odd numbers are prime'),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders end-of-topic practice card and topic traversal bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTopicTheoryScreen());
      await tester.pumpAndSettle();

      // Scroll down to reveal End-of-Topic section
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      // Practice Card
      expect(find.text('Test Your Understanding'), findsOneWidget);
      expect(find.text('Practice This Topic →'), findsOneWidget);

      // Traversal Bar (topic 1 of 2: has next topic, but no previous)
      expect(find.text('Previous Topic'), findsOneWidget);
      expect(find.text('Next Topic'), findsOneWidget);
      expect(find.text('Divisibility Rules & Modulo'), findsOneWidget);
    });

    testWidgets('allows marking topic as completed from bottom bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repo = FakeTopicTheoryStudyRepository(
        chapter: testChapter,
        topics: testTopics,
        blocks: testBlocks,
      );

      await tester.pumpWidget(createTopicTheoryScreen(repo: repo));
      await tester.pumpAndSettle();

      // Initially not completed -> Mark as Completed button visible
      expect(find.text('Mark as Completed'), findsOneWidget);

      // Tap Mark as Completed
      await tester.tap(find.text('Mark as Completed'));
      await tester.pumpAndSettle();

      // Button now indicates completion
      expect(find.text('✓ Completed'), findsWidgets);
    });

    testWidgets('displays error state with retry button on network failure', (
      tester,
    ) async {
      final repo = FakeTopicTheoryStudyRepository(shouldThrow: true);

      await tester.pumpWidget(createTopicTheoryScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load topic contents.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('displays clean empty state when topic has no blocks', (
      tester,
    ) async {
      final repo = FakeTopicTheoryStudyRepository(
        chapter: testChapter,
        topics: testTopics,
        blocks: const [],
      );

      await tester.pumpWidget(createTopicTheoryScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('No content blocks loaded'), findsOneWidget);
      expect(find.text('Reload'), findsOneWidget);
    });
  });
}
