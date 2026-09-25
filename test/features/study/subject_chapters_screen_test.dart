import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/study/data/study_repository.dart';
import 'package:my_praperation/features/study/domain/study_chapter.dart';
import 'package:my_praperation/features/study/domain/study_subject.dart';
import 'package:my_praperation/features/study/presentation/screens/subject_chapters_screen.dart';

class FakeStudyRepository implements StudyRepository {
  FakeStudyRepository({
    this.subjects = const [],
    this.chapters = const [],
    this.shouldThrow = false,
  });

  final List<StudySubject> subjects;
  final List<StudyChapter> chapters;
  final bool shouldThrow;

  @override
  Future<List<StudySubject>> fetchSubjects({
    required String languageCode,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    return subjects;
  }

  @override
  Future<List<StudyChapter>> fetchChapters({
    required String subjectId,
    required String languageCode,
    String? userId,
  }) async {
    if (shouldThrow) throw Exception('Network connection failed');
    return chapters;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const testSubject = StudySubject(
    id: 'sub-math-1',
    subjectKey: 'mathematics',
    name: 'Mathematics',
    description: 'Master core mathematical concepts and formulas.',
    icon: 'calculate',
    chapterCount: 3,
    progressPercentage: 50.0,
  );

  final testChapters = [
    const StudyChapter(
      id: 'chap-1',
      subjectId: 'sub-math-1',
      chapterKey: 'number_system',
      title: 'Number System',
      description: 'Foundational properties of numbers and primes.',
      orderIndex: 1,
      partKey: 'arithmetic',
      partTitle: 'Part 1: Arithmetic',
      partOrderIndex: 1,
      topicCount: 4,
      questionCount: 20,
      progressPercentage: 100.0, // Completed
    ),
    const StudyChapter(
      id: 'chap-2',
      subjectId: 'sub-math-1',
      chapterKey: 'percentages',
      title: 'Percentages & Ratios',
      description: 'Calculating rates, margins, and proportion.',
      orderIndex: 2,
      partKey: 'arithmetic',
      partTitle: 'Part 1: Arithmetic',
      partOrderIndex: 1,
      topicCount: 5,
      questionCount: 25,
      progressPercentage: 50.0, // In Progress
    ),
    const StudyChapter(
      id: 'chap-3',
      subjectId: 'sub-math-1',
      chapterKey: 'linear_algebra',
      title: 'Linear Algebra',
      description: 'Matrices, vectors, and determinant systems.',
      orderIndex: 3,
      partKey: 'advanced',
      partTitle: 'Part 2: Advanced Algebra',
      partOrderIndex: 2,
      topicCount: 6,
      questionCount: 30,
      progressPercentage: 0.0, // Not Started
    ),
  ];

  Widget createSubjectChaptersScreen({
    StudyRepository? repo,
    String subjectId = 'sub-math-1',
  }) {
    return MaterialApp(
      home: SubjectChaptersScreen(
        subjectId: subjectId,
        repository:
            repo ??
            FakeStudyRepository(
              subjects: [testSubject],
              chapters: testChapters,
            ),
      ),
    );
  }

  group('SubjectChaptersScreen UI Modernization Tests', () {
    testWidgets('renders subject title and syllabus mastery hero overview', (
      tester,
    ) async {
      await tester.pumpWidget(createSubjectChaptersScreen());
      await tester.pumpAndSettle();

      // Subject title in header
      expect(find.text('Mathematics'), findsWidgets);

      // Syllabus mastery header and overall percentage: (100 + 50 + 0) / 3 = 50%
      expect(find.text('Syllabus Mastery'), findsOneWidget);
      expect(find.text('50% Completed'), findsOneWidget);

      // Completed chapters count chip: "1 of 3 Chapters"
      expect(find.text('1 of 3 Chapters'), findsOneWidget);

      // Total topics count chip: 4 + 5 + 6 = 15 Topics
      expect(find.text('15 Topics'), findsOneWidget);

      // Filter chips with exact counts
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Not Started (1)'), findsOneWidget);
      expect(find.text('In Progress (1)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsOneWidget);

      // All 3 chapter cards rendered
      expect(find.text('Number System'), findsOneWidget);
      expect(find.text('Percentages & Ratios'), findsOneWidget);
      expect(find.text('Linear Algebra'), findsOneWidget);

      // Formatted 2-digit index badges
      expect(find.text('02'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);

      // Action CTA pills
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Continue (50%) →'), findsOneWidget);
      expect(find.text('Start Learning →'), findsOneWidget);
    });

    testWidgets('filters chapters by status chip: Completed', (tester) async {
      await tester.pumpWidget(createSubjectChaptersScreen());
      await tester.pumpAndSettle();

      // Tap "Completed (1)" chip
      await tester.tap(find.text('Completed (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Number System'), findsOneWidget);
      expect(find.text('Percentages & Ratios'), findsNothing);
      expect(find.text('Linear Algebra'), findsNothing);
    });

    testWidgets('filters chapters by status chip: In Progress', (tester) async {
      await tester.pumpWidget(createSubjectChaptersScreen());
      await tester.pumpAndSettle();

      // Tap "In Progress (1)" chip
      await tester.tap(find.text('In Progress (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Percentages & Ratios'), findsOneWidget);
      expect(find.text('Number System'), findsNothing);
      expect(find.text('Linear Algebra'), findsNothing);
    });

    testWidgets('filters chapters by status chip: Not Started', (tester) async {
      await tester.pumpWidget(createSubjectChaptersScreen());
      await tester.pumpAndSettle();

      // Tap "Not Started (1)" chip
      await tester.tap(find.text('Not Started (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Linear Algebra'), findsOneWidget);
      expect(find.text('Number System'), findsNothing);
      expect(find.text('Percentages & Ratios'), findsNothing);
    });

    testWidgets(
      'searches chapters in real-time and shows empty state with clear action',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(createSubjectChaptersScreen());
        await tester.pumpAndSettle();

        // Enter search text matching "linear"
        await tester.enterText(find.byType(TextField), 'linear');
        await tester.pumpAndSettle();

        expect(find.text('Linear Algebra'), findsOneWidget);
        expect(find.text('Number System'), findsNothing);

        // Enter non-matching query
        await tester.enterText(find.byType(TextField), 'QuantumPhysics');
        await tester.pumpAndSettle();

        expect(find.text('No chapters match your criteria'), findsOneWidget);
        expect(find.text('Clear All Filters'), findsOneWidget);

        // Tap Clear All Filters
        final clearButton = find.text('Clear All Filters');
        await tester.ensureVisible(clearButton);
        await tester.tap(clearButton, warnIfMissed: false);
        await tester.pumpAndSettle();

        // Restored
        expect(find.text('Number System'), findsOneWidget);
        expect(find.text('Percentages & Ratios'), findsOneWidget);
        expect(find.text('Linear Algebra'), findsOneWidget);
      },
    );

    testWidgets('filters chapters by Section / Part pill', (tester) async {
      await tester.pumpWidget(createSubjectChaptersScreen());
      await tester.pumpAndSettle();

      expect(find.text('Part 1: Arithmetic (2)'), findsOneWidget);
      expect(find.text('Part 2: Advanced Algebra (1)'), findsOneWidget);

      // Tap "Part 2: Advanced Algebra (1)"
      await tester.tap(find.text('Part 2: Advanced Algebra (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Linear Algebra'), findsOneWidget);
      expect(find.text('Number System'), findsNothing);
      expect(find.text('Percentages & Ratios'), findsNothing);
    });

    testWidgets(
      'displays error state with retry action on repository failure',
      (tester) async {
        final repo = FakeStudyRepository(shouldThrow: true);
        await tester.pumpWidget(createSubjectChaptersScreen(repo: repo));
        await tester.pumpAndSettle();

        expect(
          find.text('Failed to load chapters for this subject.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets('displays clean empty state when subject has zero chapters', (
      tester,
    ) async {
      final repo = FakeStudyRepository(subjects: [testSubject], chapters: []);
      await tester.pumpWidget(createSubjectChaptersScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('No chapters available yet'), findsOneWidget);
      expect(
        find.text('Content will be added for this subject shortly.'),
        findsOneWidget,
      );
    });
  });
}
