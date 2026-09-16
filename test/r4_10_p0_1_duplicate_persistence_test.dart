// P0-1: duplicate test / question / syllabus persistence on repeated
// Save Draft → Continue Editing → Save/Publish, and partial-failure retries.
//
// These exercise the static persistence helpers on TestCreationScreen with
// injected fakes — no Supabase client involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/test_creation_screen.dart';

QuestionDraft _draft(String text) => QuestionDraft(
      questionText: text,
      questionType: QuestionType.mcqSingle,
      options: const [
        QuestionOptionDraft(text: 'A'),
        QuestionOptionDraft(text: 'B'),
      ],
      correctOptionIndex: 0,
      difficulty: DifficultyLevel.easy,
      marks: 1,
    );

void main() {
  group('P0-1 persistDraftQuestions', () {
    test('removes every draft from the list once all creates succeed',
        () async {
      final drafts = [_draft('q1'), _draft('q2'), _draft('q3')];
      final created = <String>[];

      await TestCreationScreen.persistDraftQuestions(
        drafts,
        create: (d) async {
          created.add(d.questionText);
          return 'id-${d.questionText}';
        },
      );

      expect(created, ['q1', 'q2', 'q3']);
      expect(drafts, isEmpty);
    });

    test('a second save after success creates nothing', () async {
      final drafts = [_draft('q1'), _draft('q2')];
      var calls = 0;
      Future<String> create(QuestionDraft d) async {
        calls++;
        return 'id-$calls';
      }

      await TestCreationScreen.persistDraftQuestions(drafts, create: create);
      await TestCreationScreen.persistDraftQuestions(drafts, create: create);

      expect(calls, 2);
      expect(drafts, isEmpty);
    });

    test('partial failure: created drafts are dropped, failing one kept, '
        'retry only re-sends the unsaved ones', () async {
      final drafts = [
        _draft('q1'),
        _draft('q2'),
        _draft('q3'),
        _draft('q4'),
        _draft('q5'),
      ];
      final sent = <String>[];
      var failOnce = true;

      Future<String> create(QuestionDraft d) async {
        sent.add(d.questionText);
        if (d.questionText == 'q3' && failOnce) {
          failOnce = false;
          throw Exception('rpc_create_question failed');
        }
        return 'id-${d.questionText}';
      }

      await expectLater(
        TestCreationScreen.persistDraftQuestions(drafts, create: create),
        throwsException,
      );
      expect(sent, ['q1', 'q2', 'q3']);
      expect(drafts.map((d) => d.questionText), ['q3', 'q4', 'q5']);

      // Retry: q1/q2 must NOT be created again.
      await TestCreationScreen.persistDraftQuestions(drafts, create: create);
      expect(sent, ['q1', 'q2', 'q3', 'q3', 'q4', 'q5']);
      expect(drafts, isEmpty);
    });

    test('approve is called with the created id; its failure surfaces but '
        'the already-persisted question is not re-created on retry', () async {
      final drafts = [_draft('q1'), _draft('q2')];
      final approved = <String>[];
      final created = <String>[];
      var failOnce = true;

      Future<String> create(QuestionDraft d) async {
        created.add(d.questionText);
        return 'id-${d.questionText}';
      }

      Future<void> approve(String id) async {
        approved.add(id);
        if (id == 'id-q1' && failOnce) {
          failOnce = false;
          throw Exception('approve failed');
        }
      }

      // q1 is created, its approval fails → surfaced as an AppError so the
      // user is told to approve from Review instead of hitting a generic
      // publish rejection later.
      await expectLater(
        TestCreationScreen.persistDraftQuestions(drafts,
            create: create, approve: approve),
        throwsA(isA<AppError>()),
      );
      expect(created, ['q1']);
      expect(drafts.map((d) => d.questionText), ['q2']);

      // Retry: q1 must not be created again.
      await TestCreationScreen.persistDraftQuestions(drafts,
          create: create, approve: approve);
      expect(created, ['q1', 'q2']);
      expect(approved, ['id-q1', 'id-q2']);
      expect(drafts, isEmpty);
    });

    test('does not mutate the list while iterating (iterates over a copy)',
        () async {
      final drafts = [_draft('q1'), _draft('q2'), _draft('q3')];
      final seen = <String>[];
      await TestCreationScreen.persistDraftQuestions(
        drafts,
        create: (d) async {
          seen.add(d.questionText);
          return d.questionText;
        },
      );
      // With in-place removal during a forward index loop, q2 would be skipped.
      expect(seen, ['q1', 'q2', 'q3']);
    });
  });

  group('P0-1 persistSyllabusSelection', () {
    test('adds only nodes not yet on the server and merges them', () async {
      final local = ['n1', 'n2', 'n3'];
      final server = ['n1'];
      final added = <String>[];

      await TestCreationScreen.persistSyllabusSelection(
        local: local,
        server: server,
        add: (n) async => added.add(n),
        remove: (_) async => fail('nothing should be removed'),
      );

      expect(added, ['n2', 'n3']);
      expect(server, ['n1', 'n2', 'n3']);
    });

    test('a second save after success sends nothing', () async {
      final local = ['n1', 'n2'];
      final server = <String>[];
      var adds = 0;
      var removes = 0;

      Future<void> add(String _) async => adds++;
      Future<void> remove(String _) async => removes++;

      await TestCreationScreen.persistSyllabusSelection(
          local: local, server: server, add: add, remove: remove);
      await TestCreationScreen.persistSyllabusSelection(
          local: local, server: server, add: add, remove: remove);

      expect(adds, 2);
      expect(removes, 0);
    });

    test('removes deselected nodes and drops them from server list',
        () async {
      final local = ['n2'];
      final server = ['n1', 'n2'];
      final removed = <String>[];

      await TestCreationScreen.persistSyllabusSelection(
        local: local,
        server: server,
        add: (_) async => fail('nothing should be added'),
        remove: (n) async => removed.add(n),
      );

      expect(removed, ['n1']);
      expect(server, ['n2']);
    });

    test('partial failure on add: earlier node merged, failing node retried '
        'alone', () async {
      final local = ['n1', 'n2', 'n3'];
      final server = <String>[];
      final sent = <String>[];
      var failOnce = true;

      Future<void> add(String n) async {
        sent.add(n);
        if (n == 'n2' && failOnce) {
          failOnce = false;
          throw Exception('rpc_add_test_syllabus failed');
        }
      }

      await expectLater(
        TestCreationScreen.persistSyllabusSelection(
            local: local, server: server, add: add, remove: (_) async {}),
        throwsException,
      );
      expect(server, ['n1']);

      await TestCreationScreen.persistSyllabusSelection(
          local: local, server: server, add: add, remove: (_) async {});
      expect(sent, ['n1', 'n2', 'n2', 'n3']);
      expect(server, ['n1', 'n2', 'n3']);
    });
  });
}
