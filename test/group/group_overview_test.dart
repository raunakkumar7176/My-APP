// Group Hub Phase 3 — Overview: study-test counts, the next upcoming
// test, and the caller's own recent activity for the group. Reuses the
// existing `GroupTestManagement.sectionFor` classification and the
// existing `notifications.forGroup` read — no new backend, no duplicated
// section logic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import '../r4_restart/fakes.dart';
import 'fakes.dart';

final _now = DateTime(2026, 9, 19, 12);

Test _t(
  String id, {
  required String by,
  String group = 'g-1',
  TestStatus status = TestStatus.draft,
  DateTime? startsAt,
  DateTime? endsAt,
}) => Test(
  id: id,
  createdBy: by,
  title: 'Test $id',
  status: status,
  testMode: 'group',
  groupId: group,
  durationSec: 600,
  marksPerQuestion: 1,
  negativeMarks: 0,
  startsAt: startsAt,
  endsAt: endsAt,
);

({InMemoryGroupRepository groups, FakeTestRepository tests}) _fixture({
  String user = 'u-me',
}) {
  final groups = InMemoryGroupRepository(currentUser: user)
    ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-me': 'member'});
  final tests = FakeTestRepository()
    ..currentUser = user
    ..groups = groups;
  return (groups: groups, tests: tests);
}

GroupHubController _hub(
  ({InMemoryGroupRepository groups, FakeTestRepository tests}) f,
  String user,
) => GroupHubController(
  groupId: 'g-1',
  repository: f.groups,
  tests: f.tests,
  currentUserId: user,
  now: () => _now,
);

void main() {
  group('upcomingTest / test counts', () {
    test('picks the earliest upcoming test, ignores live/previous/draft', () async {
      final f = _fixture();
      f.tests.rows.addAll({
        for (final t in [
          _t('t-draft', by: 'u-owner'),
          _t('t-later', by: 'u-owner', status: TestStatus.published, startsAt: _now.add(const Duration(days: 5))),
          _t('t-soon', by: 'u-owner', status: TestStatus.published, startsAt: _now.add(const Duration(hours: 2))),
          _t('t-live', by: 'u-owner', status: TestStatus.published, startsAt: _now.subtract(const Duration(minutes: 1)), endsAt: _now.add(const Duration(hours: 1))),
          _t('t-ended', by: 'u-owner', status: TestStatus.ended),
        ])
          t.id: t,
      });
      final c = _hub(f, 'u-me');

      await c.load();

      expect(c.upcomingTest?.id, 't-soon');
      expect(c.upcomingTestCount, 2);
      expect(c.liveTestCount, 1);
      expect(c.previousTestCount, 1);
      c.dispose();
    });

    test('no tests at all: upcomingTest is null, every count is 0', () async {
      final f = _fixture();
      final c = _hub(f, 'u-me');

      await c.load();

      expect(c.upcomingTest, isNull);
      expect(c.upcomingTestCount, 0);
      expect(c.liveTestCount, 0);
      expect(c.previousTestCount, 0);
      c.dispose();
    });

    test('a test from a different group is never counted here', () async {
      final f = _fixture();
      f.tests.rows['t-foreign'] = _t(
        't-foreign',
        by: 'u-other',
        group: 'g-2',
        status: TestStatus.published,
        startsAt: _now.add(const Duration(hours: 1)),
      );
      final c = _hub(f, 'u-me');

      await c.load();

      expect(c.upcomingTest, isNull);
      expect(c.upcomingTestCount, 0);
      c.dispose();
    });

    test('without an injected TestRepository, Overview data is simply absent (never a guess or a crash)', () async {
      final f = _fixture();
      final c = GroupHubController(groupId: 'g-1', repository: f.groups, currentUserId: 'u-me');

      await c.load();

      expect(c.upcomingTest, isNull);
      expect(c.upcomingTestCount, 0);
      c.dispose();
    });
  });

  group('recentActivity', () {
    test('null when the hub has no notification repository (never a guessed empty list)', () async {
      final f = _fixture();
      final c = _hub(f, 'u-me');
      await c.load();
      expect(c.recentActivity, isNull);
      c.dispose();
    });

    test('surfaces the caller\'s own recent notifications for this group, newest first', () async {
      final f = _fixture();
      final notif = FakeNotificationRepository(currentUser: 'u-me')
        ..seed(userId: 'u-me', groupId: 'g-1', title: 'Older', createdAt: DateTime(2026, 1, 1))
        ..seed(userId: 'u-me', groupId: 'g-1', title: 'Newer', createdAt: DateTime(2026, 1, 2))
        ..seed(userId: 'u-other', groupId: 'g-1', title: 'Not mine', createdAt: DateTime(2026, 1, 3));
      final c = GroupHubController(
        groupId: 'g-1',
        repository: f.groups,
        currentUserId: 'u-me',
        notifications: notif,
        now: () => _now,
      );

      await c.load();

      final activity = c.recentActivity;
      expect(activity, isNotNull);
      expect(activity!.map((n) => n.title), ['Newer', 'Older']);
      c.dispose();
    });
  });

  group('GroupHubScreen: Overview section rendering', () {
    testWidgets('shows live/upcoming/completed counts and the next upcoming test card', (tester) async {
      final f = _fixture();
      f.tests.rows['t-soon'] = _t(
        't-soon',
        by: 'u-owner',
        status: TestStatus.published,
        startsAt: _now.add(const Duration(hours: 2)),
      );
      final c = _hub(f, 'u-me');

      await tester.pumpWidget(MaterialApp(home: GroupHubScreen(groupId: 'g-1', controller: c)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('overview_stats_row')), findsOneWidget);
      expect(find.byKey(const Key('overview_upcoming_test_t-soon')), findsOneWidget);
      expect(find.text('Test t-soon'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('shows the empty-upcoming-test message when there is none', (tester) async {
      final f = _fixture();
      final c = _hub(f, 'u-me');

      await tester.pumpWidget(MaterialApp(home: GroupHubScreen(groupId: 'g-1', controller: c)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('overview_no_upcoming_test')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('tapping View Test navigates to /tests/:id', (tester) async {
      final f = _fixture();
      f.tests.rows['t-soon'] = _t(
        't-soon',
        by: 'u-owner',
        status: TestStatus.published,
        startsAt: _now.add(const Duration(hours: 2)),
      );
      final c = _hub(f, 'u-me');

      final router = GoRouter(
        initialLocation: '/groups/g-1',
        routes: [
          GoRoute(
            path: '/groups/:groupId',
            builder: (_, _) => GroupHubScreen(groupId: 'g-1', controller: c),
          ),
          GoRoute(
            path: '/tests/:testId',
            builder: (_, state) =>
                Scaffold(body: Text('Test detail: ${state.pathParameters['testId']}')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('overview_view_test_t-soon')));
      await tester.pumpAndSettle();

      expect(find.text('Test detail: t-soon'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
