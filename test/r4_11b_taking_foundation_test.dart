// R4.11b — Practice/Quick taking-flow foundation (client only).
//
// Server semantics are untouched: deadlines still come from the server, and
// the "untimed" path only renders when the server itself returned no
// deadline for a Practice test (no start RPC in the repo does that yet).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/core/models/test_kind.dart';
import 'package:my_praperation/features/test/test_creation_screen.dart';
import 'package:my_praperation/features/test/test_taking_screen.dart';
import 'package:my_praperation/features/test/widgets/step_questions.dart';

Test _test(TestKind kind, {String mode = 'self'}) => Test(
      id: 't-1',
      createdBy: 'u-1',
      title: 'Algebra basics',
      status: TestStatus.published,
      testMode: mode,
      settings: {'test_kind': kind.dbValue},
    );

Attempt _attempt({DateTime? deadline}) => Attempt(
      id: 'a-1',
      testId: 't-1',
      userId: 'u-1',
      status: AttemptStatus.inProgress,
      startedAt: DateTime(2026, 9, 16, 10),
      deadlineAt: deadline,
    );

const _q = Question(
  id: 'q-1',
  testId: 't-1',
  ordinal: 1,
  question: '2 + 2 = ?',
  options: [QuestionOption(id: 'a', text: '3'), QuestionOption(id: 'b', text: '4')],
  difficulty: DifficultyLevel.easy,
  marks: 1,
  status: 'approved',
  questionType: QuestionType.mcqSingle,
);

Future<void> _pumpTaking(WidgetTester tester, Test test, Attempt attempt) async {
  await tester.pumpWidget(MaterialApp(
    home: TestTakingScreen(attempt: attempt, questions: const [_q], test: test),
  ));
  await tester.pump();
}

void main() {
  group('Quick / Sectional guidance', () {
    test('only Self-family kinds with guidance produce a hint', () {
      expect(TestCreationScreen.questionsGuidance('self', TestKind.quick),
          contains('5–10 questions'));
      expect(TestCreationScreen.questionsGuidance('self', TestKind.quick),
          contains('10 minutes'));
      expect(TestCreationScreen.questionsGuidance('self', TestKind.sectional),
          contains('Syllabus'));
      expect(TestCreationScreen.questionsGuidance('self', TestKind.practice),
          isNull);
      expect(TestCreationScreen.questionsGuidance('self', TestKind.self), isNull);
      expect(TestCreationScreen.questionsGuidance('live', TestKind.quick), isNull);
      expect(TestCreationScreen.questionsGuidance('group', TestKind.quick), isNull);
    });

    test('quick metadata constants are consistent with the guidance', () {
      expect(TestCreationScreen.quickTargetQuestionCount, 10);
      expect(TestCreationScreen.targetQuestionCountKey, 'target_question_count');
      expect(TestCreationScreen.quickDefaultDurationSec ~/ 60, 10);
    });

    testWidgets('StepQuestions shows the hint only when provided',
        (tester) async {
      Widget build(String? guidance) => MaterialApp(
            home: Scaffold(
              body: StepQuestions(
                questions: const [],
                serverQuestions: const [],
                onQuestionsChanged: (_) {},
                onServerQuestionDeleted: (_) {},
                onServerQuestionUpdated: (_) {},
                onNewQuestionFromServer: (_) {},
                guidance: guidance,
              ),
            ),
          );

      await tester.pumpWidget(build('Quick Test: aim for 5–10 questions'));
      expect(find.textContaining('aim for 5–10'), findsOneWidget);

      await tester.pumpWidget(build(null));
      expect(find.textContaining('aim for'), findsNothing);
    });
  });

  group('Taking screen kind awareness', () {
    testWidgets('timed Practice shows the timer and the kind label',
        (tester) async {
      await _pumpTaking(tester, _test(TestKind.practice),
          _attempt(deadline: DateTime.now().add(const Duration(hours: 1))));

      expect(find.text('Practice Test'), findsOneWidget);
      expect(find.text('Untimed'), findsNothing);
      expect(find.text('Timer Not Available'), findsNothing);

      await tester.pumpWidget(const SizedBox()); // dispose autosave timer
    });

    testWidgets('null deadline on a non-Practice test is still an error state',
        (tester) async {
      await _pumpTaking(tester, _test(TestKind.self), _attempt(deadline: null));
      expect(find.text('Timer Not Available'), findsOneWidget);
      expect(find.text('Untimed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('null deadline on Quick is still an error state (not untimed)',
        (tester) async {
      await _pumpTaking(tester, _test(TestKind.quick), _attempt(deadline: null));
      expect(find.text('Timer Not Available'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('null deadline on Practice renders the dormant untimed path',
        (tester) async {
      await _pumpTaking(
          tester, _test(TestKind.practice), _attempt(deadline: null));
      expect(find.text('Untimed'), findsOneWidget);
      expect(find.text('Timer Not Available'), findsNothing);
      expect(find.text('2 + 2 = ?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('kind never leaks into non-self modes', (tester) async {
      await _pumpTaking(tester, _test(TestKind.practice, mode: 'live'),
          _attempt(deadline: null));
      // A Challenge with Friends attempt without a deadline is an error,
      // regardless of any stray test_kind in settings.
      expect(find.text('Timer Not Available'), findsOneWidget);
      expect(find.text('Practice Test'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
