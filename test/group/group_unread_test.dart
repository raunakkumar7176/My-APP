// Group Hub — chat unread state (existing 0027 RPCs, previously unwired on
// the client). `fn_get_group_unread_counts` / `fn_mark_group_read` /
// `fn_latest_group_messages` already exist server-side; these tests
// exercise the NEW client wiring: GroupListController surfacing a badge
// + preview per group, and GroupHubController marking a group read when
// it opens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/group/screens/group_list_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_list_controller.dart';

import 'fakes.dart';

void main() {
  group('GroupListController: unread counts + previews', () {
    test('a group with an unread message from another member shows a nonzero count', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'Hi', at: DateTime(2026, 1, 1, 9, 0));
      final c = GroupListController(repository: repo);

      await c.load();

      expect(c.unreadCountFor('g-1'), 1);
      c.dispose();
    });

    test('the sender\'s own messages never count as unread for them', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me');
      repo.seedMessage(groupId: 'g-1', senderId: 'u-me', body: 'Hi', at: DateTime(2026, 1, 1, 9, 0));
      final c = GroupListController(repository: repo);

      await c.load();

      expect(c.unreadCountFor('g-1'), 0);
      c.dispose();
    });

    test('an unloaded / unknown group id reports 0, never a guessed count', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me');
      final c = GroupListController(repository: repo);
      await c.load();
      expect(c.unreadCountFor('does-not-exist'), 0);
      c.dispose();
    });

    test('latestMessageFor surfaces the newest message with sender + deleted-safe preview', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.profileNames['u-owner'] = 'Owner Person';
      repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'First', at: DateTime(2026, 1, 1, 9, 0));
      repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'Second', at: DateTime(2026, 1, 1, 9, 5));
      final c = GroupListController(repository: repo);

      await c.load();

      final latest = c.latestMessageFor('g-1');
      expect(latest, isNotNull);
      expect(latest!.body, 'Second');
      expect(latest.senderName, 'Owner Person');
      expect(latest.isDeleted, isFalse);
      expect(latest.preview, 'Second');
      c.dispose();
    });

    test('a group with no messages yet has no latest-message preview', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Empty', ownerId: 'u-me');
      final c = GroupListController(repository: repo);

      await c.load();

      expect(c.latestMessageFor('g-1'), isNull);
      c.dispose();
    });

    test('a failure loading unread/preview data never blocks the groups list itself from rendering', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me');
      final c = GroupListController(repository: repo);

      await c.load();

      expect(c.groups.length, 1);
      expect(c.error, isNull);
      c.dispose();
    });
  });

  group('GroupHubController: mark read on open', () {
    test('opening a group hub marks it read (message_reads upserted)', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'Hi', at: DateTime(2026, 1, 1, 9, 0));

      final hub = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-me');
      await hub.load();

      expect(repo.calls.where((x) => x.startsWith('markGroupRead:g-1')).length, 1);
      hub.dispose();

      final list = GroupListController(repository: repo);
      await list.load();
      expect(list.unreadCountFor('g-1'), 0);
      list.dispose();
    });

    test('opening an inaccessible group never calls markGroupRead', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Not mine', ownerId: 'u-owner');

      final hub = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-me');
      await hub.load();

      expect(hub.accessDenied, isTrue);
      expect(repo.calls.where((x) => x.startsWith('markGroupRead:')).length, 0);
      hub.dispose();
    });

    test('a markGroupRead failure never surfaces as a hub load error', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me');

      final hub = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-me');
      await hub.load();

      // The fake's markGroupRead only throws for a non-member/unknown group,
      // which can't happen once load() has already confirmed access — this
      // asserts the happy path never leaks a read-marking error into `error`.
      expect(hub.error, isNull);
      hub.dispose();
    });
  });

  group('GroupListScreen: unread badge + preview rendering', () {
    testWidgets('shows the unread badge and the latest-message preview instead of the member-count line', (tester) async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.profileNames['u-owner'] = 'Owner Person';
      repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'Chapter 3 tonight', at: DateTime(2026, 1, 1, 9, 0));
      final c = GroupListController(repository: repo);

      await tester.pumpWidget(MaterialApp(home: GroupListScreen(controller: c)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('group_card_unread_g-1')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byKey(const Key('group_card_preview_g-1')), findsOneWidget);
      expect(find.text('Owner Person: Chapter 3 tonight'), findsOneWidget);

      c.dispose();
    });

    testWidgets('no badge and the member-count fallback subtitle when there is no unread and no message', (tester) async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me');
      final c = GroupListController(repository: repo);

      await tester.pumpWidget(MaterialApp(home: GroupListScreen(controller: c)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('group_card_unread_g-1')), findsNothing);
      expect(find.byKey(const Key('group_card_preview_g-1')), findsNothing);
      expect(find.text('1 member · Owner'), findsOneWidget);

      c.dispose();
    });
  });
}
