// P1-6: typed (numeric / short-answer) answers.
//
// Before: the typed text was written only to selected_option_id, the input
// had no initial value (text vanished when paging away and back) and the
// read-only view only looked at text_answer, so it never showed the answer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/logging/app_logger.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/widgets/question_card.dart';

const _typed = Question(
  id: 'q-num',
  testId: 't1',
  ordinal: 1,
  question: 'What is 6 × 7?',
  options: null,
  difficulty: DifficultyLevel.easy,
  marks: 1,
  status: 'approved',
  questionType: QuestionType.integer,
);

Widget _card({
  Answer? answer,
  bool interactive = true,
  ValueChanged<String?>? onText,
  ValueChanged<String?>? onOption,
}) {
  return MaterialApp(
    home: Scaffold(
      body: QuestionCard(
        question: _typed,
        shuffledOptions: const [],
        answer: answer,
        questionNumber: 1,
        totalQuestions: 1,
        onOptionSelected: onOption ?? (_) {},
        onTextAnswerChanged: onText,
        onMarkReview: () {},
        interactive: interactive,
      ),
    ),
  );
}

void main() {
  group('P1-6 QuestionCard typed answers', () {
    testWidgets('input is seeded with the stored text_answer', (tester) async {
      await tester.pumpWidget(_card(
        answer: const Answer(
            attemptId: 'a', questionId: 'q-num', textAnswer: '42'),
      ));
      expect(find.widgetWithText(TextFormField, '42'), findsOneWidget);
    });

    testWidgets('input falls back to selected_option_id for older answers',
        (tester) async {
      await tester.pumpWidget(_card(
        answer: const Answer(
            attemptId: 'a', questionId: 'q-num', selectedOptionId: '42'),
      ));
      expect(find.widgetWithText(TextFormField, '42'), findsOneWidget);
    });

    testWidgets('typing routes to onTextAnswerChanged, empty clears to null',
        (tester) async {
      final received = <String?>[];
      var optionCalls = 0;
      await tester.pumpWidget(_card(
        onText: received.add,
        onOption: (_) => optionCalls++,
      ));

      await tester.enterText(find.byType(TextFormField), '42');
      await tester.enterText(find.byType(TextFormField), '');

      expect(received, ['42', null]);
      expect(optionCalls, 0);
    });

    testWidgets('without onTextAnswerChanged it still uses onOptionSelected',
        (tester) async {
      final received = <String?>[];
      await tester.pumpWidget(_card(onOption: received.add));
      await tester.enterText(find.byType(TextFormField), '7');
      expect(received, ['7']);
    });

    testWidgets('read-only view shows text_answer', (tester) async {
      await tester.pumpWidget(_card(
        interactive: false,
        answer: const Answer(
            attemptId: 'a', questionId: 'q-num', textAnswer: '42'),
      ));
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('read-only view shows legacy selected_option_id text',
        (tester) async {
      await tester.pumpWidget(_card(
        interactive: false,
        answer: const Answer(
            attemptId: 'a', questionId: 'q-num', selectedOptionId: '42'),
      ));
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('read-only view shows nothing when unanswered',
        (tester) async {
      await tester.pumpWidget(_card(interactive: false, answer: null));
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Type your answer here...'), findsNothing);
    });
  });

  group('AppLogger.describeShape (RPC contract diagnostics)', () {
    test('describes maps by sorted keys only, never values', () {
      final s = AppLogger.describeShape({
        'status': 'approved',
        'id': 'secret-id',
        'correct_option': 2,
      });
      expect(s, 'Map(keys=[correct_option, id, status])');
      expect(s, isNot(contains('secret-id')));
      expect(s, isNot(contains('approved')));
    });

    test('describes lists by length and first element shape', () {
      expect(AppLogger.describeShape([]), 'List(empty)');
      expect(
        AppLogger.describeShape([
          {'b': 1, 'a': 2},
          {'c': 3},
        ]),
        'List(len=2) first=Map(keys=[a, b])',
      );
    });

    test('describes scalars by type and null as null', () {
      expect(AppLogger.describeShape(null), 'null');
      expect(AppLogger.describeShape('abc'), 'String');
    });
  });
}
