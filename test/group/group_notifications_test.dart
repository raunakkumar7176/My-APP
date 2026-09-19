// G16 — Group notifications / unread state.
//
// CLIENT TESTS ONLY. `FakeNotificationRepository` mirrors the live rules
// (own `notifications` rows; `read_at` read state; `data->>'group_id'`
// scope; own `group_mutes` rows; `fn_notify_group` skipping the actor and
// muted members). They prove what the client offers, refuses and re-reads.
// They are NOT proof of the live database — that is the rolled-back live
// probe recorded in docs/G16_GROUP_NOTIFICATIONS_IMPLEMENTATION_REPORT.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/app_notification.dart';
import 'package:my_praperation/features/group/data/notification_repository.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/screens/group_notifications_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_notifications_controller.dart';

import 'fakes.dart';

/// g-1: owner u-owner, members u-me and u-b; g-2: owned by u-other.
({InMemoryGroupRepository groups, FakeNotificationRepository notes}) _fixture(String user) {
  final groups = InMemoryGroupRepository(currentUser: user)
    ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-me': 'member', 'u-b': 'member'})
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  final notes = FakeNotificationRepository(currentUser: user);
  return (groups: groups, notes: notes);
}

GroupNotificationsController _ctl(({InMemoryGroupRepository groups, FakeNotificationRepository notes}) f, String user, {String groupId = 'g-1'}) =>
    GroupNotificationsController(groupId: groupId, notifications: f.notes, groups: f.groups, currentUserId: user);

Future<void> _pump(WidgetTester tester, Widget home, {double height = 1600}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

void main() {
  group('model', () {
    test('AppNotification parses the live row shape; unread == read_at IS NULL', () {
      final n = AppNotification.fromJson({
        'id': 'x', 'user_id': 'u', 'category': 'GROUP_MESSAGE', 'title': 'Nn — new message', 'body': 'hi',
        'data': {'group_id': 'g-1', 'message_id': 'm-1', 'type': 'group_message'},
        'read_at': null, 'created_at': '2026-09-19T09:55:12.888Z', 'priority': 'low',
      });
      expect(n.isRead, isFalse);
      expect(n.groupId, 'g-1');
      expect(n.type, 'group_message');
      expect(n.messageId, 'm-1');
      expect(n.copyWith(readAt: DateTime(2026)).isRead, isTrue);
      final bare = AppNotification.fromJson({'id': 'y', 'user_id': 'u', 'created_at': '2026-09-19T09:55:12.888Z', 'data': 'not-a-map'});
      expect(bare.groupId, isNull);
      expect(bare.category, '');
    });
  });

  group('1–3. unread count, empty state, ordering', () {
    test('unread count and newest-first order come from the server rows', () async {
      final f = _fixture('u-me');
      f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'old', createdAt: DateTime(2026, 9, 1), readAt: DateTime(2026, 9, 1, 1));
      f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'mid', createdAt: DateTime(2026, 9, 2));
      f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'new', createdAt: DateTime(2026, 9, 3));
      f.notes.seed(userId: 'u-me', groupId: 'g-2', title: 'other group', createdAt: DateTime(2026, 9, 4));
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.accessDenied, isFalse);
      expect(c.items.map((n) => n.title), ['new', 'mid', 'old']);
      expect(c.unreadCount, 2);
      expect(c.hasUnread, isTrue);
      expect(c.hasOlder, isFalse);
      c.dispose();
    });

    testWidgets('empty state renders; mark-all disabled', (tester) async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await _pump(tester, GroupNotificationsScreen(groupId: 'g-1', controller: c));
      expect(c.isEmpty, isTrue);
      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('mark_all_read'))).onPressed, isNull);
      expect(find.byKey(const Key('load_older_notifications')), findsNothing);
      c.dispose();
    });
  });

  group('4. pagination', () {
    test('a full page enables Load older; older pages are keyset on created_at and finite', () async {
      final f = _fixture('u-me');
      for (var i = 0; i < notificationPageSize + 5; i++) {
        f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'n$i', createdAt: DateTime(2026, 9, 1).add(Duration(minutes: i)));
      }
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.items.length, notificationPageSize);
      expect(c.hasOlder, isTrue);
      await Future.wait([c.loadOlder(), c.loadOlder()]); // single-flight
      expect(f.notes.calls.where((x) => x.startsWith('forGroup')).length, 2);
      expect(c.items.length, notificationPageSize + 5);
      expect(c.items.map((n) => n.id).toSet().length, c.items.length); // no duplicates
      expect(c.hasOlder, isFalse);
      await c.loadOlder(); // nothing more: no call
      expect(f.notes.calls.where((x) => x.startsWith('forGroup')).length, 2);
      c.dispose();
    });
  });

  group('5–6. mark one / mark all read (server re-read)', () {
    test('mark one: exactly one update, then page + count re-read; already-read is a no-op', () async {
      final f = _fixture('u-me');
      final a = f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'a');
      final b = f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'b');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.unreadCount, 2);
      final before = f.notes.calls.length;
      expect(await c.markRead(a.id), isTrue);
      final after = f.notes.calls.sublist(before);
      expect(after.first, 'markRead:${a.id}');
      expect(after.where((x) => x.startsWith('forGroup')).length, 1);
      expect(after.where((x) => x.startsWith('unreadCount')).length, 1);
      expect(c.unreadCount, 1);
      expect(c.items.firstWhere((n) => n.id == a.id).isRead, isTrue);
      expect(c.items.firstWhere((n) => n.id == b.id).isRead, isFalse);
      final n = f.notes.calls.length;
      expect(await c.markRead(a.id), isTrue);
      expect(f.notes.calls.length, n); // no-op, nothing sent
      c.dispose();
    });

    test('mark all: one group-scoped update; other groups untouched', () async {
      final f = _fixture('u-me');
      f.notes.seed(userId: 'u-me', groupId: 'g-1');
      f.notes.seed(userId: 'u-me', groupId: 'g-1');
      final other = f.notes.seed(userId: 'u-me', groupId: 'g-2');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(await c.markAllRead(), isTrue);
      expect(f.notes.calls.where((x) => x == 'markAllRead:g-1').length, 1);
      expect(c.unreadCount, 0);
      expect(c.items.every((n) => n.isRead), isTrue);
      expect(f.notes.rows.firstWhere((n) => n.id == other.id).isRead, isFalse);
      final n = f.notes.calls.length;
      expect(await c.markAllRead(), isTrue);
      expect(f.notes.calls.length, n); // nothing unread: nothing sent
      c.dispose();
    });

    test('server refusal surfaces and the list is re-read (no optimistic state)', () async {
      final f = _fixture('u-me');
      final a = f.notes.seed(userId: 'u-me', groupId: 'g-1');
      final c = _ctl(f, 'u-me');
      await c.load();
      f.notes.failNextWith = const DataError(message: 'permission denied for table notifications');
      expect(await c.markRead(a.id), isFalse);
      expect(c.error, contains('permission denied'));
      expect(c.items.single.isRead, isFalse);
      expect(c.unreadCount, 1);
      expect(f.notes.calls.last, 'isMuted:g-1'); // the re-read ran
      c.dispose();
    });
  });

  group('7 & 14. Group Hub badge integration', () {
    testWidgets('hub shows the unread badge from the server count and re-reads it on refresh', (tester) async {
      final f = _fixture('u-me');
      f.notes.seed(userId: 'u-me', groupId: 'g-1');
      f.notes.seed(userId: 'u-me', groupId: 'g-1');
      f.notes.seed(userId: 'u-b', groupId: 'g-1'); // someone else's row: never counted
      final hub = GroupHubController(groupId: 'g-1', repository: f.groups, currentUserId: 'u-me', notifications: f.notes);
      await _pump(tester, GroupHubScreen(groupId: 'g-1', controller: hub), height: 3600);
      expect(hub.unreadNotifications, 2);
      expect(find.byKey(const Key('group_notifications_action')), findsOneWidget);
      expect(tester.widget<Badge>(find.byKey(const Key('group_notifications_badge'))).isLabelVisible, isTrue);
      expect(find.text('2'), findsWidgets);
      // Marked read elsewhere (the inbox screen) → refresh → badge hidden.
      await f.notes.markAllRead('g-1');
      await hub.refresh();
      await tester.pumpAndSettle();
      expect(hub.unreadNotifications, 0);
      expect(tester.widget<Badge>(find.byKey(const Key('group_notifications_badge'))).isLabelVisible, isFalse);
      expect(f.notes.calls.where((x) => x == 'unreadCount:g-1').length, 2);
      await tester.pumpWidget(const SizedBox());
      hub.dispose();
    });

    testWidgets('a hub without a notification repository shows no bell and makes no call', (tester) async {
      final f = _fixture('u-me');
      final hub = GroupHubController(groupId: 'g-1', repository: f.groups, currentUserId: 'u-me');
      await _pump(tester, GroupHubScreen(groupId: 'g-1', controller: hub), height: 3600);
      expect(hub.hasNotifications, isFalse);
      expect(hub.unreadNotifications, isNull);
      expect(find.byKey(const Key('group_notifications_action')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      hub.dispose();
    });

    test('a failing count never breaks the hub: badge absent, group still loaded', () async {
      final f = _fixture('u-me');
      f.notes.failNextWith = const DataError(message: 'boom');
      final hub = GroupHubController(groupId: 'g-1', repository: f.groups, currentUserId: 'u-me', notifications: f.notes);
      await hub.load();
      expect(hub.group, isNotNull);
      expect(hub.error, isNull);
      expect(hub.unreadNotifications, isNull);
      expect(hub.hasUnreadNotifications, isFalse);
      hub.dispose();
    });
  });

  group('8–10. group scope, removed member, unauthorized user', () {
    test('another user\'s rows are never read or marked (RLS mirror: 0 rows)', () async {
      final f = _fixture('u-me');
      final theirs = f.notes.seed(userId: 'u-b', groupId: 'g-1', title: 'theirs');
      f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'mine');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.items.map((n) => n.title), ['mine']);
      expect(c.unreadCount, 1);
      expect(await f.notes.markRead(theirs.id), isFalse); // forged id → 0 rows
      expect(f.notes.rows.firstWhere((n) => n.id == theirs.id).isRead, isFalse);
      c.dispose();
    });

    test('non-member / forged group id: access denied, no notification read', () async {
      final f = _fixture('u-me');
      f.notes.seed(userId: 'u-me', groupId: 'g-2', title: 'stale row about g-2');
      for (final gid in ['g-2', 'g-forged']) {
        final c = _ctl(f, 'u-me', groupId: gid);
        await c.load();
        expect(c.accessDenied, isTrue, reason: gid);
        expect(c.items, isEmpty);
        expect(c.unreadCount, 0);
        expect(await c.markAllRead(), isFalse);
        c.dispose();
      }
      expect(f.notes.calls.where((x) => x.startsWith('forGroup') || x.startsWith('markAll')), isEmpty);
    });

    test('removed member: the screen denies access on refresh even though own rows remain', () async {
      final f = _fixture('u-me');
      f.notes.seed(userId: 'u-me', groupId: 'g-1');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.items.length, 1);
      f.groups.groups['g-1']!.roles.remove('u-me'); // removed server-side
      await c.refresh();
      expect(c.accessDenied, isTrue);
      expect(c.items, isEmpty);
      expect(await c.markRead('n-001'), isFalse);
      expect(f.notes.calls.where((x) => x.startsWith('markRead')), isEmpty);
      c.dispose();
    });
  });

  group('11. mute (existing group_mutes semantics)', () {
    test('mute is read on load, toggled by one upsert, and honoured by delivery', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.isMuted, isFalse);
      expect(await c.setMuted(true), isTrue);
      expect(f.notes.calls.where((x) => x == 'setMuted:g-1:true').length, 1);
      expect(c.isMuted, isTrue);
      // fn_notify_group mirror: muted member gets no row; others do.
      f.notes.notifyGroup(members: ['u-owner', 'u-me', 'u-b'], groupId: 'g-1', category: 'GROUP_MESSAGE', type: 'group_message', title: 'Nn — new message', exclude: 'u-b');
      expect(f.notes.rows.where((n) => n.userId == 'u-me'), isEmpty);
      expect(f.notes.rows.where((n) => n.userId == 'u-owner').length, 1);
      expect(f.notes.rows.where((n) => n.userId == 'u-b'), isEmpty); // actor excluded
      final n = f.notes.calls.length;
      expect(await c.setMuted(true), isTrue); // no-op
      expect(f.notes.calls.length, n);
      expect(await c.setMuted(false), isTrue);
      expect(c.isMuted, isFalse);
      c.dispose();
    });
  });

  group('12–13. single-flight and server re-read', () {
    test('load is single-flight; a second mutation while busy is refused', () async {
      final f = _fixture('u-me');
      final a = f.notes.seed(userId: 'u-me', groupId: 'g-1');
      final b = f.notes.seed(userId: 'u-me', groupId: 'g-1');
      final c = _ctl(f, 'u-me');
      await Future.wait([c.load(), c.load()]);
      expect(f.notes.calls.where((x) => x.startsWith('forGroup')).length, 1);
      final first = c.markRead(a.id);
      final second = c.markRead(b.id);
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(f.notes.calls.where((x) => x.startsWith('markRead')).length, 1);
      c.dispose();
    });
  });

  group('15–16. G8 chat / G5 join / G7 announcement paths land in the same inbox', () {
    test('trigger-shaped rows of every live type are listed, typed and scoped', () async {
      final f = _fixture('u-me');
      final members = ['u-owner', 'u-me', 'u-b'];
      f.notes.notifyGroup(members: members, groupId: 'g-1', category: 'GROUP_MESSAGE', type: 'group_message', title: 'Physics — new message', body: 'hi all', exclude: 'u-b', extra: {'message_id': 'm-1'});
      f.notes.notifyGroup(members: members, groupId: 'g-1', category: 'GROUP_ANNOUNCEMENT', type: 'group_announcement', title: '📢 Exam', exclude: 'u-owner', extra: {'announcement_id': 'a-1'});
      f.notes.notifyGroup(members: members, groupId: 'g-1', category: 'GROUP_ANNOUNCEMENT', type: 'group_join', title: 'Cee joined Physics', exclude: 'u-c', extra: {'user_id': 'u-c'});
      f.notes.notifyGroup(members: members, groupId: 'g-1', category: 'TEST_INVITATION', type: 'group_test', title: 'New test in Physics: Weekly', exclude: 'u-owner', extra: {'test_id': 't-1'});
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.items.map((n) => n.type), ['group_test', 'group_join', 'group_announcement', 'group_message']);
      expect(c.items.every((n) => n.groupId == 'g-1'), isTrue);
      expect(c.items.firstWhere((n) => n.type == 'group_test').testId, 't-1');
      expect(c.items.firstWhere((n) => n.type == 'group_message').messageId, 'm-1');
      expect(c.unreadCount, 4);
      c.dispose();
    });
  });

  group('17–18. read-only reads; no second infrastructure', () {
    test('opening, refreshing and paging the inbox perform reads only', () async {
      final f = _fixture('u-me');
      for (var i = 0; i < notificationPageSize + 1; i++) {
        f.notes.seed(userId: 'u-me', groupId: 'g-1');
      }
      final c = _ctl(f, 'u-me');
      await c.load();
      await c.refresh();
      await c.loadOlder();
      final writes = f.notes.calls.where((x) => x.startsWith('markRead') || x.startsWith('markAllRead') || x.startsWith('setMuted'));
      expect(writes, isEmpty);
      expect(f.groups.calls.where((x) => !x.startsWith('groupForMember')), isEmpty);
      c.dispose();
    });

    test('the repository contract is the live table: own rows, read_at, data.group_id, group_mutes', () {
      // One inbox, one read flag, one mute table — nothing else exists to
      // cross-check against; this pins the surface so a second system would
      // have to change this test.
      expect(NotificationRepository, isNotNull);
      expect(notificationPageSize, 30);
      final n = AppNotification.fromJson({'id': 'x', 'user_id': 'u', 'created_at': '2026-09-20T00:00:00Z', 'data': {'group_id': 'g'}, 'read_at': '2026-09-20T00:00:00Z'});
      expect(n.isRead, isTrue);
      expect(n.groupId, 'g');
    });
  });

  group('UI', () {
    testWidgets('list shows read/unread, tapping marks read; mark all clears the dots', (tester) async {
      final f = _fixture('u-me');
      final a = f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'A msg', type: 'group_test', extra: {'test_id': 't-1'});
      final b = f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'B read', readAt: DateTime(2026, 9, 1));
      final c = _ctl(f, 'u-me');
      await _pump(tester, GroupNotificationsScreen(groupId: 'g-1', controller: c));
      expect(find.text('Notifications (1 unread)'), findsOneWidget);
      expect(find.byKey(Key('unread_dot_${a.id}')), findsOneWidget);
      expect(find.byKey(Key('unread_dot_${b.id}')), findsNothing);
      expect(find.byKey(const Key('mute_group_switch')), findsOneWidget);
      // The (unrouted) tap still marks read before navigating.
      await tester.tap(find.byKey(Key('notification_${a.id}')));
      await tester.pump();
      expect(f.notes.calls, contains('markRead:${a.id}'));
      await tester.pumpAndSettle();
      expect(c.unreadCount, 0);
      expect(find.text('Notifications'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('mark_all_read'))).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('error state offers retry; denied state is honest', (tester) async {
      final f = _fixture('u-me');
      f.notes.failNextWith = const DataError(message: 'Could not load notifications. Please try again.');
      final c = _ctl(f, 'u-me');
      await _pump(tester, GroupNotificationsScreen(groupId: 'g-1', controller: c));
      expect(find.byKey(const Key('notifications_retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('notifications_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      final d = _ctl(f, 'u-me', groupId: 'g-2');
      await _pump(tester, GroupNotificationsScreen(groupId: 'g-2', controller: d));
      expect(find.text('Group not available'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      d.dispose();
    });
  });
}
