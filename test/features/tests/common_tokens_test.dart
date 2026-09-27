import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/tests/presentation/widgets/common/question_palette_grid.dart';
import 'package:my_praperation/features/tests/presentation/widgets/common/result_metric_card.dart';
import 'package:my_praperation/features/tests/presentation/widgets/common/test_card.dart';
import 'package:my_praperation/features/tests/presentation/widgets/common/timer_pill.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('Unified Test Design System Tokens', () {
    testWidgets('TestCard renders subject, difficulty, mode, and live CTA', (
      tester,
    ) async {
      var actionTriggered = false;

      const liveTest = TestCardData(
        id: 'test_1',
        title: 'Modern Indian History: Freedom Struggle',
        subject: 'History',
        difficulty: TestCardDifficulty.medium,
        mode: 'Exam Simulation',
        questionCount: 25,
        totalMarks: 50.0,
        durationMinutes: 35,
        status: TestCardStatus.live,
      );

      await tester.pumpWidget(
        _host(TestCard(data: liveTest, onAction: () => actionTriggered = true)),
      );
      await tester.pumpAndSettle();

      // Subject, Difficulty, Mode
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Exam Simulation'), findsOneWidget);
      expect(find.text('🟢 LIVE NOW'), findsOneWidget);

      // Metadata
      expect(find.text('25 Questions'), findsOneWidget);
      expect(find.text('50 Marks'), findsOneWidget);
      expect(find.text('35m'), findsOneWidget);

      // Live CTA
      final startBtn = find.text('Start Examination ➔');
      expect(startBtn, findsOneWidget);

      await tester.tap(startBtn);
      await tester.pumpAndSettle();
      expect(actionTriggered, isTrue);
    });

    testWidgets(
      'TestCard renders completed status with score and analysis CTA',
      (tester) async {
        const completedTest = TestCardData(
          id: 'test_2',
          title: 'Polity: Preamble & DPSPs',
          subject: 'Polity',
          difficulty: TestCardDifficulty.hard,
          mode: 'Speed Drill',
          questionCount: 20,
          totalMarks: 40.0,
          durationMinutes: 20,
          status: TestCardStatus.completed,
          scoreObtained: 34.0,
          accuracyPercentage: 85.0,
          rank: 2,
        );

        await tester.pumpWidget(_host(const TestCard(data: completedTest)));
        await tester.pumpAndSettle();

        expect(find.text('Score: '), findsOneWidget);
        expect(find.text('34.0 / 40'), findsOneWidget);
        expect(find.text('Accuracy: 85.0%'), findsOneWidget);
        expect(find.text('Rank: #2'), findsOneWidget);
        expect(find.text('View Scorecard & Solutions'), findsOneWidget);
        expect(find.text('Leaderboard'), findsOneWidget);
      },
    );

    testWidgets(
      'QuestionPaletteGrid renders legend, buttons, and handles callbacks',
      (tester) async {
        int? tappedIndex;

        await tester.pumpWidget(
          _host(
            QuestionPaletteGrid(
              totalQuestions: 6,
              currentIndex: 0,
              answeredIndices: const {1, 2},
              markedIndices: const {3},
              onQuestionSelected: (idx) => tappedIndex = idx,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Legend items
        expect(find.text('Answered'), findsOneWidget);
        expect(find.text('Unanswered'), findsOneWidget);
        expect(find.text('Marked Review'), findsOneWidget);
        expect(find.text('Current'), findsOneWidget);

        // 6 question numbers
        for (var i = 1; i <= 6; i++) {
          expect(find.text('$i'), findsOneWidget);
        }

        // Tap question 4
        final q4Btn = find.byKey(const Key('palette_btn_3'));
        expect(q4Btn, findsOneWidget);
        await tester.tap(q4Btn);
        await tester.pumpAndSettle();

        expect(tappedIndex, equals(3));
      },
    );

    testWidgets('TimerPill formats time and displays normal/critical states', (
      tester,
    ) async {
      // Normal state: > 5 mins (e.g. 600s = 10:00)
      await tester.pumpWidget(_host(const TimerPill(remainingSeconds: 600)));
      await tester.pump();
      expect(find.text('10:00'), findsOneWidget);

      // Critical state: < 5 mins (e.g. 180s = 03:00)
      await tester.pumpWidget(_host(const TimerPill(remainingSeconds: 180)));
      await tester.pump();
      expect(find.text('03:00'), findsOneWidget);
    });

    testWidgets(
      'ResultMetricCard renders label, value, and celebratory badge',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const ResultMetricCard(
              label: 'Study Points',
              value: '+15 Pts',
              icon: Icons.stars_rounded,
              badgeText: 'Celebratory',
              isCelebratory: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Study Points'), findsOneWidget);
        expect(find.text('+15 Pts'), findsOneWidget);
        expect(find.text('Celebratory'), findsOneWidget);
      },
    );
  });
}
