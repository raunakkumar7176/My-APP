// P1-1: editing a server question must not force a blind re-pick of the
// correct option (the client never receives the answer key), and a picked
// option must be carried through to the update call instead of dropped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/widgets/question_editor.dart';

QuestionDraft _serverDraft() => const QuestionDraft(
      id: 'server-q-1', // id present ⇒ exists on server
      questionText: 'Capital of France?',
      questionType: QuestionType.mcqSingle,
      options: [
        QuestionOptionDraft(id: 'o1', text: 'Paris'),
        QuestionOptionDraft(id: 'o2', text: 'Rome'),
        QuestionOptionDraft(id: 'o3', text: 'Berlin'),
        QuestionOptionDraft(id: 'o4', text: 'Madrid'),
      ],
      correctOptionIndex: null, // never exposed by get_test_questions_safe
      subjectId: 'subj-1',
      topicNodeId: 'node-1',
      language: 'en',
      marks: 2,
    );

void main() {
  group('P1-1 QuestionEditor on a server question', () {
    testWidgets('saves with correct option left unselected (keep stored key)',
        (tester) async {
      QuestionDraft? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QuestionEditor(initial: _serverDraft(), onSave: (d) => saved = d),
        ),
      ));

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.id, 'server-q-1');
      expect(saved!.correctOptionIndex, isNull, reason: 'null ⇒ omitted ⇒ unchanged');
      // Non-editable fields are carried through, not dropped.
      expect(saved!.subjectId, 'subj-1');
      expect(saved!.topicNodeId, 'node-1');
      expect(saved!.language, 'en');
      expect(saved!.options.map((o) => o.id), ['o1', 'o2', 'o3', 'o4']);
    });

    testWidgets('a newly picked correct option is kept in the saved draft',
        (tester) async {
      QuestionDraft? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QuestionEditor(initial: _serverDraft(), onSave: (d) => saved = d),
        ),
      ));

      await tester.tap(find.byType(Radio<int>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.correctOptionIndex, 1);
    });

    testWidgets('a brand-new MCQ draft still requires a correct option',
        (tester) async {
      QuestionDraft? saved;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QuestionEditor(
            initial: const QuestionDraft(
              // no id ⇒ local draft
              questionText: 'New?',
              options: [
                QuestionOptionDraft(text: 'A'),
                QuestionOptionDraft(text: 'B'),
                QuestionOptionDraft(text: 'C'),
                QuestionOptionDraft(text: 'D'),
              ],
            ),
            onSave: (d) => saved = d,
          ),
        ),
      ));

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
    });
  });
}
