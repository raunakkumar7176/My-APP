// G11 — Group Test Results on the LIVE contract (audited 2026-09-19):
//   results(attempt_id PK, test_id, user_id, score, max_score, correct_count,
//   wrong_count, unanswered_count, accuracy, percentage, rank,
//   subject_breakdown, topic_breakdown, computed_at) — SELECT own row OR
//   VIEW_GROUP_ANALYTICS; result_batches(UNIQUE test_id) — SELECT
//   GENERATE_RESULTS; ai_reports(UNIQUE(test_id,user_id), payload jsonb,
//   model) — SELECT own OR GENERATE_RESULTS; rpc_generate_results — creator
//   OR GENERATE_RESULTS, deterministic (fn_score_attempt), no AI; ai_jobs —
//   no direct client access (proposed rpc_request_coach_reports enqueues).
// Leader holds GENERATE_RESULTS + VIEW_GROUP_ANALYTICS by the live seeding.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/result_batch.dart';
import 'package:my_praperation/features/test/data/result_repository.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/group/domain/group_test_results.dart';
import 'package:my_praperation/features/group/screens/group_test_results_screen.dart';
import 'package:my_praperation/features/group/state/group_test_results_controller.dart';

import '../r4_restart/fakes.dart';
import 'fakes.dart';

Result _r(
  String user, {
  double score = 6,
  double max = 10,
  int c = 6,
  int w = 2,
  int u = 2,
  int? rank,
  Map<String, dynamic>? subjects,
}) => Result(
  id: 'a-$user',
  attemptId: 'a-$user',
  testId: 't-1',
  userId: user,
  score: score,
  maxScore: max,
  percentage: score / max * 100,
  accuracy: c + w == 0 ? 0 : c / (c + w) * 100,
  correctCount: c,
  wrongCount: w,
  unansweredCount: u,
  rank: rank,
  subjectBreakdown: subjects ?? const {'Physics': 80.0, 'Maths': 40.0},
  computedAt: DateTime(2026, 9, 18, 10),
);

AiCoachReport _rep(String user) => AiCoachReport.fromJson({
  'id': 'rep-$user',
  'test_id': 't-1',
  'user_id': user,
  'batch_id': 'b-t-1',
  'model': 'gemini-2.0-flash',
  'created_at': '2026-09-18T11:00:00Z',
  'payload': {
    'summary': 'Solid physics, weak maths.',
    'strengths': ['Mechanics'],
    'weaknesses': ['Algebra'],
    'mistake_patterns': ['Sign errors'],
    'subject_analysis': [
      {'subject': 'Maths', 'performance': '40%', 'note': 'Revise algebra'},
    ],
    'revision_plan': ['Algebra ch. 2'],
    'practice_plan': ['20 MCQs daily'],
    'next_week_action_plan': ['Mock test Sunday'],
    'coach_message': 'Keep going.',
  },
});

/// g-1: owner u-owner, leader u-lead, member u-me, member u-b; g-2 owned by
/// u-other. t-1 = ended group test in g-1 created by u-lead with results for
/// u-me (rank 2) and u-b (rank 1) and a stored report for u-b only;
/// t-2 = ended test in g-2 with a result for u-other.
({
  InMemoryGroupRepository groups,
  FakeTestRepository tests,
  FakeResultRepository results,
})
_fixture(String user) {
  final groups = InMemoryGroupRepository(currentUser: user)
    ..seed(
      id: 'g-1',
      name: 'Physics',
      ownerId: 'u-owner',
      members: {'u-lead': 'leader', 'u-me': 'member', 'u-b': 'member'},
    )
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  groups.profileNames['u-b'] = 'Bea';
  final tests = FakeTestRepository()
    ..currentUser = user
    ..groups = groups;
  tests.rows['t-1'] = const Test(
    id: 't-1',
    createdBy: 'u-lead',
    title: 'Weekly',
    status: TestStatus.ended,
    testMode: 'group',
    groupId: 'g-1',
    durationSec: 600,
    negativeMarks: 0.5,
  );
  tests.rows['t-2'] = const Test(
    id: 't-2',
    createdBy: 'u-other',
    title: 'Foreign',
    status: TestStatus.ended,
    testMode: 'group',
    groupId: 'g-2',
    durationSec: 600,
  );
  final results = FakeResultRepository()
    ..currentUser = user
    ..groups = groups
    ..tests = tests;
  results.resultsByTest['t-1'] = [
    _r('u-me', rank: 2),
    _r('u-b', score: 9, c: 9, w: 1, u: 0, rank: 1),
  ];
  results.resultsByTest['t-2'] = [_r('u-other')];
  results.reportsByTest['t-1'] = [_rep('u-b')];
  return (groups: groups, tests: tests, results: results);
}

GroupTestResultsController _ctl(
  ({
    InMemoryGroupRepository groups,
    FakeTestRepository tests,
    FakeResultRepository results,
  })
  f,
  String user, {
  String groupId = 'g-1',
  String testId = 't-1',
}) => GroupTestResultsController(
  groupId: groupId,
  testId: testId,
  results: f.results,
  tests: f.tests,
  groups: f.groups,
  currentUserId: user,
);

void main() {
  group('models', () {
    test(
      'AiCoachReport parses the live payload keys; missing keys are empty',
      () {
        final r = _rep('u-b');
        expect(r.summary, 'Solid physics, weak maths.');
        expect(r.strengths, ['Mechanics']);
        expect(r.mistakePatterns, ['Sign errors']);
        expect(r.subjectAnalysis.single.subject, 'Maths');
        expect(r.nextWeekActionPlan, ['Mock test Sunday']);
        expect(r.coachMessage, 'Keep going.');
        expect(r.isEmpty, isFalse);
        final bare = AiCoachReport.fromJson({
          'id': 'x',
          'test_id': 't',
          'user_id': 'u',
          'batch_id': 'b',
          'model': 'm',
          'payload': {},
        });
        expect(bare.isEmpty, isTrue);
        expect(bare.strengths, isEmpty);
      },
    );

    test('CoachReportJob parses the RPC response', () {
      final j = CoachReportJob.fromJson({
        'job_id': 'j1',
        'status': 'pending',
        'reports_done': 1,
        'reports_total': 3,
        'created': true,
      });
      expect(j.isQueued, isTrue);
      expect(j.created, isTrue);
      expect(
        CoachReportJob.fromJson({'id': 'j2', 'status': 'completed'}).isDone,
        isTrue,
      );
    });

    test('ResultInsights derive weak/strong areas, negative marks and points deterministically', () {
      const t = Test(
        id: 't-1',
        createdBy: 'u',
        title: 'x',
        status: TestStatus.ended,
        negativeMarks: 0.5,
      );
      final ins = ResultInsights.from(_r('u-me'), test: t);
      expect(ins.weakSubjects.map((e) => e.key), ['Maths']);
      expect(ins.strongSubjects.map((e) => e.key), ['Physics']);
      expect(ins.negativeMarksLost, 1.0);
      expect(ins.improvementPoints.any((p) => p.contains('Maths')), isTrue);
      expect(
        ins.improvementPoints.any((p) => p.contains('unanswered')),
        isTrue,
      );
      expect(
        ins.improvementPoints.any((p) => p.contains('Negative marking')),
        isTrue,
      );
      final clean = ResultInsights.from(
        _r('u', c: 10, w: 0, u: 0, subjects: {'Physics': 100.0}),
      );
      expect(clean.weakSubjects, isEmpty);
      expect(clean.improvementPoints.single, contains('Clean run'));
    });

    test('GroupTestResultsSummary is arithmetic only (no pass mark)', () {
      final s = GroupTestResultsSummary.from([
        _r('a', score: 5),
        _r('b', score: 9),
        _r('c', score: 7),
      ]);
      expect(s.participants, 3);
      expect(s.averagePercentage, closeTo(70, 0.01));
      expect(s.medianPercentage, 70);
      expect(s.highestPercentage, 90);
      expect(s.lowestPercentage, 50);
      expect(GroupTestResultsSummary.from(const []).averagePercentage, isNull);
    });

    test('access gates mirror the live rules', () {
      expect(
        GroupResultsAccess.canGenerate(
          isCreator: false,
          hasGenerateResults: false,
          isOwner: false,
        ),
        isFalse,
      );
      expect(
        GroupResultsAccess.canGenerate(
          isCreator: true,
          hasGenerateResults: false,
          isOwner: false,
        ),
        isTrue,
      );
      expect(
        GroupResultsAccess.canSeeAllResults(
          hasViewAnalytics: false,
          isOwner: false,
        ),
        isFalse,
      );
      expect(
        GroupResultsAccess.canSeeAllReports(
          hasGenerateResults: true,
          isOwner: false,
        ),
        isTrue,
      );
      expect(GroupResultsAccess.isResultsPhase(TestStatus.ended), isTrue);
      expect(GroupResultsAccess.isResultsPhase(TestStatus.published), isFalse);
    });
  });

  group('member: own result only, no AI on open', () {
    test('member sees only their own result and no other report', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.accessDenied, isFalse);
      expect(c.results.map((r) => r.userId), ['u-me']);
      expect(c.myResult!.rank, 2);
      expect(c.myReport, isNull);
      expect(
        c.allReports,
        isEmpty,
        reason: 'u-b\'s report is not visible to u-me',
      );
      expect(c.canGenerateResults, isFalse);
      expect(c.canSeeAllResults, isFalse);
      expect(c.batch, isNull);
      expect(
        f.results.calls.any((x) => x.startsWith('generate')),
        isFalse,
        reason: 'opening never generates',
      );
      expect(
        f.results.calls.any((x) => x.startsWith('requestCoach')),
        isFalse,
        reason: 'opening never queues AI',
      );
      expect(
        f.results.calls.any((x) => x.startsWith('batch')),
        isFalse,
        reason: 'members do not read batches',
      );
    });

    test('member with a stored report reads it (own row policy)', () async {
      final f = _fixture('u-b');
      final c = _ctl(f, 'u-b');
      await c.load();
      expect(c.myReport?.summary, 'Solid physics, weak maths.');
      expect(c.results.map((r) => r.userId), ['u-b']);
    });

    test('member cannot generate or request coach reports (controller + fake server)', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(await c.generateResults(), isFalse);
      expect(c.error, contains('permission'));
      expect(await c.requestCoachReports(), isFalse);
      await expectLater(
        f.results.generateResults('t-1'),
        throwsA(isA<DataError>()),
      );
      await expectLater(
        f.results.requestCoachReports('t-1'),
        throwsA(isA<DataError>()),
      );
      expect(f.results.batchByTest, isEmpty);
    });
  });

  group('access: non-member, cross-group, removed member, forged ids', () {
    test('non-member: access denied, nothing read', () async {
      final f = _fixture('u-stranger');
      final c = _ctl(f, 'u-stranger');
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(f.results.calls, isEmpty);
    });

    test(
      'a test of another group cannot be opened through this group',
      () async {
        final f = _fixture('u-me');
        final c = _ctl(f, 'u-me', testId: 't-2');
        await c.load();
        expect(c.accessDenied, isTrue);
        expect(c.results, isEmpty);
      },
    );

    test('cross-group results are never returned (fake RLS)', () async {
      final f = _fixture('u-lead');
      expect(
        await f.results.resultsForTest('t-2'),
        isEmpty,
        reason: 'no VIEW_GROUP_ANALYTICS in g-2 and no own row',
      );
    });

    test('removed member loses access on refresh', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.myResult, isNotNull);
      f.groups.groups['g-1']!.roles.remove('u-me');
      await c.refresh();
      expect(c.accessDenied, isTrue);
      expect(c.results, isEmpty);
    });

    test('forged user id: a result row for another user is not readable by a member', () async {
      final f = _fixture('u-me');
      final rows = await f.results.resultsForTest('t-1');
      expect(rows.any((r) => r.userId == 'u-b'), isFalse);
      expect(await f.results.allAiReports('t-1'), isEmpty);
    });
  });

  group('manager: batch, generation, coach reports, all results', () {
    test('leader (creator) sees everyone, batch and reports; generation is explicit', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(c.canGenerateResults, isTrue);
      expect(c.canSeeAllResults, isTrue);
      expect(c.results.map((r) => r.userId), [
        'u-b',
        'u-me',
      ], reason: 'best first');
      expect(c.allReports.map((r) => r.userId), ['u-b']);
      expect(c.hasReport(c.results.first), isTrue);
      expect(c.participantLabel(c.results.first), 'Bea');
      expect(c.batch, isNull, reason: 'nothing generated yet');
      expect(f.results.calls.any((x) => x.startsWith('generate')), isFalse);

      expect(await c.generateResults(), isTrue);
      expect(c.batch?.isCompleted, isTrue);
      expect(f.results.calls.where((x) => x == 'generate:t-1').length, 1);
      expect(
        f.results.calls.where((x) => x == 'results:t-1').length,
        2,
        reason: 'server re-read after the action',
      );
      // Second run reuses the batch (live UNIQUE(test_id)).
      expect(await c.generateResults(), isTrue);
      expect(f.results.batchByTest.length, 1);
    });

    test(
      'coach reports: only after a finished batch; idempotent; no AI on read',
      () async {
        final f = _fixture('u-lead');
        final c = _ctl(f, 'u-lead');
        await c.load();
        expect(await c.requestCoachReports(), isFalse);
        expect(c.error, contains('Generate results first'));
        expect(
          f.results.calls.any((x) => x.startsWith('requestCoach')),
          isFalse,
        );
        await c.generateResults();
        expect(await c.requestCoachReports(), isTrue);
        expect(c.coachJob?.created, isTrue);
        expect(c.coachJob?.isQueued, isTrue);
        expect(await c.requestCoachReports(), isTrue);
        expect(c.coachJob?.created, isFalse, reason: 'same job returned');
        expect(f.results.jobByTest.length, 1);
        await c.refresh();
        expect(
          f.results.calls.where((x) => x.startsWith('requestCoach')).length,
          2,
          reason: 'refresh never re-queues',
        );
      },
    );

    test(
      'owner (no explicit permission row) passes through the function bypass',
      () async {
        final f = _fixture('u-owner');
        final c = _ctl(f, 'u-owner');
        await c.load();
        expect(c.canGenerateResults, isTrue);
        expect(c.canSeeAllResults, isTrue);
        expect(c.results.length, 2);
        expect(await c.generateResults(), isTrue);
      },
    );

    test('server rejection is surfaced and state re-read', () async {
      final f = _fixture('u-lead');
      f.results.failGenerateWith = const DataError(
        message: 'GENERATE_RESULTS_FORBIDDEN',
      );
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(await c.generateResults(), isFalse);
      expect(c.error, 'GENERATE_RESULTS_FORBIDDEN');
      expect(c.isBusy, isFalse);
      expect(c.batch, isNull);
    });

    test(
      'single-flight: second action while one is in flight is dropped',
      () async {
        final f = _fixture('u-lead');
        final slow = _SlowResults(f.results);
        final c = GroupTestResultsController(
          groupId: 'g-1',
          testId: 't-1',
          results: slow,
          tests: f.tests,
          groups: f.groups,
          currentUserId: 'u-lead',
        );
        await c.load();
        final first = c.generateResults();
        expect(c.isBusy, isTrue);
        expect(await c.generateResults(), isFalse);
        expect(await c.requestCoachReports(), isFalse);
        expect(await first, isTrue);
        expect(f.results.calls.where((x) => x == 'generate:t-1').length, 1);
      },
    );
  });

  group('states + widget', () {
    Future<GroupTestResultsController> pump(
      WidgetTester tester,
      ({
        InMemoryGroupRepository groups,
        FakeTestRepository tests,
        FakeResultRepository results,
      })
      f,
      String user,
    ) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _ctl(f, user);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupTestResultsScreen(
            groupId: 'g-1',
            testId: 't-1',
            controller: c,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    test('loading → loaded; empty results; error on load', () async {
      final f = _fixture('u-me');
      f.results.resultsByTest['t-1'] = [];
      final c = _ctl(f, 'u-me');
      final fut = c.load();
      expect(c.isLoading, isTrue);
      await fut;
      expect(c.hasLoaded, isTrue);
      expect(c.myResult, isNull);
      expect(c.hasAnyResults, isFalse);
      final failing = _FailingResults(f.results);
      final c2 = GroupTestResultsController(
        groupId: 'g-1',
        testId: 't-1',
        results: failing,
        tests: f.tests,
        groups: f.groups,
        currentUserId: 'u-me',
      );
      await c2.load();
      expect(c2.error, 'Network error.');
      failing.fail = false;
      await c2.load();
      expect(c2.error, isNull);
    });

    testWidgets(
      'member: own result, insights, review button, no manager section, no coach report',
      (tester) async {
        final c = await pump(tester, _fixture('u-me'), 'u-me');
        expect(find.byKey(const Key('my_result_card')), findsOneWidget);
        expect(find.byKey(const Key('my_score')), findsOneWidget);
        expect(find.byKey(const Key('my_negative')), findsOneWidget);
        expect(find.byKey(const Key('my_weak')), findsOneWidget);
        expect(find.byKey(const Key('open_detailed_result')), findsOneWidget);
        expect(find.byKey(const Key('coach_report_empty')), findsOneWidget);
        expect(find.byKey(const Key('results_manager_section')), findsNothing);
        expect(find.byKey(const Key('generate_results_button')), findsNothing);
        expect(
          find.textContaining('Bea'),
          findsNothing,
          reason: 'no other participant leaks',
        );
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets(
      'member with report: coach card sections render from stored payload',
      (tester) async {
        final c = await pump(tester, _fixture('u-b'), 'u-b');
        expect(find.byKey(const Key('coach_report_card')), findsOneWidget);
        expect(find.byKey(const Key('coach_summary')), findsOneWidget);
        expect(find.byKey(const Key('coach_mistakes')), findsOneWidget);
        expect(find.byKey(const Key('coach_subjects')), findsOneWidget);
        expect(find.byKey(const Key('coach_next_week')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets(
      'leader: manager section, generate → batch status → request coach',
      (tester) async {
        final f = _fixture('u-lead');
        final c = await pump(tester, f, 'u-lead');
        expect(
          find.byKey(const Key('results_manager_section')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('participant_u-b')), findsOneWidget);
        expect(find.byKey(const Key('participant_u-me')), findsOneWidget);
        expect(find.byKey(const Key('group_summary')), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('request_coach_reports_button')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const Key('generate_results_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_generate_results')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('batch_status')), findsOneWidget);
        expect(c.batch?.isCompleted, isTrue);
        await tester.tap(find.byKey(const Key('request_coach_reports_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('coach_job_status')), findsOneWidget);
        expect(c.coachJob?.isQueued, isTrue);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('non-member: denied state', (tester) async {
      final c = await pump(tester, _fixture('u-stranger'), 'u-stranger');
      expect(find.byKey(const Key('group_results_denied')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

class _SlowResults extends _Delegating {
  _SlowResults(super.inner);
  @override
  Future<ResultBatch> generateResults(String testId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return inner.generateResults(testId);
  }
}

class _FailingResults extends _Delegating {
  _FailingResults(super.inner);
  bool fail = true;
  @override
  Future<List<Result>> resultsForTest(String testId) {
    if (fail) throw const DataError(message: 'Network error.');
    return inner.resultsForTest(testId);
  }
}

class _Delegating implements ResultRepository {
  _Delegating(this.inner);
  final FakeResultRepository inner;
  @override
  Future<Result?> byAttempt(String attemptId) => inner.byAttempt(attemptId);
  @override
  Future<List<Result>> mineForTest(String testId) => inner.mineForTest(testId);
  @override
  Future<ResultBatch> generateResults(String testId) =>
      inner.generateResults(testId);
  @override
  Future<List<Result>> resultsForTest(String testId) =>
      inner.resultsForTest(testId);
  @override
  Future<AiCoachReport?> myAiReport(String testId) => inner.myAiReport(testId);
  @override
  Future<List<AiCoachReport>> allAiReports(String testId) =>
      inner.allAiReports(testId);
  @override
  Future<ResultBatch?> batchForTest(String testId) =>
      inner.batchForTest(testId);
  @override
  Future<CoachReportJob> requestCoachReports(String testId) =>
      inner.requestCoachReports(testId);
  @override
  Future<List<Map<String, dynamic>>> leaderboard(String testId) =>
      inner.leaderboard(testId);
}
