// Attempt / re-attempt policy (server-authoritative; mirrored by the fake
// exactly as `_fn_start_attempt_core` does: resume in_progress, count the
// user's own attempts, settings.allow_reattempt / max_attempts, then
// REATTEMPT_LIMIT_REACHED / ATTEMPT_ALREADY_COMPLETED, MAX+1 allocation).
// Matrix A–L from the R4 re-attempt spec.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/domain/attempt_history.dart';
import 'package:my_praperation/features/test/domain/attempt_policy.dart';
import 'package:my_praperation/features/test/domain/test_errors.dart';
import 'package:my_praperation/features/test/domain/test_lifecycle.dart';
import 'package:my_praperation/features/test/screens/test_detail_screen.dart';
import 'package:my_praperation/features/test/state/attempt_launch_store.dart';
import 'package:my_praperation/features/test/state/results_controller.dart';
import 'package:my_praperation/features/test/state/test_creation_controller.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';

import 'fakes.dart';

class _NoAnswers implements AnswerRepository {
  @override
  Future<void> save(String attemptId, List<Answer> answers) async {}
  @override
  Future<List<Answer>> forAttempt(String attemptId) async => const [];
}

const _limitMsg = 'You have used all attempts allowed for this test.';
const _completedMsg = 'You have already completed this test. Use Re-attempt to try again.';

Test _test({Map<String, dynamic>? settings, String mode = 'self'}) => Test(
      id: 't-1', createdBy: 'creator', title: 'Policy', status: TestStatus.published,
      testMode: mode, durationSec: 600, settings: settings,
    );

({TestDetailController c, FakeAttemptRepository a, FakeTestRepository t}) _detail({
  Map<String, dynamic>? settings,
  String user = 'u-1',
}) {
  final t = FakeTestRepository()..rows['t-1'] = _test(settings: settings);
  final a = FakeAttemptRepository()
    ..currentUser = user
    ..testSettings['t-1'] = settings;
  final c = TestDetailController(
    testId: 't-1', tests: t, questions: FakeQuestionRepository(), attempts: a,
    results: FakeResultRepository(), currentUserId: () => user,
    clock: () => DateTime(2026, 9, 17, 12),
  );
  return (c: c, a: a, t: t);
}

void main() {
  setUp(AttemptLaunchStore.clear);

  group('AttemptSettings (tests.settings contract)', () {
    test('defaults: allow_reattempt=false, max_attempts=1, effective 1', () {
      expect(AttemptSettings.fromSettings(null), AttemptSettings.defaults);
      expect(AttemptSettings.defaults.effectiveMax, 1);
      expect(AttemptSettings.allowedMaxValues, [1, 2, 3, 5, 10]);
    });
    test('allow=false forces effective max 1 even if max_attempts is larger', () {
      const s = AttemptSettings(allowReattempt: false, maxAttempts: 5);
      expect(s.effectiveMax, 1);
      expect(s.applyTo({'test_kind': 'practice'}),
          {'test_kind': 'practice', 'allow_reattempt': false, 'max_attempts': 1});
    });
    test('round-trips through jsonb-ish maps, preserving other keys', () {
      const s = AttemptSettings(allowReattempt: true, maxAttempts: 3);
      final stored = s.applyTo({'test_kind': 'quick', 'target_question_count': 10});
      expect(stored['target_question_count'], 10);
      expect(AttemptSettings.fromSettings(stored), s);
      expect(AttemptSettings.fromSettings({'allow_reattempt': 'true', 'max_attempts': '2'}),
          const AttemptSettings(allowReattempt: true, maxAttempts: 2));
    });
  });

  group('A. allow_reattempt = false', () {
    test('first attempt succeeds without intent; explicit re-attempt is blocked', () async {
      final d = _detail(settings: {'allow_reattempt': false, 'max_attempts': 1});
      await d.c.load();
      expect(d.c.attemptState!.cta, AttemptCta.startTest);
      final first = await d.c.start();
      expect(first.started.attempt.attemptNumber, 1);
      d.a.complete(first.started.attempt.id);
      await d.c.refresh();
      expect(d.c.attemptState!.cta, AttemptCta.limitReached);
      expect(d.c.attemptState!.canReattempt, isFalse);
      await expectLater(d.c.reattempt(), throwsA(isA<ValidationError>()));
      // Even bypassing the UI gate, the "server" rejects.
      await expectLater(d.a.start('t-1', reattempt: true),
          throwsA(predicate((e) => e is AppError && e.message == _limitMsg)));
      expect(d.a.rows.length, 1);
    });
  });

  group('B. max_attempts = 2', () {
    test('1 ok, 2 ok (explicit), 3 blocked with REATTEMPT_LIMIT_REACHED', () async {
      final d = _detail(settings: {'allow_reattempt': true, 'max_attempts': 2});
      await d.c.load();
      final a1 = await d.c.start();
      d.a.complete(a1.started.attempt.id);
      await d.c.refresh();
      expect(d.c.attemptState!.cta, AttemptCta.reattempt);
      expect(d.c.attemptState!.usageLabel, 'Attempts 1/2');
      final a2 = await d.c.reattempt();
      expect(a2.started.attempt.attemptNumber, 2);
      d.a.complete(a2.started.attempt.id);
      await d.c.refresh();
      expect(d.c.attemptState!.cta, AttemptCta.limitReached);
      expect(d.c.attemptState!.usageLabel, 'Attempts 2/2');
      await expectLater(d.c.reattempt(), throwsA(isA<ValidationError>()));
      await expectLater(d.a.start('t-1', reattempt: true),
          throwsA(predicate((e) => e is AppError && e.message == _limitMsg)));
      expect(d.a.rows.length, 2);
    });
  });

  group('C. in_progress', () {
    test('repeated start resumes the same attempt; no duplicate; CTA = Continue', () async {
      final d = _detail(settings: {'allow_reattempt': true, 'max_attempts': 3});
      await d.c.load();
      final a1 = await d.c.start();
      await d.c.refresh();
      expect(d.c.attemptState!.cta, AttemptCta.continueTest);
      final again = await d.c.start();
      expect(again.started.attempt.id, a1.started.attempt.id);
      // Even an explicit re-attempt resumes while one is in progress.
      final viaReattempt = await d.a.start('t-1', reattempt: true);
      expect(viaReattempt.attempt.id, a1.started.attempt.id);
      expect(d.a.rows.length, 1);
    });
  });

  group('D. completed / scored', () {
    test('plain start (Back to Test path) never creates an attempt', () async {
      final d = _detail(settings: {'allow_reattempt': true, 'max_attempts': 3});
      await d.c.load();
      final a1 = await d.c.start();
      d.a.complete(a1.started.attempt.id);
      await d.c.refresh();
      expect(d.c.attemptState!.cta, AttemptCta.reattempt); // View Result + Re-attempt
      expect(d.c.attemptState!.inProgress, isNull);
      await expectLater(d.c.start(),
          throwsA(predicate((e) => e is AppError && e.message == _completedMsg)));
      expect(d.a.rows.length, 1);
      expect(d.a.calls.where((x) => x == 'start:t-1').length, 2);
      expect(d.a.calls.where((x) => x.endsWith(':reattempt')), isEmpty);
    });

    testWidgets('detail shows View Result and never "Continue Test" for a completed attempt',
        (tester) async {
      final d = _detail(settings: {'allow_reattempt': false});
      final a1 = await d.a.start('t-1');
      d.a.complete(a1.attempt.id);
      await tester.pumpWidget(MaterialApp(home: TestDetailScreen(testId: 't-1', controller: d.c)));
      await tester.pumpAndSettle();
      expect(find.text('View Result'), findsOneWidget);
      expect(find.text('Continue Test'), findsNothing);
      expect(find.text('Start Test'), findsNothing);
      expect(find.text('Re-attempt'), findsNothing);
      expect(find.text('This test allows a single attempt'), findsOneWidget);
      expect(find.textContaining('Attempts 1/1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      d.c.dispose();
    });
  });

  group('E. explicit Re-attempt', () {
    test('creates attempt_number + 1 only when permitted, with p_reattempt', () async {
      final d = _detail(settings: {'allow_reattempt': true, 'max_attempts': 3});
      await d.c.load();
      final a1 = await d.c.start();
      d.a.complete(a1.started.attempt.id);
      await d.c.refresh();
      final a2 = await d.c.reattempt();
      expect(a2.started.attempt.attemptNumber, 2);
      expect(d.a.calls.last, 'start:t-1:reattempt');
    });

    testWidgets('detail offers Re-attempt with Attempts N/M when permitted', (tester) async {
      final d = _detail(settings: {'allow_reattempt': true, 'max_attempts': 3});
      final a1 = await d.a.start('t-1');
      d.a.complete(a1.attempt.id);
      await tester.pumpWidget(MaterialApp(home: TestDetailScreen(testId: 't-1', controller: d.c)));
      await tester.pumpAndSettle();
      expect(find.text('Re-attempt'), findsOneWidget);
      expect(find.text('View Result'), findsOneWidget);
      expect(find.textContaining('Attempts 1/3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      d.c.dispose();
    });
  });

  group('F. limit reached', () {
    testWidgets('deterministic error mapping and no usable Re-attempt in the UI', (tester) async {
      expect(TestErrors.map('REATTEMPT_LIMIT_REACHED'), _limitMsg);
      expect(TestErrors.map('ATTEMPT_ALREADY_COMPLETED'), _completedMsg);
      expect(TestErrors.map('ATTEMPT_ALLOCATION_CONFLICT'),
          'Could not start the attempt right now. Please try again.');

      final d = _detail(settings: {'allow_reattempt': true, 'max_attempts': 2});
      for (var i = 0; i < 2; i++) {
        final a = await d.a.start('t-1', reattempt: i > 0);
        d.a.complete(a.attempt.id);
      }
      await tester.pumpWidget(MaterialApp(home: TestDetailScreen(testId: 't-1', controller: d.c)));
      await tester.pumpAndSettle();
      expect(find.text('Re-attempt'), findsNothing);
      expect(find.text('Re-attempt limit reached'), findsOneWidget);
      expect(find.textContaining('Attempts 2/2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      d.c.dispose();
    });
  });

  group('G. user isolation', () {
    test("another user's attempts do not count against mine", () async {
      final shared = FakeAttemptRepository()
        ..testSettings['t-1'] = {'allow_reattempt': false};
      shared.currentUser = 'someone-else';
      final theirs = await shared.start('t-1');
      shared.complete(theirs.attempt.id);

      shared.currentUser = 'u-1';
      final mine = await shared.start('t-1'); // first attempt for u-1
      expect(mine.attempt.attemptNumber, 1);
      expect(mine.attempt.userId, 'u-1');
      expect((await shared.mine('t-1')).map((a) => a.id), [mine.attempt.id]);
    });
  });

  group('H. security', () {
    test('direct RPC with p_reattempt=true cannot exceed the limit', () async {
      final a = FakeAttemptRepository()..testSettings['t-1'] = {'allow_reattempt': true, 'max_attempts': 1};
      final first = await a.start('t-1', reattempt: true); // first attempt: intent is harmless
      expect(first.attempt.attemptNumber, 1);
      a.complete(first.attempt.id);
      await expectLater(a.start('t-1', reattempt: true),
          throwsA(predicate((e) => e is AppError && e.message == _limitMsg)));
      // attempt_number is never client-supplied: rows carry server numbers only.
      expect(a.rows.map((r) => r.attemptNumber), [1]);
    });
  });

  group('I. code join', () {
    test('code-based entry obeys the same policy (resume, completed, limit)', () async {
      final a = FakeAttemptRepository()..testSettings['t-coded'] = {'allow_reattempt': true, 'max_attempts': 2};
      final a1 = await a.startByCode('ABCD');
      expect((await a.startByCode('ABCD')).attempt.id, a1.attempt.id); // resume
      a.complete(a1.attempt.id);
      await expectLater(a.startByCode('ABCD'),
          throwsA(predicate((e) => e is AppError && e.message == _completedMsg)));
      final a2 = await a.startByCode('ABCD', reattempt: true);
      expect(a2.attempt.attemptNumber, 2);
      expect(a.calls.last, 'code:ABCD:reattempt');
      a.complete(a2.attempt.id);
      await expectLater(a.startByCode('ABCD', reattempt: true),
          throwsA(predicate((e) => e is AppError && e.message == _limitMsg)));
    });
  });

  group('J. lifecycle unchanged', () {
    test('ends_at hard block and late-join rules are untouched by the policy', () {
      final endsAt = DateTime.utc(2026, 9, 17, 10);
      expect(
          TestLifecycle.startBlockReason(
              status: TestStatus.published, startsAt: null, endsAt: endsAt, now: endsAt),
          'Test ended.');
      expect(TestErrors.map('LATE_JOIN_NOT_ALLOWED'),
          'This challenge has already started and does not allow late joining.');
      expect(TestErrors.map('TEST_ENDED'), 'This test has ended.');
    });
  });

  group('K. results per attempt', () {
    Result res(String attemptId, {double score = 0, double? pct, double? acc, int c = 0, int w = 0, int u = 0}) =>
        Result(
          id: attemptId, attemptId: attemptId, testId: 't-1', userId: 'u-1',
          score: score, maxScore: 20, percentage: pct, accuracy: acc,
          correctCount: c, wrongCount: w, unansweredCount: u,
          computedAt: DateTime(2026, 9, 17, 12, int.parse(attemptId.split('-').last)),
        );
    Attempt att(String id, int n, {int minutes = 20}) => Attempt(
          id: id, testId: 't-1', userId: 'u-1', status: AttemptStatus.scored,
          startedAt: DateTime(2026, 9, 17, 9, n), attemptNumber: n,
          submittedAt: DateTime(2026, 9, 17, 9, n).add(Duration(minutes: minutes)),
        );

    test('history joins each result to its attempt; latest/best/previous/delta from stored fields', () {
      final results = [
        res('a-2', score: 16, pct: 80, acc: 88.9, c: 16, w: 2, u: 2),
        res('a-1', score: 12, pct: 60, acc: 75, c: 12, w: 4, u: 4),
      ];
      final attempts = [att('a-1', 1, minutes: 25), att('a-2', 2, minutes: 18)];
      final h = AttemptHistory.build(results, attempts);
      expect(h.map((e) => e.attemptNumber), [1, 2]);
      expect(AttemptHistory.latest(h)!.result.attemptId, 'a-2');
      expect(AttemptHistory.best(h)!.result.attemptId, 'a-2');
      final prev = AttemptHistory.previousOf(h, 'a-2')!;
      expect(prev.result.attemptId, 'a-1');
      final d = ResultDelta.between(h[1], h[0]);
      expect(d.score, 4);
      expect(d.percentage, 20);
      expect(d.accuracy, closeTo(13.9, 0.01));
      expect(d.correct, 4);
      expect(d.wrong, -2);
      expect(d.unanswered, -2);
      expect(d.time, const Duration(minutes: -7));
      expect(h[1].duration, const Duration(minutes: 18));
      expect(AttemptHistory.previousOf(h, 'a-1'), isNull);
    });

    test('missing stored fields yield null deltas and no duration (nothing fabricated)', () {
      final h = AttemptHistory.build([res('a-1'), res('a-2')], const []);
      expect(h.first.attemptNumber, isNull);
      expect(h.first.duration, isNull);
      final d = ResultDelta.between(h[1], h[0]);
      expect(d.percentage, isNull);
      expect(d.accuracy, isNull);
      expect(d.time, isNull);
      expect(d.score, 0);
      expect(AttemptHistory.best([]), isNull);
    });

    test('results controller exposes history, best/latest and gated re-attempt', () async {
      final attempts = FakeAttemptRepository()
        ..rows.addAll([att('a-1', 1), att('a-2', 2)])
        ..testSettings['t-1'] = {'allow_reattempt': true, 'max_attempts': 2};
      final results = FakeResultRepository()
        ..byAttemptId['a-2'] = res('a-2', score: 16, pct: 80)
        ..mine.addAll([res('a-2', score: 16, pct: 80), res('a-1', score: 12, pct: 60)]);
      final tests = FakeTestRepository()
        ..rows['t-1'] = _test(settings: {'allow_reattempt': true, 'max_attempts': 2});
      final c = ResultsController(
        attemptId: 'a-2', results: results, tests: tests,
        questions: FakeQuestionRepository(), answers: _NoAnswers(),
        attempts: attempts, subjectNames: () async => {},
      );
      await c.load();
      expect(c.attemptHistory.length, 2);
      expect(c.latestEntry!.attemptNumber, 2);
      expect(c.bestEntry!.attemptNumber, 2);
      expect(c.previousEntry!.attemptNumber, 1);
      expect(c.deltaFromPrevious!.score, 4);
      expect(c.canReattempt, isFalse); // 2/2 used
      await expectLater(c.reattempt(), throwsA(isA<ValidationError>()));
    });
  });

  group('L. creation persists the policy (no schema)', () {
    test('Attempt Settings round-trip through settings jsonb and reload on edit', () async {
      final tests = FakeTestRepository();
      final c = TestCreationController(
        tests: tests, questions: FakeQuestionRepository(), groups: FakeGroupRepository(),
        currentUserId: () => 'u-1',
      )..setTitle('P');
      c.setConfiguration(
        durationSec: 600, marksPerQuestion: 1, negativeMarks: 0, groupId: null,
        startsAt: null, endsAt: null, maxParticipants: null, allowLateJoin: false,
        accessCode: null, joinCode: null,
        attemptSettings: const AttemptSettings(allowReattempt: true, maxAttempts: 5),
      );
      final id = await c.saveDraft();
      expect(tests.rows[id]!.settings!['allow_reattempt'], true);
      expect(tests.rows[id]!.settings!['max_attempts'], 5);

      final edit = TestCreationController(
        editingTestId: id, tests: tests, questions: FakeQuestionRepository(),
        groups: FakeGroupRepository(), currentUserId: () => 'u-1',
      );
      await edit.loadForEdit();
      expect(edit.attemptSettings, const AttemptSettings(allowReattempt: true, maxAttempts: 5));
    });
  });
}

