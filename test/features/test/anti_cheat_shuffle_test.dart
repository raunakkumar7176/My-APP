// Anti-cheat two-level shuffle ("Shuffle Questions & Options").
//
// Contract under test:
//  1. the flags are persisted (settings mirror + best-effort column sync),
//  2. the attempt engine reads them per level (questions vs options),
//  3. seeding is per attempt — two students differ, one student's resume
//     does not,
//  4. shuffling is presentation-only: the stored answer keeps the master
//     option index.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/domain/creation_settings.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/state/attempt_controller.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';
import 'package:my_praperation/features/test/state/test_creation_controller.dart';

import '../../r4_restart/fakes.dart';

// ── engine harness ──

class _Answers implements AnswerRepository {
  @override
  Future<void> save(String attemptId, List<Answer> answers) async {}

  @override
  Future<List<Answer>> forAttempt(String attemptId) async => const [];
}

List<Question> _questions(int n) => [
  for (var i = 1; i <= n; i++)
    Question(
      id: 'q-$i',
      testId: 't-1',
      ordinal: i,
      question: 'Question $i',
      options: [
        for (var o = 0; o < 4; o++)
          QuestionOption(id: '', text: 'q${i}_o$o', index: o),
      ],
      difficulty: DifficultyLevel.easy,
      marks: 1,
      status: 'approved',
      questionType: QuestionType.mcqSingle,
    ),
];

Test _test({
  bool column = false,
  Map<String, dynamic>? settings,
}) => Test(
  id: 't-1',
  createdBy: 'u-1',
  title: 'T',
  status: TestStatus.published,
  testMode: 'group',
  shuffleQuestions: column,
  settings: settings,
);

AttemptController _controller({
  required bool column,
  Map<String, dynamic>? settings,
  String attemptId = 'a-1',
}) {
  final attempt = Attempt(
    id: attemptId,
    testId: 't-1',
    userId: 'u-1',
    status: AttemptStatus.inProgress,
    startedAt: DateTime(2026, 9, 16),
    deadlineAt: DateTime(2026, 9, 16, 1),
  );
  return AttemptController(
    attemptId: attemptId,
    testId: 't-1',
    attempts: FakeAttemptRepository()..rows.add(attempt),
    questions: FakeQuestionRepository()..byTest['t-1'] = _questions(6),
    answers: _Answers(),
    tests: FakeTestRepository()
      ..rows['t-1'] = _test(column: column, settings: settings),
    autosaveInterval: const Duration(hours: 1),
  );
}

TestCreationController _creator(FakeTestRepository tests) =>
    TestCreationController(
      tests: tests,
      questions: FakeQuestionRepository(),
      groups: FakeGroupRepository(),
      currentUserId: () => 'u-1',
    );

void main() {
  setUp(AttemptLaunchStore.clear);

  group('ShuffleSettings flags', () {
    test('question flag is the column OR the settings mirror', () {
      expect(ShuffleSettings.questionsFrom(column: true, settings: null), isTrue);
      expect(
        ShuffleSettings.questionsFrom(
          column: false,
          settings: {ShuffleSettings.questionsKey: true},
        ),
        isTrue,
        reason: 'the mirror alone must activate it (RPC not applied yet)',
      );
      expect(ShuffleSettings.questionsFrom(column: false, settings: null), isFalse);
      expect(
        ShuffleSettings.questionsFrom(
          column: true,
          settings: {ShuffleSettings.questionsKey: false},
        ),
        isTrue,
      );
    });

    test('option flag honors settings, else follows the question flag', () {
      expect(
        ShuffleSettings.optionsFrom(
          shuffleQuestions: true,
          settings: {ShuffleSettings.optionsKey: false},
        ),
        isFalse,
        reason: 'independent level: questions shuffled, options untouched',
      );
      expect(
        ShuffleSettings.optionsFrom(
          shuffleQuestions: false,
          settings: {ShuffleSettings.optionsKey: true},
        ),
        isTrue,
      );
      expect(
        ShuffleSettings.optionsFrom(shuffleQuestions: true, settings: null),
        isTrue,
        reason: 'rows written before the split keep both levels together',
      );
      expect(
        ShuffleSettings.optionsFrom(shuffleQuestions: false, settings: null),
        isFalse,
      );
    });

    test('applyTo writes both keys and never drops unrelated ones', () {
      const s = ShuffleSettings(questions: true, options: false);
      final out = s.applyTo({'test_kind': 'group', 'auto_submit': true});
      expect(out, {
        'test_kind': 'group',
        'auto_submit': true,
        ShuffleSettings.questionsKey: true,
        ShuffleSettings.optionsKey: false,
      });
      // Round trip through fromRow.
      final back = ShuffleSettings.fromRow(
        column: out[ShuffleSettings.questionsKey] as bool,
        settings: out,
      );
      expect(back, s);
    });

    test('kind defaults: side-by-side kinds ON, self-paced kinds OFF', () {
      expect(TestKind.group.defaultShuffle, const ShuffleSettings(questions: true, options: true));
      expect(
        TestKind.challengeWithFriends.defaultShuffle,
        const ShuffleSettings(questions: true, options: true),
      );
      for (final k in [TestKind.self, TestKind.practice, TestKind.quick, TestKind.sectional]) {
        expect(k.defaultShuffle, ShuffleSettings.defaults, reason: '$k');
      }
    });
  });

  group('creation persists the flags', () {
    test('new challenge saves both settings keys and syncs the column once', () async {
      final tests = FakeTestRepository();
      final c = _creator(tests)
        ..setTitle('C')
        ..setKind(TestKind.challengeWithFriends)
        ..joinCode = 'X1';

      expect(c.shuffle.questions, isTrue, reason: 'kind default is ON');

      final id = await c.saveDraft();
      final saved = tests.rows[id]!;
      expect(saved.settings![ShuffleSettings.questionsKey], isTrue);
      expect(saved.settings![ShuffleSettings.optionsKey], isTrue);
      expect(tests.shuffleCalls, ['$id:true']);
      expect(saved.shuffleQuestions, isTrue, reason: 'column synced too');
      // Saving again with no change must not hit the RPC again.
      await c.saveDraft();
      expect(tests.shuffleCalls, ['$id:true']);
      c.dispose();
    });

    test('a self-paced kind never writes the column when shuffle is off', () async {
      final tests = FakeTestRepository();
      final c = _creator(tests)..setTitle('P')..setKind(TestKind.practice);
      expect(c.shuffle, ShuffleSettings.defaults);

      final id = await c.saveDraft();
      expect(tests.shuffleCalls, isEmpty);
      expect(tests.rows[id]!.settings![ShuffleSettings.questionsKey], isFalse);
      expect(tests.rows[id]!.settings![ShuffleSettings.optionsKey], isFalse);
      c.dispose();
    });

    test('toggling off after a save writes the column false', () async {
      final tests = FakeTestRepository();
      final c = _creator(tests)
        ..setTitle('C')
        ..setKind(TestKind.challengeWithFriends)
        ..joinCode = 'X1';
      final id = await c.saveDraft();
      expect(tests.shuffleCalls, ['$id:true']);

      c.shuffle = const ShuffleSettings(questions: false, options: false);
      await c.saveDraft();
      expect(tests.shuffleCalls, ['$id:true', '$id:false']);
      expect(tests.rows[id]!.settings![ShuffleSettings.questionsKey], isFalse);
      c.dispose();
    });

    test('column sync failure is non-fatal: settings still activate it', () async {
      final tests = FakeTestRepository()
        ..failShuffleWith = const DataError(
          message: 'Could not find the function rpc_set_test_shuffle_questions',
        );
      final c = _creator(tests)
        ..setTitle('C')
        ..setKind(TestKind.challengeWithFriends)
        ..joinCode = 'X1';

      final id = await c.saveDraft(); // must NOT throw
      final saved = tests.rows[id]!;
      expect(saved.settings![ShuffleSettings.questionsKey], isTrue);
      expect(
        saved.shuffleQuestions,
        isFalse,
        reason: 'column stays stale until the migration lands',
      );
      c.dispose();
    });

    test('edit round trip restores the flags without rewriting them', () async {
      final tests = FakeTestRepository();
      tests.rows['t-9'] = const Test(
        id: 't-9',
        createdBy: 'u-1',
        title: 'E',
        status: TestStatus.draft,
        testMode: 'group',
        groupId: 'g-1',
        shuffleQuestions: false,
        settings: {
          ShuffleSettings.questionsKey: true,
          ShuffleSettings.optionsKey: false,
        },
      );
      final edit = TestCreationController(
        editingTestId: 't-9',
        tests: tests,
        questions: FakeQuestionRepository(),
        groups: FakeGroupRepository(),
        currentUserId: () => 'u-1',
      );
      await edit.loadForEdit();
      expect(edit.shuffle, const ShuffleSettings(questions: true, options: false));
      expect(tests.shuffleCalls, isEmpty, reason: 'loading never writes');

      await edit.saveDraft();
      expect(
        tests.shuffleCalls,
        ['t-9:true'],
        reason: 'column was false → synced once to match the restored value',
      );
      edit.dispose();
    });
  });

  group('attempt engine', () {
    test('settings mirror alone turns the shuffle on', () async {
      final c = _controller(
        column: false,
        settings: {
          ShuffleSettings.questionsKey: true,
          ShuffleSettings.optionsKey: true,
        },
      );
      await c.load();
      final ids = c.questions.map((q) => q.id).toList();
      expect(ids.toSet(), {for (var i = 1; i <= 6; i++) 'q-$i'});
      expect(
        ids,
        isNot([for (var i = 1; i <= 6; i++) 'q-$i']),
        reason: 'order differs from the master order',
      );
      c.dispose();
    });

    test('the two levels are independent', () async {
      final questionsOnly = _controller(
        column: true,
        settings: {ShuffleSettings.optionsKey: false},
      );
      await questionsOnly.load();
      final qOrder = questionsOnly.questions.map((q) => q.id).toList();
      expect(qOrder, isNot([for (var i = 1; i <= 6; i++) 'q-$i']));
      final displayed = questionsOnly.optionsFor(questionsOnly.questions.first);
      expect(
        displayed.map((o) => o.index).toList(),
        [0, 1, 2, 3],
        reason: 'options keep the master order',
      );
      questionsOnly.dispose();

      final optionsOnly = _controller(
        column: false,
        settings: {
          ShuffleSettings.questionsKey: false,
          ShuffleSettings.optionsKey: true,
        },
      );
      await optionsOnly.load();
      expect(
        optionsOnly.questions.map((q) => q.id).toList(),
        [for (var i = 1; i <= 6; i++) 'q-$i'],
        reason: 'questions keep the master order',
      );
      final shown = optionsOnly.optionsFor(optionsOnly.questions.first);
      expect(shown.map((o) => o.index).toSet(), {0, 1, 2, 3});
      expect(shown.map((o) => o.index).toList(), isNot([0, 1, 2, 3]));
      optionsOnly.dispose();
    });

    test('same attempt → same order, different attempt → different order', () async {
      final settings = {
        ShuffleSettings.questionsKey: true,
        ShuffleSettings.optionsKey: true,
      };

      Future<List<String>> orderFor(String attemptId) async {
        final c = _controller(column: true, settings: settings, attemptId: attemptId);
        await c.load();
        final ids = c.questions.map((q) => q.id).toList();
        final opts = c.optionsFor(c.questions.first).map((o) => o.index).toList();
        c.dispose();
        return [...ids, ...opts.map((i) => 'o$i')];
      }

      final first = await orderFor('attempt-alpha');
      final resume = await orderFor('attempt-alpha');
      final other = await orderFor('attempt-omega');

      expect(resume, first, reason: 'resume/crash recovery never re-shuffles');
      expect(
        other,
        isNot(first),
        reason: 'a second student sees a different order',
      );
    });

    test('display order never changes what is stored', () async {
      final c = _controller(
        column: true,
        settings: {ShuffleSettings.optionsKey: true},
      );
      await c.load();
      final q = c.questions.first;
      final shown = c.optionsFor(q);

      // Every master index survives the shuffle exactly once…
      expect(shown.map((o) => o.index).toSet(), {0, 1, 2, 3});
      expect(shown.length, 4);

      // …and selecting a displayed option stores its MASTER index.
      final picked = shown[2];
      c.selectOption(q.id, picked.index);
      expect(c.answerFor(q.id)!.toRpcJson()['selected_option'], picked.index);

      // The highlighted option on screen is found by master index, not slot.
      final restored = shown.singleWhere(
        (o) => o.index == c.answerFor(q.id)!.selectedOption,
      );
      expect(restored.text, picked.text);
      c.dispose();
    });
  });
}
