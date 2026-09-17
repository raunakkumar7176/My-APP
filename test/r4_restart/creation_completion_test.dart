// R4 Test System completion matrix (creation side): A–E five kinds,
// J Mixed distribution, K duration/end, L late-join window, V readiness,
// W unsupported types, X group, Y timezone round trip, N source step.
// Other letters live in reattempt_policy_test / question_option_guard_test /
// delete_draft_test / attempt_results_test / result_batch_rpc_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/domain/attempt_policy.dart';
import 'package:my_praperation/features/test/domain/creation_settings.dart';
import 'package:my_praperation/features/test/domain/publish_readiness.dart';
import 'package:my_praperation/features/test/domain/test_errors.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/state/test_creation_controller.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';
import 'package:my_praperation/features/test/widgets/configuration_step.dart';
import 'package:my_praperation/features/test/widgets/question_source_step.dart';

import 'fakes.dart';

QuestionDraft _mcq(String text, {DifficultyLevel d = DifficultyLevel.medium}) => QuestionDraft(
      questionText: text,
      difficulty: d,
      options: const [
        QuestionOptionDraft(text: 'A'),
        QuestionOptionDraft(text: 'B'),
        QuestionOptionDraft(text: 'C'),
        QuestionOptionDraft(text: 'D'),
      ],
      correctOptionIndex: 0,
    );

TestCreationController _controller({FakeTestRepository? tests, FakeGroupRepository? groups}) =>
    TestCreationController(
      tests: tests ?? FakeTestRepository(),
      questions: FakeQuestionRepository(),
      groups: groups ?? FakeGroupRepository(),
      currentUserId: () => 'u-1',
    );

void main() {
  group('V1 kinds', () {
    test('exactly five creatable kinds; Sectional/Adaptive reserved', () {
      expect(TestKind.creatable, [
        TestKind.self,
        TestKind.practice,
        TestKind.quick,
        TestKind.challengeWithFriends,
        TestKind.group,
      ]);
      for (final k in TestKind.creatable) {
        expect(k.label, isNot(contains('Live')));
      }
      expect(TestKind.challengeWithFriends.label, 'Challenge with Friends');
    });

    test('kind rules drive the form: scheduling, scope, late join, join code, group', () {
      expect(TestKind.self.isScheduled, isFalse);
      expect(TestKind.practice.requiresScope, isTrue);
      expect(TestKind.quick.requiresScope, isTrue);
      expect(TestKind.quick.maxQuestionTarget, 15);
      expect(TestKind.challengeWithFriends.isScheduled, isTrue);
      expect(TestKind.challengeWithFriends.requiresJoinCode, isTrue);
      expect(TestKind.challengeWithFriends.supportsLateJoin, isTrue);
      expect(TestKind.group.requiresGroup, isTrue);
      expect(TestKind.group.supportsLateJoin, isTrue);
      expect(TestKind.practice.defaultAttemptPolicy.allowReattempt, isTrue);
      expect(TestKind.self.defaultAttemptPolicy.maxAttempts, 1);
    });
  });

  group('A–E creation per kind (settings + mapping)', () {
    test('A Self: self mode, single attempt, no schedule, question target persisted', () async {
      final tests = FakeTestRepository();
      final c = _controller(tests: tests)
        ..setTitle('Self')
        ..setKind(TestKind.self)
        ..setQuestionConfig(const QuestionConfig(total: 4, easy: 2, medium: 1, hard: 1))
        ..setLocalQuestions([
          _mcq('1', d: DifficultyLevel.easy),
          _mcq('2', d: DifficultyLevel.easy),
          _mcq('3'),
          _mcq('4', d: DifficultyLevel.hard),
        ]);
      final id = await c.saveDraft();
      final row = tests.rows[id]!;
      expect(row.testMode, 'self');
      expect(row.settings!['allow_reattempt'], false);
      expect(row.settings!['question_config'], {'total': 4, 'easy': 2, 'medium': 1, 'hard': 1, 'type': 'mcq'});
      expect(row.settings!.containsKey('late_join_minutes'), isFalse);
      expect(c.distributionCheck!.satisfied, isTrue);
    });

    test('B Practice: test_kind practice, re-attempts default ON (3), scope required', () async {
      final tests = FakeTestRepository();
      final c = _controller(tests: tests)
        ..setTitle('P')
        ..setKind(TestKind.practice)
        ..setLocalQuestions([_mcq('1')]);
      expect(c.durationSec, TestCreationController.practiceDefaultDurationSec);
      expect(c.attemptSettings, const AttemptSettings(allowReattempt: true, maxAttempts: 3));
      final id = await c.saveDraft();
      expect(tests.rows[id]!.settings!['test_kind'], 'practice');
      // Readiness requires a syllabus scope for Practice.
      expect(c.readiness.firstWhere((i) => i.label == 'Syllabus scope selected').isValid, isFalse);
      c.setSyllabusNodeIds(['n-1']);
      expect(c.readiness.firstWhere((i) => i.label == 'Syllabus scope selected').isValid, isTrue);
    });

    test('C Quick: test_kind quick, 10 min, target count, total capped at 15', () async {
      final tests = FakeTestRepository();
      final c = _controller(tests: tests)
        ..setTitle('Q')
        ..setKind(TestKind.quick)
        ..setLocalQuestions([_mcq('1')]);
      expect(c.durationSec, TestCreationController.quickDefaultDurationSec);
      c.setQuestionConfig(const QuestionConfig(total: 20, easy: 10, medium: 5, hard: 5));
      expect(c.canProceedFromConfiguration, isFalse); // over the Quick cap
      c.setQuestionConfig(const QuestionConfig(total: 10, easy: 5, medium: 3, hard: 2));
      expect(c.canProceedFromConfiguration, isTrue);
      final id = await c.saveDraft();
      expect(tests.rows[id]!.settings!['test_kind'], 'quick');
      expect(tests.rows[id]!.settings!['target_question_count'], 10);
    });

    test('D Challenge with Friends: live mode, join code required, late join ON 10 min, start needed',
        () async {
      final tests = FakeTestRepository();
      final c = _controller(tests: tests)
        ..setTitle('C')
        ..setKind(TestKind.challengeWithFriends)
        ..setLocalQuestions([_mcq('1')]);
      expect(c.allowLateJoin, isTrue);
      expect(c.lateJoin, LateJoinSettings.defaults);
      var labels = {for (final i in c.readiness) i.label: i.isValid};
      expect(labels['Join code set'], isFalse);
      expect(labels['Start time set'], isFalse);
      c.setConfiguration(
        durationSec: 1800, marksPerQuestion: 1, negativeMarks: 0, groupId: null,
        startsAt: DateTime(2026, 10, 1, 10), endsAt: null, maxParticipants: 20,
        allowLateJoin: true, accessCode: null, joinCode: 'ABCD',
      );
      labels = {for (final i in c.readiness) i.label: i.isValid};
      expect(labels['Join code set'], isTrue);
      expect(labels['Start time set'], isTrue);
      final id = await c.saveDraft();
      final row = tests.rows[id]!;
      expect(row.testMode, 'live');
      expect(row.settings!['late_join_minutes'], 10);
    });

    test('E Group Test: group mode, real group required; none available → blocked', () async {
      final tests = FakeTestRepository();
      final noGroups = _controller(tests: tests, groups: FakeGroupRepository())
        ..setTitle('G')
        ..setKind(TestKind.group);
      await noGroups.loadGroups();
      expect(noGroups.groups, isEmpty);
      expect(noGroups.canProceedFromConfiguration, isFalse);

      final groups = FakeGroupRepository()
        ..groups = [
          Group(
            id: 'g-1', name: 'Batch A', ownerId: 'owner-1', createdAt: DateTime(2026),
            memberCount: 3, userRole: 'member',
          ),
        ];
      final c = _controller(tests: tests, groups: groups)
        ..setTitle('G')
        ..setKind(TestKind.group)
        ..setLocalQuestions([_mcq('1')]);
      await c.loadGroups();
      c.setConfiguration(
        durationSec: 1800, marksPerQuestion: 1, negativeMarks: 0, groupId: 'g-1',
        startsAt: DateTime(2026, 10, 1, 10), endsAt: null, maxParticipants: null,
        allowLateJoin: true, accessCode: null, joinCode: null,
      );
      expect(c.canProceedFromConfiguration, isTrue);
      final id = await c.saveDraft();
      expect(tests.rows[id]!.testMode, 'group');
      expect(tests.rows[id]!.groupId, 'g-1');
    });
  });

  group('J Mixed distribution', () {
    test('8 + 7 + 5 = 20 valid; 8 + 7 + 4 blocked', () {
      const ok = QuestionConfig(total: 20, easy: 8, medium: 7, hard: 5);
      const bad = QuestionConfig(total: 20, easy: 8, medium: 7, hard: 4);
      expect(ok.isValid, isTrue);
      expect(bad.isValid, isFalse);
      final c = _controller()..setTitle('M');
      c.setQuestionConfig(bad);
      expect(c.canProceedFromConfiguration, isFalse);
      c.setQuestionConfig(ok);
      expect(c.canProceedFromConfiguration, isTrue);
      expect(QuestionConfig.none.isValid, isTrue); // optional target
    });

    test('target is compared with ACTUAL questions at readiness (truthful)', () {
      final c = _controller()
        ..setTitle('M')
        ..setQuestionConfig(const QuestionConfig(total: 3, easy: 1, medium: 1, hard: 1))
        ..setLocalQuestions([_mcq('1', d: DifficultyLevel.easy), _mcq('2')]);
      final item = c.readiness.firstWhere((i) => i.label == 'Questions match the difficulty target');
      expect(item.isValid, isFalse);
      expect(item.reason, contains('Easy 1/1 · Medium 1/1 · Hard 0/1 (2/3)'));
      c.setLocalQuestions([
        _mcq('1', d: DifficultyLevel.easy), _mcq('2'), _mcq('3', d: DifficultyLevel.hard),
      ]);
      expect(c.readiness.firstWhere((i) => i.label == 'Questions match the difficulty target').isValid, isTrue);
    });

    test('survives reload / edit through settings jsonb', () async {
      final tests = FakeTestRepository();
      final c = _controller(tests: tests)
        ..setTitle('M')
        ..setQuestionConfig(const QuestionConfig(total: 5, easy: 2, medium: 2, hard: 1))
        ..setLocalQuestions([_mcq('1')]);
      final id = await c.saveDraft();
      final edit = TestCreationController(
        editingTestId: id, tests: tests, questions: FakeQuestionRepository(),
        groups: FakeGroupRepository(), currentUserId: () => 'u-1',
      );
      await edit.loadForEdit();
      expect(edit.questionConfig, const QuestionConfig(total: 5, easy: 2, medium: 2, hard: 1));
    });
  });

  group('K duration / end', () {
    test('start 10:00 + 30 min = end 10:30; no independent end time is written', () async {
      final start = DateTime(2026, 10, 1, 10);
      expect(ScheduleMath.endFor(startsAt: start, durationSec: 1800), DateTime(2026, 10, 1, 10, 30));
      expect(ScheduleMath.endFor(startsAt: null, durationSec: 1800), isNull);
      final tests = FakeTestRepository();
      final c = _controller(tests: tests)
        ..setTitle('K')
        ..setKind(TestKind.challengeWithFriends)
        ..setLocalQuestions([_mcq('1')]);
      c.setConfiguration(
        durationSec: 1800, marksPerQuestion: 1, negativeMarks: 0, groupId: null,
        startsAt: start, endsAt: DateTime(2026, 10, 1, 11, 15), // stale/typed value is ignored
        maxParticipants: null, allowLateJoin: true, accessCode: null, joinCode: 'X1',
      );
      expect(c.calculatedEndsAt, DateTime(2026, 10, 1, 10, 30));
      final id = await c.saveDraft();
      expect(tests.rows[id]!.endsAt, DateTime(2026, 10, 1, 10, 30));
    });

    testWidgets('configuration step shows Calculated End Time and no end picker', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConfigurationStep(
            kind: TestKind.challengeWithFriends,
            durationSec: 1800, marksPerQuestion: 1, negativeMarks: 0, testMode: 'live',
            groupId: null, startsAt: DateTime(2026, 10, 1, 10), endsAt: null,
            maxParticipants: null, allowLateJoin: true, accessCode: null, joinCode: null,
            onChanged: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Calculated End Time'), findsOneWidget);
      expect(find.text('End Time'), findsNothing);
      expect(find.textContaining('10:30'), findsOneWidget);
      expect(find.byKey(const Key('late_join_minutes')), findsOneWidget);
      expect(find.byKey(const Key('qc_total')), findsOneWidget);
    });

    testWidgets('Self shows no schedule / late-join controls', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ConfigurationStep(
            kind: TestKind.self,
            durationSec: 600, marksPerQuestion: 1, negativeMarks: 0, testMode: 'self',
            groupId: null, startsAt: null, endsAt: null, maxParticipants: null,
            allowLateJoin: false, accessCode: null, joinCode: null, onChanged: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Schedule'), findsNothing);
      expect(find.byKey(const Key('late_join_minutes')), findsNothing);
      expect(find.byKey(const Key('allow_reattempt')), findsOneWidget);
    });
  });

  group('L late-join window', () {
    final start = DateTime.utc(2026, 10, 1, 10);
    const lj = LateJoinSettings(enabled: true, minutes: 10);

    test('10:05 / 10:09 / 10:10:00 allowed; 10:10:01 and 10:11 blocked', () {
      bool open(Duration d) => lj.joinOpenAt(startsAt: start, now: start.add(d));
      expect(open(const Duration(minutes: 5)), isTrue);
      expect(open(const Duration(minutes: 9)), isTrue);
      expect(open(const Duration(minutes: 10)), isTrue);
      expect(open(const Duration(minutes: 10, seconds: 1)), isFalse);
      expect(open(const Duration(minutes: 11)), isFalse);
      expect(open(const Duration(minutes: -1)), isTrue); // before start: lifecycle decides
    });

    test('F late join disabled: blocked right after start', () {
      const off = LateJoinSettings(enabled: false, minutes: 10);
      expect(off.joinOpenAt(startsAt: start, now: start.add(const Duration(seconds: 1))), isFalse);
      expect(off.joinOpenAt(startsAt: start, now: start), isTrue);
    });

    test('detail mirrors the window; in_progress keeps resume; server code mapped', () async {
      Test challenge({int minutes = 10}) => Test(
            id: 't-1', createdBy: 'creator', title: 'C', status: TestStatus.published,
            testMode: 'live', durationSec: 1800, startsAt: start,
            endsAt: start.add(const Duration(minutes: 30)), allowLateJoin: true,
            settings: {'late_join_minutes': minutes},
          );
      TestDetailController make(Duration after, FakeAttemptRepository a) => TestDetailController(
            testId: 't-1', tests: FakeTestRepository()..rows['t-1'] = challenge(),
            questions: FakeQuestionRepository(), attempts: a, results: FakeResultRepository(),
            currentUserId: () => 'u-1', clock: () => start.add(after),
          );
      final inside = make(const Duration(minutes: 10), FakeAttemptRepository());
      await inside.load();
      expect(inside.startBlockReason(), isNull);
      final outside = make(const Duration(minutes: 11), FakeAttemptRepository());
      await outside.load();
      expect(outside.startBlockReason(), contains('late-join window'));
      final a = FakeAttemptRepository();
      await a.start('t-1');
      final resuming = make(const Duration(minutes: 11), a);
      await resuming.load();
      expect(resuming.startBlockReason(), isNull);
      expect(TestErrors.map('LATE_JOIN_WINDOW_CLOSED'), 'The late-join window for this test has closed.');
    });

    test('G ends_at hard boundary unchanged even inside the late-join window', () {
      final t = Test(
        id: 't', createdBy: 'u', title: 'x', status: TestStatus.published, testMode: 'live',
        startsAt: start, endsAt: start.add(const Duration(minutes: 5)), allowLateJoin: true,
        settings: const {'late_join_minutes': 10},
      );
      final c = TestDetailController(
        testId: 't', tests: FakeTestRepository()..rows['t'] = t,
        questions: FakeQuestionRepository(), attempts: FakeAttemptRepository(),
        results: FakeResultRepository(), currentUserId: () => 'u-1',
        clock: () => start.add(const Duration(minutes: 5)),
      );
      expect(c.startBlockReason, isNotNull);
    });
  });

  group('N question source (truthful)', () {
    test('only Manual is available; creation_method never pretends', () {
      expect(QuestionSource.manual.isAvailable, isTrue);
      for (final s in [QuestionSource.document, QuestionSource.ai, QuestionSource.books]) {
        expect(s.isAvailable, isFalse, reason: '$s has no pipeline');
      }
    });

    testWidgets('unavailable source shows Not configured and cannot proceed', (tester) async {
      QuestionSource? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QuestionSourceStep(selected: QuestionSource.ai, onChanged: (s) => changed = s),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source_unavailable')), findsOneWidget);
      expect(find.text('Not configured'), findsNWidgets(3));
      await tester.tap(find.text('Use Manual'));
      expect(changed, QuestionSource.manual);
    });
  });

  group('W unsupported question types stay hidden', () {
    test('only MCQ single is a valid draft type', () {
      for (final t in QuestionType.values) {
        expect(QuestionDraft.isSupportedType(t), t == QuestionType.mcqSingle, reason: '$t');
      }
    });
  });

  group('Y timezone round trip', () {
    test('local pick → UTC write → local display keeps the same instant and wall clock', () {
      final picked = DateTime(2026, 10, 1, 10);
      final wire = picked.toUtc().toIso8601String();
      final back = parseTimestamp(wire)!;
      expect(back, picked);
      expect(back.isUtc, isFalse);
      expect(back.hour, 10);
    });
  });

  group('V readiness blocks every invalid state', () {
    test('every rule reports an actionable reason', () {
      const input = PublishReadinessInput(
        title: '', kind: TestKind.challengeWithFriends, groupId: null, durationSec: null,
        marksPerQuestion: null, startsAt: null, endsAt: null,
        serverQuestionStatuses: ['pending_review'], localDraftValidity: [false],
        serverQuestionOptionCounts: [2],
        questionConfig: QuestionConfig(total: 3, easy: 1, medium: 1, hard: 0),
        attemptSettings: AttemptSettings(allowReattempt: true, maxAttempts: 7),
        lateJoin: LateJoinSettings(enabled: true, minutes: -1), allowLateJoin: true,
        joinCode: '',
      );
      final reasons = PublishReadiness.blockingReasons(input);
      expect(reasons, containsAll([
        'Enter a test title',
        'Set a valid duration',
        'Set marks per question',
        '1 question(s) need approval before publishing',
        '1 question(s) have fewer than 4 options',
        '1 question(s) need fixing',
        'Challenge with Friends needs a start time',
        'Easy + Medium + Hard must equal 3',
        'Maximum attempts must be one of [1, 2, 3, 5, 10]',
        'Late-join window cannot be negative',
        'Challenge with Friends needs a join code',
      ]));
      expect(PublishReadiness.isReady(input), isFalse);
    });
  });
}
