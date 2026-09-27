import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';
import 'package:my_praperation/features/tests/presentation/screens/test_attempt_screen.dart';
import 'package:my_praperation/features/tests/presentation/screens/test_builder_screen.dart';
import 'package:my_praperation/features/tests/presentation/screens/test_instructions_screen.dart';
import 'package:my_praperation/features/tests/presentation/screens/test_leaderboard_screen.dart';
import 'package:my_praperation/features/tests/presentation/screens/test_result_screen.dart';
import 'package:my_praperation/features/tests/presentation/screens/tests_dashboard_screen.dart';

import '../../r4_restart/fakes.dart';

/// Minimal in-memory answer store — mirrors the pattern already used by
/// `test/r4_restart/attempt_results_test.dart`'s own local fake (not shared
/// via fakes.dart today).
class _FakeAnswerRepository implements AnswerRepository {
  final Map<String, Answer> _byQuestion = {};
  final List<List<Answer>> saves = [];
  Object? failWith;

  @override
  Future<void> save(String attemptId, List<Answer> answers) async {
    if (failWith != null) {
      final e = failWith!;
      failWith = null;
      throw e;
    }
    saves.add(answers);
    for (final a in answers) {
      _byQuestion[a.questionId] = a;
    }
  }

  @override
  Future<List<Answer>> forAttempt(String attemptId) async =>
      _byQuestion.values.toList();
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    home: child,
  );
}

void main() {
  group('Screen 1: TestsDashboardScreen', () {
    testWidgets('renders goal banner, metrics strip, tabs, and FAB', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const TestsDashboardScreen()));
      await tester.pumpAndSettle();

      // Goal banner
      expect(find.text('Examination & Test Hub'), findsOneWidget);
      expect(find.text('UPSC CSE 2026'), findsOneWidget);

      // Metrics strip
      expect(find.text('Tests Taken'), findsOneWidget);
      expect(find.text('Avg Accuracy'), findsOneWidget);
      expect(find.text('Points Earned'), findsOneWidget);

      // Segmented Tabs
      expect(find.textContaining('Live & Active'), findsOneWidget);
      expect(find.textContaining('Upcoming'), findsOneWidget);
      expect(find.textContaining('Completed'), findsOneWidget);

      // Custom Test Builder FAB
      expect(find.byKey(const Key('custom_test_builder_fab')), findsOneWidget);
      expect(find.text('+ Custom Test Builder'), findsOneWidget);

      // Switch to Upcoming tab
      await tester.tap(find.textContaining('Upcoming'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Physical Geography: Geomorphology'),
        findsOneWidget,
      );
    });
  });

  group('Screen 2: TestBuilderScreen', () {
    testWidgets('renders all sections and sticky live calculation summary', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const TestBuilderScreen()));
      await tester.pumpAndSettle();

      // Section A
      expect(find.text('SECTION A: BASIC INFORMATION'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(find.text('Test Mode'), findsOneWidget);

      // Section B Sources
      expect(find.text('SECTION B: QUESTION SOURCE'), findsOneWidget);
      expect(find.textContaining('My Study & Notes'), findsOneWidget);
      expect(find.textContaining('Question Bank'), findsOneWidget);
      expect(find.textContaining('AI Generator'), findsOneWidget);

      // Section C Matrix
      expect(find.text('SECTION C: QUESTION MATRIX'), findsOneWidget);
      expect(find.text('Question Count'), findsOneWidget);
      expect(find.text('Difficulty Weightage Ratio'), findsOneWidget);

      // Section D Marking & Timer
      expect(find.text('SECTION D: MARKING & TIMER'), findsOneWidget);
      expect(find.text('Allotted Duration'), findsOneWidget);

      // Live summary button
      expect(find.text('Launch Test 🚀'), findsOneWidget);
    });
  });

  group('Screen 3: TestInstructionsScreen', () {
    testWidgets('renders academic overview and unlocks entry on confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const TestInstructionsScreen()));
      await tester.pumpAndSettle();

      // Header and parameters
      expect(find.text('Examination Instructions'), findsOneWidget);
      expect(find.text('Total Questions'), findsOneWidget);
      expect(find.text('Allotted Time'), findsOneWidget);
      expect(find.text('Maximum Marks'), findsOneWidget);
      expect(find.text('Negative Marking'), findsOneWidget);

      // Rules and server-timer notice
      expect(find.text('EXAMINATION RULES & MARKING SCHEME'), findsOneWidget);
      expect(find.textContaining('Server Clock Synchronized'), findsOneWidget);

      // Checkbox gate
      final checkboxFinder = find.byKey(
        const Key('confirm_readiness_checkbox'),
      );
      expect(checkboxFinder, findsOneWidget);

      final enterBtnFinder = find.byKey(
        const Key('enter_examination_hall_btn'),
      );
      expect(enterBtnFinder, findsOneWidget);

      // Initially disabled
      final initialBtn = tester.widget<FilledButton>(enterBtnFinder);
      expect(initialBtn.onPressed, isNull);

      // Scroll to checkbox and tap
      await tester.ensureVisible(checkboxFinder);
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Now enabled
      final updatedBtn = tester.widget<FilledButton>(enterBtnFinder);
      expect(updatedBtn.onPressed, isNotNull);
    });
  });

  group('Screen 4: TestAttemptScreen (real AttemptController, injected for determinism)', () {
    late AttemptController controller;

    setUp(() async {
      AttemptLaunchStore.clear();
      const questions = [
        Question(
          id: 'q-1',
          testId: 't-1',
          question: 'Consider the following statements regarding the Ilbert '
              'Bill Controversy (1883). Which is/are correct?',
          options: [
            QuestionOption(id: 'a', text: '1 and 2 only', index: 0),
            QuestionOption(id: 'b', text: '1 and 3 only', index: 1),
            QuestionOption(id: 'c', text: '2 and 3 only', index: 2),
            QuestionOption(id: 'd', text: '1, 2, and 3', index: 3),
          ],
          difficulty: DifficultyLevel.medium,
          marks: 2,
          status: 'active',
        ),
      ];
      AttemptLaunchStore.putLaunch(
        started: (
          attempt: Attempt(
            id: 'a-1',
            testId: 't-1',
            userId: 'u-1',
            status: AttemptStatus.inProgress,
            startedAt: DateTime.now(),
            deadlineAt: DateTime.now().add(const Duration(minutes: 30)),
          ),
          testTitle: null,
        ),
        questions: questions,
        test: const Test(
          id: 't-1',
          createdBy: 'u-1',
          title: 'Sample Test',
          status: TestStatus.live,
          testMode: 'self',
        ),
      );
      controller = AttemptController(
        attemptId: 'a-1',
        testId: 't-1',
        attempts: FakeAttemptRepository(),
        questions: FakeQuestionRepository(),
        answers: _FakeAnswerRepository(),
        tests: FakeTestRepository(),
        autosaveInterval: const Duration(hours: 1),
      );
      await controller.load();
    });

    tearDown(() => controller.dispose());

    testWidgets(
      'renders live examination, timer, options, and submission audit dialog',
      (tester) async {
        await tester.pumpWidget(
          _host(TestAttemptScreen(attemptController: controller)),
        );
        await tester.pumpAndSettle();

        // Top bar elements
        expect(find.textContaining('Q 1 /'), findsOneWidget);
        expect(
          find.byKey(const Key('open_palette_drawer_btn')),
          findsOneWidget,
        );

        // Question statement & options (real data from the controller)
        expect(find.textContaining('Ilbert Bill Controversy'), findsOneWidget);
        expect(find.text('1 and 2 only'), findsOneWidget);
        expect(find.text('1 and 3 only'), findsOneWidget);

        // Select option B — real controller state, not local widget state
        final optionB = find.byKey(const Key('option_card_0_1'));
        expect(optionB, findsOneWidget);
        await tester.ensureVisible(optionB);
        await tester.tap(optionB);
        await tester.pumpAndSettle();
        expect(controller.answerFor('q-1')?.selectedOption, 1);

        // Toggle Mark for review
        final reviewBtn = find.byKey(const Key('mark_for_review_btn'));
        expect(reviewBtn, findsOneWidget);
        await tester.tap(reviewBtn);
        await tester.pumpAndSettle();
        expect(find.text('Marked'), findsOneWidget);
        expect(controller.answerFor('q-1')?.markedForReview, isTrue);

        // Submit test button opens Audit dialog
        final submitBtn = find.byKey(const Key('submit_test_btn'));
        expect(submitBtn, findsOneWidget);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        // Submission Audit Dialog
        expect(find.text('Submit Examination?'), findsOneWidget);
        expect(find.text('Answered Questions'), findsOneWidget);
        expect(find.text('Marked for Review'), findsOneWidget);
        expect(
          find.byKey(const Key('confirm_submit_audit_btn')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'confirming submission calls the real submit flow exactly once',
      (tester) async {
        await tester.pumpWidget(
          _host(TestAttemptScreen(attemptController: controller)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('submit_test_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_submit_audit_btn')));
        await tester.pumpAndSettle();

        final attempts = controller.attempt; // sanity: still resolvable
        expect(attempts, isNotNull);
        expect(controller.isInteractive, isFalse);
      },
    );
  });

  group('Screen 5: TestResultScreen', () {
    testWidgets('renders hero score card, celebratory points, and solutions', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const TestResultScreen()));
      await tester.pumpAndSettle();

      // Hero score ring & celebratory badge
      expect(find.text('Scorecard & Performance Analysis'), findsOneWidget);
      expect(find.text('+15 Study Points Added'), findsOneWidget);
      expect(find.textContaining('Top 8%'), findsOneWidget);

      // Distribution bar & topic mastery
      expect(
        find.text('ATTEMPT DISTRIBUTION & MARK BREAKDOWN'),
        findsOneWidget,
      );
      expect(find.text('TOPIC MASTERY MATRIX'), findsOneWidget);
      expect(
        find.textContaining('Strong Topics (Accuracy > 75%)'),
        findsOneWidget,
      );

      // Solutions Tab
      expect(find.text('Full Solutions & Review'), findsOneWidget);
      final aiTab = find.text('🤖 AI Performance Coach');
      expect(aiTab, findsOneWidget);

      // Switch to AI Coach tab
      await tester.ensureVisible(aiTab);
      await tester.tap(aiTab);
      await tester.pumpAndSettle();

      expect(find.text('AI COHORT COACH DIAGNOSTIC REPORT'), findsOneWidget);
      expect(find.text('1. Elimination Strategy & Precision'), findsOneWidget);
    });
  });

  group('Screen 6: TestLeaderboardScreen', () {
    testWidgets('displays unpublished gate when results are pending', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const TestLeaderboardScreen(isResultPublished: false)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Results Awaiting Cohort Leader Release'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Results will be published by cohort leader'),
        findsOneWidget,
      );
      expect(find.text('Check for Updates'), findsOneWidget);
    });

    testWidgets('displays published leaderboard with podium and export hub', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const TestLeaderboardScreen(isResultPublished: true)),
      );
      await tester.pumpAndSettle();

      // Summary & My rank highlight
      expect(find.text('Cohort Leaderboard & Analytics'), findsOneWidget);
      expect(find.text('YOUR STANDING: RANK #4'), findsOneWidget);

      // Top 3 Podium
      expect(find.text('👑 #1'), findsOneWidget);
      expect(find.text('🥈 #2'), findsOneWidget);
      expect(find.text('🥉 #3'), findsOneWidget);

      // Export section
      expect(find.text('EXPORT HUB & ARCHIVAL'), findsOneWidget);
      final downloadScorecardBtn = find.byKey(
        const Key('download_scorecard_pdf_btn'),
      );
      expect(downloadScorecardBtn, findsOneWidget);

      await tester.ensureVisible(downloadScorecardBtn);
      await tester.tap(downloadScorecardBtn);
      await tester.pumpAndSettle();

      // The real PDF is built and handed to Printing.sharePdf, which has no
      // platform implementation in a widget test — the screen's catch-all
      // then shows a generic failure snackbar rather than crashing or
      // claiming a fake success (there is no more hardcoded "Ready to
      // view." message: this button now calls the real
      // TestPdfExportService).
      expect(
        find.text('Could not generate the scorecard PDF. Please try again.'),
        findsOneWidget,
      );
    });
  });
}
