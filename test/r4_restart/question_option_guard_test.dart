// Question option guard (V1: >= 4 options, MCQ only). Client rules in
// QuestionDraft / PublishReadiness; the fake question repository mirrors the
// server guard in migrations/R4_QUESTION_OPTION_GUARD.sql (create >= 4,
// update validates the FINAL option set, correct_option bounds).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/domain/publish_readiness.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';

import 'fakes.dart';

QuestionDraft _draft(
  int n, {
  int? correct = 0,
  QuestionType type = QuestionType.mcqSingle,
}) => QuestionDraft(
  questionText: 'Q$n',
  questionType: type,
  options: [for (var i = 0; i < n; i++) QuestionOptionDraft(text: 'opt $i')],
  correctOptionIndex: correct,
);

Matcher _rejects(String contains) =>
    throwsA(predicate((e) => e is AppError && e.message.contains(contains)));

void main() {
  group('client: QuestionDraft', () {
    test('C. 4 options valid, 3 / 2 invalid; MCQ only', () {
      expect(_draft(4).isValid, isTrue);
      expect(_draft(5).isValid, isTrue);
      expect(_draft(3).isValid, isFalse);
      expect(_draft(2).isValid, isFalse);
      expect(QuestionDraft.minOptions, 4);
      for (final t in [
        QuestionType.trueFalse,
        QuestionType.mcqMultiple,
        QuestionType.integer,
        QuestionType.shortAnswer,
      ]) {
        expect(
          _draft(4, type: t).isValid,
          isFalse,
          reason: '$t is Coming soon',
        );
        expect(QuestionDraft.isSupportedType(t), isFalse);
      }
    });
    test('E. correct option must index an existing option', () {
      expect(_draft(4, correct: 4).isValid, isFalse);
      expect(_draft(4, correct: null).isValid, isFalse);
      expect(_draft(4, correct: 3).isValid, isTrue);
    });
    test('blank option text is invalid even with 4 slots', () {
      const d = QuestionDraft(
        questionText: 'Q',
        options: [
          QuestionOptionDraft(text: 'a'),
          QuestionOptionDraft(text: 'b'),
          QuestionOptionDraft(text: ''),
          QuestionOptionDraft(text: 'd'),
        ],
        correctOptionIndex: 0,
      );
      expect(d.isValid, isFalse);
    });
  });

  group('server mirror: create', () {
    late FakeQuestionRepository repo;
    setUp(() => repo = FakeQuestionRepository());

    test('A. 2 options rejected', () async {
      await expectLater(
        repo.create('t', _draft(2)),
        _rejects('at least 4 options'),
      );
    });
    test('B. 3 options rejected', () async {
      await expectLater(
        repo.create('t', _draft(3)),
        _rejects('at least 4 options'),
      );
    });
    test('C. 4 options accepted', () async {
      expect(await repo.create('t', _draft(4)), 'q-1');
    });
    test('D. 5 options accepted', () async {
      expect(await repo.create('t', _draft(5)), 'q-1');
    });
    test('E. invalid correct_option rejected', () async {
      await expectLater(
        repo.create('t', _draft(4, correct: 4)),
        _rejects('correct_option'),
      );
      await expectLater(
        repo.create('t', _draft(4, correct: -1)),
        _rejects('correct_option'),
      );
    });
  });

  group('server mirror: update validates the final option set', () {
    late FakeQuestionRepository repo;
    setUp(() async {
      repo = FakeQuestionRepository();
      await repo.create('t', _draft(4));
    });

    test('F. options → 2 rejected', () async {
      await expectLater(
        repo.update('q-1', _draft(2)),
        _rejects('at least 4 options'),
      );
    });
    test('G. options → 3 rejected', () async {
      await expectLater(
        repo.update('q-1', _draft(3)),
        _rejects('at least 4 options'),
      );
    });
    test('H. options → 4 accepted; 5 accepted', () async {
      await repo.update('q-1', _draft(4));
      await repo.update('q-1', _draft(5, correct: 4));
    });
    test('I. text-only update with valid stored options accepted', () async {
      await repo.update(
        'q-1',
        const QuestionDraft(questionText: 'Renamed', options: []),
      );
    });
    test('correct_option checked against the final set', () async {
      await expectLater(
        repo.update('q-1', _draft(4, correct: 4)),
        _rejects('correct_option'),
      );
    });
  });

  group('J. legacy < 4-option rows are never modified silently', () {
    test(
      'a stored 2-option question stays as-is; text-only update is rejected',
      () async {
        final repo = FakeQuestionRepository();
        repo.byTest['t'] = [
          const Question(
            id: 'legacy',
            testId: 't',
            ordinal: 1,
            question: 'Old TF',
            options: [
              QuestionOption(id: 'a', text: 'True'),
              QuestionOption(id: 'b', text: 'False'),
            ],
            difficulty: DifficultyLevel.easy,
            marks: 1,
            status: 'approved',
            questionType: QuestionType.trueFalse,
          ),
        ];
        await expectLater(
          repo.update(
            'legacy',
            const QuestionDraft(questionText: 'Renamed', options: []),
          ),
          _rejects('at least 4 options'),
        );
        expect(repo.byTest['t']!.single.options!.length, 2); // untouched
      },
    );

    test(
      'publish readiness flags server questions with fewer than 4 options',
      () {
        final items = PublishReadiness.evaluate(
          const PublishReadinessInput(
            title: 'T',
            kind: TestKind.self,
            groupId: null,
            durationSec: 600,
            marksPerQuestion: 1,
            startsAt: null,
            endsAt: null,
            serverQuestionStatuses: ['approved', 'approved'],
            localDraftValidity: [],
            serverQuestionOptionCounts: [4, 2],
          ),
        );
        final item = items.firstWhere((i) => i.label.contains('4 options'));
        expect(item.isValid, isFalse);
        expect(
          item.reason,
          contains('1 question(s) have fewer than 4 options'),
        );
        expect(
          PublishReadiness.isReady(
            const PublishReadinessInput(
              title: 'T',
              kind: TestKind.self,
              groupId: null,
              durationSec: 600,
              marksPerQuestion: 1,
              startsAt: null,
              endsAt: null,
              serverQuestionStatuses: ['approved'],
              localDraftValidity: [],
              serverQuestionOptionCounts: [4],
            ),
          ),
          isTrue,
        );
      },
    );
  });
}
