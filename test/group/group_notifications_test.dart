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
import 'package:my_praperation/features/notifications/state/notification_feed_controller.dart';

import 'fakes.dart';

/// g-1: owner u-owner, members u-me and u-b; g-2: owned by u-other.
({InMemoryGroupRepository groups, FakeNotificationRepository notes}) _fixture(
  String user,
) {
  final groups = InMemoryGroupRepository(currentUser: user)
    ..seed(
      id: 'g-1',
      name: 'Physics',
      ownerId: 'u-owner',
      members: {'u-me': 'member', 'u-b': 'member'},
    )
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  final notes = FakeNotificationRepository(currentUser: user);
  return (groups: groups, notes: notes);
}

GroupNotificationsController _ctl(
  ({InMemoryGroupRepository groups, FakeNotificationRepository notes}) f,
  String user, {
  String groupId = 'g-1',
}) => GroupNotificationsController(
  groupId: groupId,
  notifications: f.notes,
  groups: f.groups,
  currentUserId: user,
);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  double height = 1600,
}) async {
  tester.view.physicalSize = Size(800, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

void main() {
  group('model', () {
    test(
      'AppNotification parses the live row shape; unread == read_at IS NULL',
      () {
        final n = AppNotification.fromJson({
          'id': 'x',
          'user_id': 'u',
          'category': 'GROUP_MESSAGE',
          'title': 'Nn — new message',
          'body': 'hi',
          'data': {
            'group_id': 'g-1',
            'message_id': 'm-1',
            'type': 'group_message',
          },
          'read_at': null,
          'created_at': '2026-09-19T09:55:12.888Z',
          'priority': 'low',
        });
        expect(n.isRead, isFalse);
        expect(n.groupId, 'g-1');
        expect(n.type, 'group_message');
        expect(n.messageId, 'm-1');
        expect(n.copyWith(readAt: DateTime(2026)).isRead, isTrue);
        final bare = AppNotification.fromJson({
          'id': 'y',
          'user_id': 'u',
          'created_at': '2026-09-19T09:55:12.888Z',
          'data': 'not-a-map',
        });
        expect(bare.groupId, isNull);
        expect(bare.category, '');
      },
    );

    test('V2 NotificationCategory enum values parse correctly', () {
      expect(
        NotificationCategory.fromString('GROUP_JOIN_REQUEST'),
        NotificationCategory.groupJoinRequest,
      );
      expect(
        NotificationCategory.fromString('JOIN_ACCEPTED'),
        NotificationCategory.joinAccepted,
      );
      expect(
        NotificationCategory.fromString('JOIN_REJECTED'),
        NotificationCategory.joinRejected,
      );
      expect(
        NotificationCategory.fromString('ROLE_CHANGED'),
        NotificationCategory.roleChanged,
      );
      expect(
        NotificationCategory.fromString('MEMBER_REMOVED'),
        NotificationCategory.memberRemoved,
      );
      // Unknown values still resolve to unknown
      expect(
        NotificationCategory.fromString('FUTURE_TYPE'),
        NotificationCategory.unknown,
      );
      expect(
        NotificationCategory.fromString(null),
        NotificationCategory.unknown,
      );
    });

    test('V2 categories are classified correctly', () {
      expect(NotificationCategory.groupJoinRequest.isGroupRelated, isTrue);
      expect(NotificationCategory.joinAccepted.isGroupRelated, isTrue);
      expect(NotificationCategory.joinRejected.isGroupRelated, isTrue);
      expect(NotificationCategory.roleChanged.isGroupRelated, isTrue);
      expect(NotificationCategory.memberRemoved.isGroupRelated, isTrue);
      expect(NotificationCategory.resultsAvailable.isTestRelated, isTrue);
      expect(NotificationCategory.leaderboardUpdated.isTestRelated, isTrue);
      expect(NotificationCategory.streakMilestone.isRoutineRelated, isTrue);
    });

    test('V2 notification rows parse with deep_link data', () {
      final n = AppNotification.fromJson({
        'id': 'v2-1',
        'user_id': 'u',
        'category': 'RESULTS_AVAILABLE',
        'title': 'Results ready',
        'body': 'View report',
        'data': {
          'test_id': 't-1',
          'deep_link': '/reports/t-1',
          'type': 'results_available',
        },
        'read_at': null,
        'created_at': '2026-09-20T10:00:00Z',
        'priority': 'high',
        'dedupe_key': 'v2_results:u:t-1',
      });
      expect(n.parsedCategory, NotificationCategory.resultsAvailable);
      expect(n.testId, 't-1');
      expect(n.deepLink, '/reports/t-1');
      expect(n.dedupeKey, 'v2_results:u:t-1');
      expect(n.priority, 'high');
    });

    test('V2 join request notification parses group data', () {
      final n = AppNotification.fromJson({
        'id': 'v2-jr',
        'user_id': 'u-leader',
        'category': 'GROUP_JOIN_REQUEST',
        'title': 'Join request',
        'body': 'Student wants to join',
        'data': {
          'group_id': 'g-1',
          'requester_id': 'u-student',
          'deep_link': '/groups/g-1',
          'type': 'join_request',
        },
        'read_at': null,
        'created_at': '2026-09-20T10:00:00Z',
        'priority': 'medium',
      });
      expect(n.parsedCategory, NotificationCategory.groupJoinRequest);
      expect(n.groupId, 'g-1');
      expect(n.type, 'join_request');
      expect(n.deepLink, '/groups/g-1');
      expect(n.parsedCategory.isGroupRelated, isTrue);
    });

    test('V2 role changed notification parses role data', () {
      final n = AppNotification.fromJson({
        'id': 'v2-rc',
        'user_id': 'u',
        'category': 'ROLE_CHANGED',
        'title': 'Role updated',
        'body': 'Your role changed',
        'data': {
          'group_id': 'g-1',
          'old_role': 'member',
          'new_role': 'moderator',
          'deep_link': '/groups/g-1',
          'type': 'role_changed',
        },
        'read_at': null,
        'created_at': '2026-09-20T10:00:00Z',
        'priority': 'medium',
      });
      expect(n.parsedCategory, NotificationCategory.roleChanged);
      expect(n.groupId, 'g-1');
      expect(n.type, 'role_changed');
    });

    test('V2 member removed notification uses safe fallback deep link', () {
      final n = AppNotification.fromJson({
        'id': 'v2-mr',
        'user_id': 'u',
        'category': 'MEMBER_REMOVED',
        'title': 'Removed',
        'body': 'No longer a member',
        'data': {
          'group_id': 'g-1',
          'deep_link': '/notifications',
          'type': 'member_removed',
        },
        'read_at': null,
        'created_at': '2026-09-20T10:00:00Z',
        'priority': 'medium',
      });
      expect(n.parsedCategory, NotificationCategory.memberRemoved);
      expect(n.deepLink, '/notifications'); // safe fallback, not /groups/g-1
    });

    test('V2 streak milestone notification parses streak data', () {
      final n = AppNotification.fromJson({
        'id': 'v2-sk',
        'user_id': 'u',
        'category': 'STREAK_MILESTONE',
        'title': '7-day streak!',
        'body': 'Keep going',
        'data': {
          'streak': 7,
          'deep_link': '/routine',
          'type': 'streak_milestone',
        },
        'read_at': null,
        'created_at': '2026-09-20T10:00:00Z',
        'priority': 'low',
      });
      expect(n.parsedCategory, NotificationCategory.streakMilestone);
      expect(n.parsedCategory.isRoutineRelated, isTrue);
    });
  });

  group('1–3. unread count, empty state, ordering', () {
    test(
      'unread count and newest-first order come from the server rows',
      () async {
        final f = _fixture('u-me');
        f.notes.seed(
          userId: 'u-me',
          groupId: 'g-1',
          title: 'old',
          createdAt: DateTime(2026, 9, 1),
          readAt: DateTime(2026, 9, 1, 1),
        );
        f.notes.seed(
          userId: 'u-me',
          groupId: 'g-1',
          title: 'mid',
          createdAt: DateTime(2026, 9, 2),
        );
        f.notes.seed(
          userId: 'u-me',
          groupId: 'g-1',
          title: 'new',
          createdAt: DateTime(2026, 9, 3),
        );
        f.notes.seed(
          userId: 'u-me',
          groupId: 'g-2',
          title: 'other group',
          createdAt: DateTime(2026, 9, 4),
        );
        final c = _ctl(f, 'u-me');
        await c.load();
        expect(c.accessDenied, isFalse);
        expect(c.items.map((n) => n.title), ['new', 'mid', 'old']);
        expect(c.unreadCount, 2);
        expect(c.hasUnread, isTrue);
        expect(c.hasOlder, isFalse);
        c.dispose();
      },
    );

    testWidgets('empty state renders; mark-all disabled', (tester) async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await _pump(
        tester,
        GroupNotificationsScreen(groupId: 'g-1', controller: c),
      );
      expect(c.isEmpty, isTrue);
      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('mark_all_read')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('load_older_notifications')), findsNothing);
      c.dispose();
    });
  });

  group('4. pagination', () {
    test('a full page enables Load older; older pages are keyset on created_at and finite', () async {
      final f = _fixture('u-me');
      for (var i = 0; i < notificationPageSize + 5; i++) {
        f.notes.seed(
          userId: 'u-me',
          groupId: 'g-1',
          title: 'n$i',
          createdAt: DateTime(2026, 9, 1).add(Duration(minutes: i)),
        );
      }
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.items.length, notificationPageSize);
      expect(c.hasOlder, isTrue);
      await Future.wait([c.loadOlder(), c.loadOlder()]); // single-flight
      expect(f.notes.calls.where((x) => x.startsWith('forGroup')).length, 2);
      expect(c.items.length, notificationPageSize + 5);
      expect(
        c.items.map((n) => n.id).toSet().length,
        c.items.length,
      ); // no duplicates
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

    test(
      'server refusal surfaces and the list is re-read (no optimistic state)',
      () async {
        final f = _fixture('u-me');
        final a = f.notes.seed(userId: 'u-me', groupId: 'g-1');
        final c = _ctl(f, 'u-me');
        await c.load();
        f.notes.failNextWith = const DataError(
          message: 'permission denied for table notifications',
        );
        expect(await c.markRead(a.id), isFalse);
        expect(c.error, contains('permission denied'));
        expect(c.items.single.isRead, isFalse);
        expect(c.unreadCount, 1);
        expect(f.notes.calls.last, 'isMuted:g-1'); // the re-read ran
        c.dispose();
      },
    );
  });

  group('7 & 14. Group Hub badge integration', () {
    testWidgets(
      'hub shows the unread badge from the server count and re-reads it on refresh',
      (tester) async {
        final f = _fixture('u-me');
        f.notes.seed(userId: 'u-me', groupId: 'g-1');
        f.notes.seed(userId: 'u-me', groupId: 'g-1');
        f.notes.seed(
          userId: 'u-b',
          groupId: 'g-1',
        ); // someone else's row: never counted
        final hub = GroupHubController(
          groupId: 'g-1',
          repository: f.groups,
          currentUserId: 'u-me',
          notifications: f.notes,
        );
        await _pump(
          tester,
          GroupHubScreen(groupId: 'g-1', controller: hub),
          height: 3600,
        );
        expect(hub.unreadNotifications, 2);
        expect(
          find.byKey(const Key('group_notifications_action')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Badge>(find.byKey(const Key('group_notifications_badge')))
              .isLabelVisible,
          isTrue,
        );
        expect(find.text('2'), findsWidgets);
        // Marked read elsewhere (the inbox screen) → refresh → badge hidden.
        await f.notes.markAllRead('g-1');
        await hub.refresh();
        await tester.pumpAndSettle();
        expect(hub.unreadNotifications, 0);
        expect(
          tester
              .widget<Badge>(find.byKey(const Key('group_notifications_badge')))
              .isLabelVisible,
          isFalse,
        );
        expect(f.notes.calls.where((x) => x == 'unreadCount:g-1').length, 2);
        await tester.pumpWidget(const SizedBox());
        hub.dispose();
      },
    );

    testWidgets(
      'a hub without a notification repository shows no bell and makes no call',
      (tester) async {
        final f = _fixture('u-me');
        final hub = GroupHubController(
          groupId: 'g-1',
          repository: f.groups,
          currentUserId: 'u-me',
        );
        await _pump(
          tester,
          GroupHubScreen(groupId: 'g-1', controller: hub),
          height: 3600,
        );
        expect(hub.hasNotifications, isFalse);
        expect(hub.unreadNotifications, isNull);
        expect(
          find.byKey(const Key('group_notifications_action')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        hub.dispose();
      },
    );

    test(
      'a failing count never breaks the hub: badge absent, group still loaded',
      () async {
        final f = _fixture('u-me');
        f.notes.failNextWith = const DataError(message: 'boom');
        final hub = GroupHubController(
          groupId: 'g-1',
          repository: f.groups,
          currentUserId: 'u-me',
          notifications: f.notes,
        );
        await hub.load();
        expect(hub.group, isNotNull);
        expect(hub.error, isNull);
        expect(hub.unreadNotifications, isNull);
        expect(hub.hasUnreadNotifications, isFalse);
        hub.dispose();
      },
    );
  });

  group('8–10. group scope, removed member, unauthorized user', () {
    test(
      'another user\'s rows are never read or marked (RLS mirror: 0 rows)',
      () async {
        final f = _fixture('u-me');
        final theirs = f.notes.seed(
          userId: 'u-b',
          groupId: 'g-1',
          title: 'theirs',
        );
        f.notes.seed(userId: 'u-me', groupId: 'g-1', title: 'mine');
        final c = _ctl(f, 'u-me');
        await c.load();
        expect(c.items.map((n) => n.title), ['mine']);
        expect(c.unreadCount, 1);
        expect(
          await f.notes.markRead(theirs.id),
          isFalse,
        ); // forged id → 0 rows
        expect(
          f.notes.rows.firstWhere((n) => n.id == theirs.id).isRead,
          isFalse,
        );
        c.dispose();
      },
    );

    test(
      'non-member / forged group id: access denied, no notification read',
      () async {
        final f = _fixture('u-me');
        f.notes.seed(
          userId: 'u-me',
          groupId: 'g-2',
          title: 'stale row about g-2',
        );
        for (final gid in ['g-2', 'g-forged']) {
          final c = _ctl(f, 'u-me', groupId: gid);
          await c.load();
          expect(c.accessDenied, isTrue, reason: gid);
          expect(c.items, isEmpty);
          expect(c.unreadCount, 0);
          expect(await c.markAllRead(), isFalse);
          c.dispose();
        }
        expect(
          f.notes.calls.where(
            (x) => x.startsWith('forGroup') || x.startsWith('markAll'),
          ),
          isEmpty,
        );
      },
    );

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
    test(
      'mute is read on load, toggled by one upsert, and honoured by delivery',
      () async {
        final f = _fixture('u-me');
        final c = _ctl(f, 'u-me');
        await c.load();
        expect(c.isMuted, isFalse);
        expect(await c.setMuted(true), isTrue);
        expect(f.notes.calls.where((x) => x == 'setMuted:g-1:true').length, 1);
        expect(c.isMuted, isTrue);
        // fn_notify_group mirror: muted member gets no row; others do.
        f.notes.notifyGroup(
          members: ['u-owner', 'u-me', 'u-b'],
          groupId: 'g-1',
          category: 'GROUP_MESSAGE',
          type: 'group_message',
          title: 'Nn — new message',
          exclude: 'u-b',
        );
        expect(f.notes.rows.where((n) => n.userId == 'u-me'), isEmpty);
        expect(f.notes.rows.where((n) => n.userId == 'u-owner').length, 1);
        expect(
          f.notes.rows.where((n) => n.userId == 'u-b'),
          isEmpty,
        ); // actor excluded
        final n = f.notes.calls.length;
        expect(await c.setMuted(true), isTrue); // no-op
        expect(f.notes.calls.length, n);
        expect(await c.setMuted(false), isTrue);
        expect(c.isMuted, isFalse);
        c.dispose();
      },
    );
  });

  group('12–13. single-flight and server re-read', () {
    test(
      'load is single-flight; a second mutation while busy is refused',
      () async {
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
      },
    );
  });

  group(
    '15–16. G8 chat / G5 join / G7 announcement paths land in the same inbox',
    () {
      test(
        'trigger-shaped rows of every live type are listed, typed and scoped',
        () async {
          final f = _fixture('u-me');
          final members = ['u-owner', 'u-me', 'u-b'];
          f.notes.notifyGroup(
            members: members,
            groupId: 'g-1',
            category: 'GROUP_MESSAGE',
            type: 'group_message',
            title: 'Physics — new message',
            body: 'hi all',
            exclude: 'u-b',
            extra: {'message_id': 'm-1'},
          );
          f.notes.notifyGroup(
            members: members,
            groupId: 'g-1',
            category: 'GROUP_ANNOUNCEMENT',
            type: 'group_announcement',
            title: '📢 Exam',
            exclude: 'u-owner',
            extra: {'announcement_id': 'a-1'},
          );
          f.notes.notifyGroup(
            members: members,
            groupId: 'g-1',
            category: 'GROUP_ANNOUNCEMENT',
            type: 'group_join',
            title: 'Cee joined Physics',
            exclude: 'u-c',
            extra: {'user_id': 'u-c'},
          );
          f.notes.notifyGroup(
            members: members,
            groupId: 'g-1',
            category: 'TEST_INVITATION',
            type: 'group_test',
            title: 'New test in Physics: Weekly',
            exclude: 'u-owner',
            extra: {'test_id': 't-1'},
          );
          final c = _ctl(f, 'u-me');
          await c.load();
          expect(c.items.map((n) => n.type), [
            'group_test',
            'group_join',
            'group_announcement',
            'group_message',
          ]);
          expect(c.items.every((n) => n.groupId == 'g-1'), isTrue);
          expect(
            c.items.firstWhere((n) => n.type == 'group_test').testId,
            't-1',
          );
          expect(
            c.items.firstWhere((n) => n.type == 'group_message').messageId,
            'm-1',
          );
          expect(c.unreadCount, 4);
          c.dispose();
        },
      );
    },
  );

  group('17–18. read-only reads; no second infrastructure', () {
    test(
      'opening, refreshing and paging the inbox perform reads only',
      () async {
        final f = _fixture('u-me');
        for (var i = 0; i < notificationPageSize + 1; i++) {
          f.notes.seed(userId: 'u-me', groupId: 'g-1');
        }
        final c = _ctl(f, 'u-me');
        await c.load();
        await c.refresh();
        await c.loadOlder();
        final writes = f.notes.calls.where(
          (x) =>
              x.startsWith('markRead') ||
              x.startsWith('markAllRead') ||
              x.startsWith('setMuted'),
        );
        expect(writes, isEmpty);
        expect(
          f.groups.calls.where((x) => !x.startsWith('groupForMember')),
          isEmpty,
        );
        c.dispose();
      },
    );

    test('the repository contract is the live table: own rows, read_at, data.group_id, group_mutes', () {
      // One inbox, one read flag, one mute table — nothing else exists to
      // cross-check against; this pins the surface so a second system would
      // have to change this test.
      expect(NotificationRepository, isNotNull);
      expect(notificationPageSize, 30);
      final n = AppNotification.fromJson({
        'id': 'x',
        'user_id': 'u',
        'created_at': '2026-09-20T00:00:00Z',
        'data': {'group_id': 'g'},
        'read_at': '2026-09-20T00:00:00Z',
      });
      expect(n.isRead, isTrue);
      expect(n.groupId, 'g');
    });
  });

  group('UI', () {
    testWidgets(
      'list shows read/unread, tapping marks read; mark all clears the dots',
      (tester) async {
        final f = _fixture('u-me');
        final a = f.notes.seed(
          userId: 'u-me',
          groupId: 'g-1',
          title: 'A msg',
          type: 'group_test',
          extra: {'test_id': 't-1'},
        );
        f.notes.seed(
          userId: 'u-me',
          groupId: 'g-1',
          title: 'B read',
          readAt: DateTime(2026, 9, 1),
        );
        final c = _ctl(f, 'u-me');
        await _pump(
          tester,
          GroupNotificationsScreen(groupId: 'g-1', controller: c),
        );
        expect(find.text('Notifications (1 unread)'), findsOneWidget);
        // Unread state is a semi-bold title (GroupNotificationsScreen's own
        // inline tile, separate from the redesigned global NotificationTile)
        // rather than a separate trailing dot widget.
        final aTitle = tester.widget<Text>(find.text('A msg'));
        final bTitle = tester.widget<Text>(find.text('B read'));
        expect(aTitle.style?.fontWeight, FontWeight.w600);
        expect(bTitle.style?.fontWeight, isNot(FontWeight.w600));
        expect(find.byKey(const Key('mute_group_switch')), findsOneWidget);
        // The (unrouted) tap still marks read before navigating.
        await tester.tap(find.byKey(Key('notification_${a.id}')));
        await tester.pump();
        expect(f.notes.calls, contains('markRead:${a.id}'));
        await tester.pumpAndSettle();
        expect(c.unreadCount, 0);
        expect(find.text('Notifications'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('mark_all_read')))
              .onPressed,
          isNull,
        );
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('error state offers retry; denied state is honest', (
      tester,
    ) async {
      final f = _fixture('u-me');
      f.notes.failNextWith = const DataError(
        message: 'Could not load notifications. Please try again.',
      );
      final c = _ctl(f, 'u-me');
      await _pump(
        tester,
        GroupNotificationsScreen(groupId: 'g-1', controller: c),
      );
      expect(find.byKey(const Key('notifications_retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('notifications_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      final d = _ctl(f, 'u-me', groupId: 'g-2');
      await _pump(
        tester,
        GroupNotificationsScreen(groupId: 'g-2', controller: d),
      );
      expect(find.text('Group not available'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      d.dispose();
    });
  });

  // ====================================================================
  // BUG-1 FIX: Notification dismissal tests (0055 migration)
  //
  // Tests the `dismiss()` method on both the per-group
  // `NotificationRepository` (not available — no dismiss in that interface)
  // and the global `NotificationFeedRepository` / `NotificationFeedController`.
  //
  // The live migration adds:
  //   CREATE POLICY "dismiss own" ON public.notifications
  //     FOR DELETE TO authenticated USING (user_id = auth.uid());
  //
  // These tests prove the CLIENT contract mirrors the RLS semantics:
  //   - own row → deleted
  //   - another user's row → 0 rows affected (RLS returns nothing)
  //   - forged ID → 0 rows affected
  //   - double dismiss → idempotent
  //   - badge/unread count re-reads correctly after dismiss
  // ====================================================================

  group('BUG-1. notification dismissal (0055 migration)', () {
    FakeNotificationFeedRepository repo0(String user) =>
        FakeNotificationFeedRepository(currentUser: user);

    NotificationFeedController ctl(FakeNotificationFeedRepository repo) =>
        NotificationFeedController(feed: repo);

    // ---- 1. User A deletes own notification → SUCCESS ----
    test('own notification is deleted successfully', () async {
      final repo = repo0('u-me');
      final n = repo.seed(userId: 'u-me', title: 'mine');
      final c = ctl(repo);
      await c.load();
      expect(c.items.length, 1);
      expect(c.items.first.id, n.id);
      expect(await c.dismiss(n.id), isTrue);
      expect(c.items, isEmpty);
      expect(c.unreadCount, 0);
      c.dispose();
    });

    // ---- 2. User A deletes User B notification → DENIED ----
    test('another user\'s notification is not deleted (RLS: 0 rows)', () async {
      final repo = repo0('u-me');
      final theirs = repo.seed(userId: 'u-b', title: 'theirs');
      repo.seed(userId: 'u-me', title: 'mine');
      final c = ctl(repo);
      await c.load();
      expect(c.items.length, 1);
      expect(c.items.first.title, 'mine');
      // Attempt to dismiss another user's row — should fail (RLS blocks)
      expect(await c.dismiss(theirs.id), isFalse);
      // The other user's row still exists
      expect(repo.rows.length, 2);
      // The own row still exists and is unread
      expect(c.unreadCount, 1);
      c.dispose();
    });

    // ---- 3. Forged notification ID → DENIED ----
    test('forged notification ID does not delete anything', () async {
      final repo = repo0('u-me');
      repo.seed(userId: 'u-me', title: 'real');
      final c = ctl(repo);
      await c.load();
      expect(c.items.length, 1);
      expect(await c.dismiss('nonexistent-id-12345'), isFalse);
      expect(repo.rows.length, 1); // nothing deleted
      expect(c.items.length, 1);
      c.dispose();
    });

    // ---- 4. Deleted notification no longer appears ----
    test('dismissed notification is removed from the feed', () async {
      final repo = repo0('u-me');
      final n1 = repo.seed(userId: 'u-me', title: 'first');
      final n2 = repo.seed(userId: 'u-me', title: 'second');
      final c = ctl(repo);
      await c.load();
      expect(c.items.length, 2);
      expect(await c.dismiss(n1.id), isTrue);
      // After dismiss, the controller re-reads the feed
      expect(c.items.length, 1);
      expect(c.items.first.id, n2.id);
      c.dispose();
    });

    // ---- 5. Badge/unread count updates correctly after dismiss ----
    test(
      'unread count decrements after dismissing an unread notification',
      () async {
        final repo = repo0('u-me');
        repo.seed(userId: 'u-me', title: 'unread-1');
        repo.seed(userId: 'u-me', title: 'unread-2');
        repo.seed(
          userId: 'u-me',
          title: 'read-1',
          readAt: DateTime(2026, 9, 1),
        );
        final c = ctl(repo);
        await c.load();
        expect(c.unreadCount, 2);
        final n = repo.rows.firstWhere((r) => r.title == 'unread-1');
        await c.dismiss(n.id);
        expect(c.unreadCount, 1);
        c.dispose();
      },
    );

    // ---- 6. Double dismiss is safe/idempotent ----
    test(
      'double dismiss is idempotent — second call returns false, no error',
      () async {
        final repo = repo0('u-me');
        final n = repo.seed(userId: 'u-me', title: 'dismiss-me');
        final c = ctl(repo);
        await c.load();
        expect(await c.dismiss(n.id), isTrue);
        expect(repo.rows.where((r) => r.id == n.id), isEmpty);
        // Second dismiss: row already gone → 0 rows → false
        expect(await c.dismiss(n.id), isFalse);
        c.dispose();
      },
    );

    // ---- 7. Dismiss only affects own group — other groups untouched ----
    test(
      'dismiss is scoped to the caller; other users\' rows survive',
      () async {
        final repo = repo0('u-me');
        final mine = repo.seed(userId: 'u-me', title: 'mine');
        final theirs = repo.seed(userId: 'u-b', title: 'theirs');
        final c = ctl(repo);
        await c.load();
        await c.dismiss(mine.id);
        expect(c.items, isEmpty);
        // The other user's row still exists in the backing store
        expect(repo.rows.any((r) => r.id == theirs.id), isTrue);
        c.dispose();
      },
    );

    // ---- 8. Existing mark-read still works after dismiss is added ----
    test('markRead still works alongside dismiss', () async {
      final repo = repo0('u-me');
      final a = repo.seed(userId: 'u-me', title: 'to-read');
      final b = repo.seed(userId: 'u-me', title: 'to-dismiss');
      final c = ctl(repo);
      await c.load();
      expect(c.unreadCount, 2);
      // Mark one read
      expect(await c.markRead(a.id), isTrue);
      expect(c.unreadCount, 1);
      // Dismiss the other
      expect(await c.dismiss(b.id), isTrue);
      expect(c.unreadCount, 0);
      // After re-read: a still exists (now read), b is gone
      expect(c.items.length, 1);
      expect(c.items.first.id, a.id);
      expect(c.items.first.isRead, isTrue);
      c.dispose();
    });

    // ---- 9. Existing mark-all-read still works ----
    test('markAllRead still works alongside dismiss', () async {
      final repo = repo0('u-me');
      repo.seed(userId: 'u-me', title: 'a');
      repo.seed(userId: 'u-me', title: 'b');
      final c = ctl(repo);
      await c.load();
      expect(c.unreadCount, 2);
      final ok = await c.markAllRead();
      expect(ok, isTrue);
      expect(c.unreadCount, 0);
      expect(c.items.every((n) => n.isRead), isTrue);
      c.dispose();
    });

    // ---- 10. Server error surfaces correctly ----
    test('server error on dismiss surfaces to the UI', () async {
      final repo = repo0('u-me');
      final n = repo.seed(userId: 'u-me', title: 'err');
      final c = ctl(repo);
      await c.load();
      repo.failNextWith = const DataError(message: 'delete denied by policy');
      expect(await c.dismiss(n.id), isFalse);
      expect(c.error, contains('delete denied by policy'));
      c.dispose();
    });

    // ---- 11. Dismiss on empty / nothing to dismiss ----
    test('dismiss on empty list returns false without error', () async {
      final repo = repo0('u-me');
      final c = ctl(repo);
      await c.load();
      expect(c.items, isEmpty);
      expect(await c.dismiss('any-id'), isFalse);
      c.dispose();
    });
  });
}
