// G12 — Group Test Leaderboard on the LIVE contract (audited 2026-09-19):
//   results(attempt_id PK, test_id, user_id, score, max_score, correct_count,
//   wrong_count, unanswered_count, accuracy, percentage, rank,
//   subject_breakdown, topic_breakdown, computed_at) — SELECT own row OR
//   VIEW_GROUP_ANALYTICS. Leaderboard is derived entirely from stored results;
//   no AI, no new RPC, no new table. Ranking: score DESC, computed_at ASC
//   as deterministic tie-breaker. Ties share rank (standard competition
//   ranking: next rank = 1 + count of entries above).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/result_batch.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/result_repository.dart';
import 'package:my_praperation/features/group/domain/group_test_results.dart';
import 'package:my_praperation/features/group/screens/group_leaderboard_screen.dart';
import 'package:my_praperation/features/group/state/group_leaderboard_controller.dart';
import 'package:my_praperation/features/group/state/group_test_results_controller.dart';

import '../r4_restart/fakes.dart';
import 'fakes.dart';

Result _r(String user, {double score = 6, double max = 10, int c = 6, int w = 2, int u = 2, int? rank, DateTime? computedAt}) =>
    Result(
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
      computedAt: computedAt ?? DateTime(2026, 9, 18, 10),
    );

({InMemoryGroupRepository groups, FakeTestRepository tests, FakeResultRepository results}) _fixture(String user) {
  final groups = InMemoryGroupRepository(currentUser: user)
    ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-lead': 'leader', 'u-me': 'member', 'u-b': 'member'})
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  groups.profileNames['u-b'] = 'Bea';
  final tests = FakeTestRepository()..currentUser = user..groups = groups;
  tests.rows['t-1'] = Test(id: 't-1', createdBy: 'u-lead', title: 'Weekly', status: TestStatus.ended, testMode: 'group', groupId: 'g-1', durationSec: 600, negativeMarks: 0.5);
  tests.rows['t-2'] = Test(id: 't-2', createdBy: 'u-other', title: 'Foreign', status: TestStatus.ended, testMode: 'group', groupId: 'g-2', durationSec: 600);
  final results = FakeResultRepository()..currentUser = user..groups = groups..tests = tests;
  results.resultsByTest['t-1'] = [
    _r('u-me', score: 6, rank: 2, computedAt: DateTime(2026, 9, 18, 10, 0)),
    _r('u-b', score: 9, c: 9, w: 1, u: 0, rank: 1, computedAt: DateTime(2026, 9, 18, 9, 55)),
  ];
  results.resultsByTest['t-2'] = [_r('u-other')];
  return (groups: groups, tests: tests, results: results);
}

GroupLeaderboardController _ctl(({InMemoryGroupRepository groups, FakeTestRepository tests, FakeResultRepository results}) f, String user, {String groupId = 'g-1', String testId = 't-1'}) =>
    GroupLeaderboardController(groupId: groupId, testId: testId, results: f.results, tests: f.tests, groups: f.groups, currentUserId: user);

void main() {
  group('LeaderboardEntry.fromResults', () {
    test('ranks by score descending', () {
      final entries = LeaderboardEntry.fromResults([_r('a', score: 5), _r('b', score: 9), _r('c', score: 7)], currentUserId: '', labelFor: (u) => u);
      expect(entries.map((e) => e.userId), ['b', 'c', 'a']);
      expect(entries.map((e) => e.rank), [1, 2, 3]);
    });

    test('ties share rank; next rank = 1 + count above', () {
      final entries = LeaderboardEntry.fromResults([
        _r('a', score: 8),
        _r('b', score: 8, computedAt: DateTime(2026, 9, 18, 11)),
        _r('c', score: 8, computedAt: DateTime(2026, 9, 18, 12)),
        _r('d', score: 5),
      ], currentUserId: '', labelFor: (u) => u);
      expect(entries[0].rank, 1);
      expect(entries[1].rank, 1);
      expect(entries[2].rank, 1);
      expect(entries[3].rank, 4);
    });

    test('tie-breaker: earlier computed_at wins when scores are equal', () {
      final entries = LeaderboardEntry.fromResults([
        _r('late', score: 7, computedAt: DateTime(2026, 9, 18, 12)),
        _r('early', score: 7, computedAt: DateTime(2026, 9, 18, 9)),
      ], currentUserId: '', labelFor: (u) => u);
      expect(entries.first.userId, 'early');
      expect(entries.last.userId, 'late');
    });

    test('null scores are placed at the bottom', () {
      final entries = LeaderboardEntry.fromResults([
        _r('no-score', score: 0),
        _r('with-score', score: 5),
      ], currentUserId: '', labelFor: (u) => u);
      expect(entries.first.userId, 'with-score');
    });

    test('empty list returns empty', () {
      expect(LeaderboardEntry.fromResults(const [], currentUserId: '', labelFor: (u) => u), isEmpty);
    });

    test('current user entry is flagged', () {
      final entries = LeaderboardEntry.fromResults([_r('me', score: 5), _r('other', score: 9)], currentUserId: 'me', labelFor: (u) => u);
      expect(entries.first.isCurrentUser, isFalse);
      expect(entries.last.isCurrentUser, isTrue);
    });

    test('label is resolved from labelFor', () {
      final entries = LeaderboardEntry.fromResults([_r('u-1', score: 5)], currentUserId: '', labelFor: (u) => u == 'u-1' ? 'You' : 'Other');
      expect(entries.first.label, 'You');
    });

    test('preserves all result fields', () {
      final entries = LeaderboardEntry.fromResults([_r('a', score: 8, max: 10, c: 8, w: 1, u: 1)], currentUserId: '', labelFor: (u) => u);
      final e = entries.first;
      expect(e.score, 8);
      expect(e.maxScore, 10);
      expect(e.percentage, closeTo(80, 0.01));
      expect(e.accuracy, closeTo(88.89, 0.1));
      expect(e.correctCount, 8);
      expect(e.wrongCount, 1);
      expect(e.unansweredCount, 1);
    });
  });

  group('GroupResultsAccess.canSeeLeaderboard', () {
    test('member can see', () {
      expect(GroupResultsAccess.canSeeLeaderboard(isMember: true, isOwner: false), isTrue);
    });
    test('owner can see', () {
      expect(GroupResultsAccess.canSeeLeaderboard(isMember: false, isOwner: true), isTrue);
    });
    test('non-member cannot see', () {
      expect(GroupResultsAccess.canSeeLeaderboard(isMember: false, isOwner: false), isFalse);
    });
  });

  group('controller: load and access', () {
    test('leader loads leaderboard with all participants, best first', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(c.accessDenied, isFalse);
      expect(c.entries.length, 2);
      expect(c.entries.first.userId, 'u-b');
      expect(c.entries.last.userId, 'u-me');
      expect(c.myEntry, isNull);
    });

    test('member receives the full server ranking and their TRUE rank (F-10)', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.accessDenied, isFalse);
      expect(c.entries.length, 2);
      expect(c.entries.first.userId, 'u-b');
      expect(c.entries.first.rank, 1);
      expect(c.myEntry?.userId, 'u-me');
      expect(c.myEntry?.rank, 2);
      expect(c.entries.first.label, 'Bea'); // server full_name, no profile read
      // Only the RPC was used: no direct results rows for other users.
      expect(f.results.calls, ['leaderboard:t-1']);
    });

    test('owner sees all results through the function bypass', () async {
      final f = _fixture('u-owner');
      final c = _ctl(f, 'u-owner');
      await c.load();
      expect(c.accessDenied, isFalse);
      expect(c.entries.length, 2);
    });

    test('leader labels participants from the roster', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(c.entries.first.label, 'Bea');
    });

    test('error state surfaces error message', () async {
      final f = _fixture('u-lead');
      final failing = _FailingResults(f.results);
      final c = GroupLeaderboardController(groupId: 'g-1', testId: 't-1', results: failing, tests: f.tests, groups: f.groups, currentUserId: 'u-lead');
      await c.load();
      expect(c.error, 'NETWORK_DOWN');
      failing.fail = false;
      await c.load();
      expect(c.error, isNull);
    });
  });

  group('server path (F-10)', () {
    test('entries keep the server order and rank; ties share the rank', () {
      final e = LeaderboardEntry.fromServerRows([
        {'rank': 1, 'user_id': 'a', 'full_name': 'Ann', 'score': 10, 'max_score': 10, 'percentage': 100, 'accuracy': 100},
        {'rank': 2, 'user_id': 'b', 'full_name': 'Bob', 'score': 9, 'max_score': 10, 'percentage': 90, 'accuracy': 90},
        {'rank': 2, 'user_id': 'me', 'full_name': null, 'score': 9, 'max_score': 10, 'percentage': 90, 'accuracy': 90},
        {'rank': 4, 'user_id': 'd', 'full_name': '', 'score': 8, 'max_score': 10, 'percentage': 80, 'accuracy': 80},
      ], currentUserId: 'me', labelFor: (u) => 'roster-$u');
      expect(e.map((x) => x.rank), [1, 2, 2, 4]);
      expect(e.map((x) => x.label), ['Ann', 'Bob', 'You', 'roster-d']);
      expect(e[2].isCurrentUser, isTrue);
      expect(e[0].score, 10.0);
    });

    test('the controller never reads results rows for ranking but probes permissions for F-10 visibility', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(f.results.calls.where((x) => x.startsWith('results:')), isEmpty);
      // F-10: permissionsFor is probed to determine canSeeFullLeaderboard
      expect(f.groups.calls.where((x) => x.startsWith('permissionsFor')), isNotEmpty);
      expect(c.canSeeFullLeaderboard, isFalse); // u-me is a member, not owner, no analytics
    });

    test('participant who is no longer a member still gets rows only via the server rule (mirror)', () async {
      final f = _fixture('u-b');
      f.groups.groups['g-1']!.roles.remove('u-b');
      // Group screen denies (membership guard) — the RPC alone would still serve a participant.
      final c = _ctl(f, 'u-b');
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(await f.results.leaderboard('t-1'), isNotEmpty);
    });

    test('stranger gets 0 rows from the RPC (mirror of the remediated function)', () async {
      final f = _fixture('u-stranger');
      expect(await f.results.leaderboard('t-1'), isEmpty);
    });

    test('owner gets canSeeFullLeaderboard = true', () async {
      final f = _fixture('u-owner');
      final c = _ctl(f, 'u-owner');
      await c.load();
      expect(c.canSeeFullLeaderboard, isTrue);
      expect(c.isOwner, isTrue);
    });

    test('member without analytics gets canSeeFullLeaderboard = false', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.canSeeFullLeaderboard, isFalse);
    });

    test('leader with viewGroupAnalytics gets canSeeFullLeaderboard = true', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(c.canSeeFullLeaderboard, isTrue);
    });
  });

  group('access control', () {
    test('non-member: access denied, no results read', () async {
      final f = _fixture('u-stranger');
      final c = _ctl(f, 'u-stranger');
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(c.entries, isEmpty);
      expect(f.results.calls, isEmpty);
    });

    test('a test of another group cannot be opened through this group', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me', testId: 't-2');
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(c.entries, isEmpty);
    });

    test('cross-group leaderboard denied', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead', groupId: 'g-2', testId: 't-2');
      await c.load();
      expect(c.accessDenied, isTrue);
    });

    test('removed member loses access on refresh', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.accessDenied, isFalse);
      f.groups.groups['g-1']!.roles.remove('u-me');
      await c.refresh();
      expect(c.accessDenied, isTrue);
      expect(c.entries, isEmpty);
    });

    test('direct results rows stay RLS-scoped (no cross-user leak outside the RPC)', () async {
      final f = _fixture('u-me');
      final rows = await f.results.resultsForTest('t-1');
      expect(rows.any((r) => r.userId == 'u-b'), isFalse);
    });
  });

  group('states', () {
    test('empty results: entries list is empty', () async {
      final f = _fixture('u-lead');
      f.results.resultsByTest['t-1'] = [];
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(c.entries, isEmpty);
      expect(c.hasLoaded, isTrue);
    });

    test('test not in results phase: still loads (server decides)', () async {
      final f = _fixture('u-lead');
      f.tests.rows['t-1'] = Test(id: 't-1', createdBy: 'u-lead', title: 'Weekly', status: TestStatus.published, testMode: 'group', groupId: 'g-1');
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(c.test?.status, TestStatus.published);
    });

    test('loading to loaded transition', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      final fut = c.load();
      expect(c.isLoading, isTrue);
      await fut;
      expect(c.hasLoaded, isTrue);
      expect(c.isLoading, isFalse);
    });
  });

  group('G11 backward compatibility', () {
    test('G11 controller still works alongside G12', () async {
      final f = _fixture('u-lead');
      final c11 = GroupTestResultsController(groupId: 'g-1', testId: 't-1', results: f.results, tests: f.tests, groups: f.groups, currentUserId: 'u-lead');
      await c11.load();
      expect(c11.results.length, 2);
      expect(c11.canGenerateResults, isTrue);
      final c12 = _ctl(f, 'u-lead');
      await c12.load();
      expect(c12.entries.length, 2);
    });
  });

  group('widget', () {
    Future<GroupLeaderboardController> pump(WidgetTester tester, {required String user}) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = _fixture(user);
      final c = _ctl(f, user);
      await tester.pumpWidget(MaterialApp(home: GroupLeaderboardScreen(groupId: 'g-1', testId: 't-1', controller: c)));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('owner sees full leaderboard with participant count', (tester) async {
      final c = await pump(tester, user: 'u-owner');
      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_entry_u-b')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_entry_u-me')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_count')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('leader with analytics permission sees full leaderboard', (tester) async {
      final c = await pump(tester, user: 'u-lead');
      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_entry_u-b')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_entry_u-me')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_count')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('member sees only their own result (F-10)', (tester) async {
      final c = await pump(tester, user: 'u-me');
      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      expect(find.byKey(const Key('leaderboard_entry_u-me')), findsOneWidget);
      // F-10: member must NOT see other participants' entries
      expect(find.byKey(const Key('leaderboard_entry_u-b')), findsNothing);
      expect(find.byKey(const Key('my_leaderboard_summary')), findsOneWidget);
      expect(find.textContaining('Your result:'), findsOneWidget);
      // F-10: member must NOT see participant count or rank number
      expect(find.textContaining('ranked participant'), findsNothing);
      expect(find.textContaining('Your rank:'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('non-member: denied state', (tester) async {
      final c = await pump(tester, user: 'u-stranger');
      expect(find.byKey(const Key('leaderboard_denied')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('empty results: shows empty message', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = _fixture('u-lead');
      f.results.resultsByTest['t-1'] = [];
      final c = _ctl(f, 'u-lead');
      await tester.pumpWidget(MaterialApp(home: GroupLeaderboardScreen(groupId: 'g-1', testId: 't-1', controller: c)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leaderboard_empty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('loading state', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = _fixture('u-lead');
      final slow = _SlowResults(f.results);
      final c = GroupLeaderboardController(groupId: 'g-1', testId: 't-1', results: slow, tests: f.tests, groups: f.groups, currentUserId: 'u-lead');
      await tester.pumpWidget(MaterialApp(home: GroupLeaderboardScreen(groupId: 'g-1', testId: 't-1', controller: c)));
      await tester.pump();
      expect(find.byKey(const Key('leaderboard_loading')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leaderboard_list')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('owner: full leaderboard with participant count (no own entry, no summary)', (tester) async {
      final c = await pump(tester, user: 'u-owner');
      expect(find.byKey(const Key('leaderboard_count')), findsOneWidget);
      expect(find.text('2 ranked participants'), findsOneWidget);
      expect(find.byKey(const Key('my_leaderboard_summary')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

class _SlowResults extends _Delegating {
  _SlowResults(super.inner);
  @override
  Future<List<Map<String, dynamic>>> leaderboard(String testId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return inner.leaderboard(testId);
  }
}

class _FailingResults extends _Delegating {
  _FailingResults(super.inner);
  bool fail = true;
  @override
  Future<List<Map<String, dynamic>>> leaderboard(String testId) {
    if (fail) throw const DataError(message: 'NETWORK_DOWN');
    return inner.leaderboard(testId);
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
  Future<ResultBatch> generateResults(String testId) => inner.generateResults(testId);
  @override
  Future<List<Result>> resultsForTest(String testId) => inner.resultsForTest(testId);
  @override
  Future<List<Map<String, dynamic>>> leaderboard(String testId) => inner.leaderboard(testId);
  @override
  Future<AiCoachReport?> myAiReport(String testId) => inner.myAiReport(testId);
  @override
  Future<List<AiCoachReport>> allAiReports(String testId) => inner.allAiReports(testId);
  @override
  Future<ResultBatch?> batchForTest(String testId) => inner.batchForTest(testId);
  @override
  Future<CoachReportJob> requestCoachReports(String testId) => inner.requestCoachReports(testId);
}
