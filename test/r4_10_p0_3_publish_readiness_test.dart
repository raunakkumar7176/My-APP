// P0-3: publish readiness must reflect question approval immediately.
//
// Root cause: Question is immutable and StepReview had no way to hand the new
// status back to the parent, so `_serverQuestions` (and therefore the publish
// gate) stayed at the pre-approval status until the screen was reopened.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/services/test_service.dart';
import 'package:my_praperation/features/test/widgets/step_review.dart';

Question _q(String id, {String status = 'pending_review', int ordinal = 1}) =>
    Question(
      id: id,
      testId: 't1',
      ordinal: ordinal,
      question: 'Question $id',
      options: const [
        QuestionOption(id: 'a', text: 'A'),
        QuestionOption(id: 'b', text: 'B'),
      ],
      difficulty: DifficultyLevel.easy,
      marks: 1,
      status: status,
      questionType: QuestionType.mcqSingle,
    );

/// Minimal stand-in for _TestCreationScreenState: owns the server question
/// list and applies the same replacement `_onServerQuestionUpdated` does.
class _Harness extends StatefulWidget {
  const _Harness({required this.initial});
  final List<Question> initial;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final List<Question> serverQuestions = List.of(widget.initial);

  bool get allApproved => serverQuestions.every((q) => q.status == 'approved');

  void onServerQuestionUpdated(Question updated) {
    setState(() {
      final i = serverQuestions.indexWhere((q) => q.id == updated.id);
      if (i != -1) serverQuestions[i] = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StepReview(
            title: 'T',
            description: '',
            durationSec: 600,
            marksPerQuestion: 1,
            negativeMarks: 0,
            testMode: 'self',
            startsAt: null,
            endsAt: null,
            maxParticipants: null,
            allowLateJoin: false,
            accessCode: null,
            joinCode: null,
            questions: const [],
            serverQuestions: serverQuestions,
            syllabusNodeIds: const [],
            serverSyllabusNodeIds: const [],
            onServerQuestionUpdated: onServerQuestionUpdated,
          ),
        ),
      ),
    );
  }
}

void main() {
  group('P0-3 Question.copyWith', () {
    test('changes only status and never introduces answer-key data', () {
      final original = _q('q1');
      final approved = original.copyWith(status: 'approved');

      expect(approved.status, 'approved');
      expect(approved.id, original.id);
      expect(approved.testId, original.testId);
      expect(approved.ordinal, original.ordinal);
      expect(approved.question, original.question);
      expect(approved.options, original.options);
      expect(approved.marks, original.marks);
      expect(approved.questionType, original.questionType);
      expect(approved.toJson().containsKey('correct_option'), isFalse);
      // Original is untouched (immutability preserved).
      expect(original.status, 'pending_review');
    });

    test('copyWith with no arguments is an equal copy', () {
      final original = _q('q1', status: 'approved');
      expect(original.copyWith().status, 'approved');
    });
  });

  group('P0-3 parent readiness after approval', () {
    test('replacing the approved question flips the publish gate', () {
      final list = [_q('q1'), _q('q2', ordinal: 2)];
      bool allApproved() => list.every((q) => q.status == 'approved');
      expect(allApproved(), isFalse);

      // Same mutation as _TestCreationScreenState._onServerQuestionUpdated.
      void update(Question u) {
        final i = list.indexWhere((q) => q.id == u.id);
        if (i != -1) list[i] = u;
      }

      update(list[0].copyWith(status: 'approved'));
      expect(allApproved(), isFalse);
      update(list[1].copyWith(status: 'approved'));
      expect(allApproved(), isTrue);
      expect(list.map((q) => q.id), ['q1', 'q2']); // order preserved
    });

    testWidgets('StepReview re-renders from the parent list after approval',
        (tester) async {
      await tester.pumpWidget(_Harness(initial: [_q('q1'), _q('q2', ordinal: 2)]));

      expect(find.text('Pending Review'), findsNWidgets(2));
      expect(find.text('Approve All'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Approve'), findsNWidgets(2));

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      state.onServerQuestionUpdated(_q('q1', status: 'approved'));
      await tester.pump();

      expect(find.text('Pending Review'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Approve'), findsOneWidget);
      expect(state.allApproved, isFalse);

      state.onServerQuestionUpdated(_q('q2', status: 'approved', ordinal: 2));
      await tester.pump();

      expect(find.text('Pending Review'), findsNothing);
      expect(find.text('Approve All'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Approve'), findsNothing);
      expect(state.allApproved, isTrue);
    });
  });

  group('P0-3 publish error visibility', () {
    test('live rpc_publish_test approval rejection is not hidden as generic',
        () {
      const live =
          'VALIDATION_ERROR: Test must have at least one approved question to publish';
      expect(TestService.mapPublishError(live), contains('Approve'));
      expect(TestService.mapPublishError(live),
          isNot('Something went wrong. Please try again.'));
      expect(TestService.mapPublishError(live),
          isNot('Add at least one question before publishing.'));
    });
  });
}
