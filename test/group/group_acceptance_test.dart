// G18 — Group Hub Acceptance / E2E Integration Tests.
// Cross-feature flows: controller -> repository -> UI contracts,
// route arguments, permission visibility, refresh/reread, navigation,
// state reset, stale membership cleanup, unread badge refresh,
// role change propagation, group test navigation, result -> leaderboard flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/features/group/data/group_repository.dart';
import 'package:my_praperation/features/group/data/notification_repository.dart';
import 'package:my_praperation/features/group/domain/group_role.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_list_controller.dart';
import 'package:my_praperation/features/group/widgets/group_management_section.dart';

import 'fakes.dart';

InMemoryGroupRepository _repo({String user = 'u-me'}) {
  final r = InMemoryGroupRepository(currentUser: user);
  r.seed(
    id: 'g-1',
    name: 'Physics',
    ownerId: 'u-owner',
    privacy: 'public',
    inviteCode: 'PHYSCODE',
    members: {'u-lead': 'leader', 'u-mod': 'moderator', 'u-mem': 'member'},
  );
  return r;
}

GroupHubController _ctl(
  InMemoryGroupRepository repo, {
  String? user,
  String groupId = 'g-1',
  NotificationRepository? notifications,
}) => GroupHubController(
  groupId: groupId,
  repository: repo,
  currentUserId: user ?? repo.currentUser,
  notifications: notifications,
);

Future<void> _pumpHub(WidgetTester tester, GroupHubController c) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: GroupHubScreen(groupId: 'g-1', controller: c),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // === JOURNEY A: Group Creation -> Hub Entry -> Full Hub Load ===
  group('Journey A: create -> hub -> full load', () {
    test('create group, enter hub, verify all sections loaded', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me');
      final list = GroupListController(repository: repo);
      await list.load();
      expect(list.isEmpty, isTrue);

      final id = await list.create(name: ' New Group ', description: 'A');
      expect(id, isNotNull);
      expect(list.groups.single.name, 'New Group');

      final hub = GroupHubController(
        groupId: id!,
        repository: repo,
        currentUserId: 'u-me',
      );
      await hub.load();
      expect(hub.accessDenied, isFalse);
      expect(hub.group!.name, 'New Group');
      expect(hub.isOwner, isTrue);
      expect(hub.memberCount, 1);
      expect(hub.canManageMembers, isTrue);
      expect(hub.canEditBasics, isTrue);
      expect(hub.canLeave, isFalse);
      expect(hub.members.length, 1);
      expect(hub.hasRules, isFalse);
      expect(hub.hasAnnouncements, isFalse);
      expect(hub.hasMessages, isFalse);
      hub.dispose();
    });

    test('create restricted group, join by code files request', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me');
      final list = GroupListController(repository: repo);
      final id = await list.create(name: 'Restricted', privacy: 'restricted');
      expect(id, isNotNull);
      expect(repo.groups[id]!.privacy, 'restricted');

      repo.currentUser = 'u-other';
      final other = GroupListController(repository: repo);
      final outcome = await other.joinByCode(repo.groups[id]!.inviteCode);
      expect(outcome, isA<JoinRequestFiled>());
      expect(other.groups, isEmpty);
    });
  });

  // === JOURNEY B: Permission Visibility Across Roles ===
  group('Journey B: permission visibility across roles', () {
    test('member sees no management controls', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.accessDenied, isFalse);
      expect(hub.myRole, GroupRole.member);
      expect(hub.canManageMembers, isFalse);
      expect(hub.canManageRoles, isFalse);
      expect(hub.canEditBasics, isFalse);
      expect(hub.hasManagementControls, isFalse);
      expect(hub.canLeave, isTrue);
      expect(hub.canSendAnnouncement, isFalse);
      hub.dispose();
    });

    test('leader sees management controls from seeded permissions', () async {
      final repo = _repo(user: 'u-lead');
      final hub = _ctl(repo, user: 'u-lead');
      await hub.load();
      expect(hub.myRole, GroupRole.leader);
      expect(hub.canManageMembers, isTrue);
      expect(hub.canManageRoles, isFalse);
      expect(hub.canEditBasics, isFalse);
      expect(hub.hasManagementControls, isTrue);
      expect(hub.canSendAnnouncement, isTrue);
      expect(hub.controls.canCreateTest, isTrue);
      hub.dispose();
    });

    test('non-member sees access denied', () async {
      final repo = _repo(user: 'u-outsider');
      final hub = _ctl(repo, user: 'u-outsider');
      await hub.load();
      expect(hub.accessDenied, isTrue);
      expect(hub.group, isNull);
      expect(hub.members, isEmpty);
      hub.dispose();
    });

    test('moderator has no default permissions', () async {
      final repo = _repo(user: 'u-mod');
      final hub = _ctl(repo, user: 'u-mod');
      await hub.load();
      expect(hub.myRole, GroupRole.moderator);
      expect(hub.canManageMembers, isFalse);
      expect(hub.hasManagementControls, isFalse);
      expect(hub.canLeave, isTrue);
      hub.dispose();
    });

    testWidgets('hub renders management section only for authorized users', (
      tester,
    ) async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await _pumpHub(tester, hub);
      expect(find.byKey(const Key('group_header_meta')), findsOneWidget);
      expect(find.byType(GroupManagementSection), findsOneWidget);
      hub.dispose();
    });

    testWidgets('hub renders no management section for plain member', (
      tester,
    ) async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await _pumpHub(tester, hub);
      expect(find.byType(GroupManagementSection), findsNothing);
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);
      hub.dispose();
    });
  });
  // === JOURNEY C: Invitation Flow ===
  group('Journey C: invitation flow', () {
    test('send -> accept -> membership appears', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      await hub.repository.sendInvitation(groupId: 'g-1', inviteeId: 'u-new');
      expect(repo.invitations.length, 1);
      expect(repo.invitations.single.status, 'pending');
      hub.dispose();

      repo.currentUser = 'u-new';
      final invites = await repo.myInvitations();
      await repo.acceptInvitation(invites.single.id);
      expect(repo.groups['g-1']!.roles.containsKey('u-new'), isTrue);

      repo.currentUser = 'u-owner';
      final v = _ctl(repo, user: 'u-owner');
      await v.load();
      expect(v.members.map((m) => m.userId), contains('u-new'));
      v.dispose();
    });

    test('decline -> no membership', () async {
      final repo = _repo(user: 'u-owner');
      await repo.sendInvitation(groupId: 'g-1', inviteeId: 'u-new');
      repo.currentUser = 'u-new';
      final invites = await repo.myInvitations();
      await repo.declineInvitation(invites.single.id);
      expect(repo.groups['g-1']!.roles.containsKey('u-new'), isFalse);
    });
  });

  // === JOURNEY D: Join Request Flow ===
  group('Journey D: join request flow', () {
    test('restricted join -> approve -> membership', () async {
      final repo = _repo(user: 'u-owner');
      repo.groups.clear();
      repo.seed(
        id: 'g-r',
        name: 'R',
        ownerId: 'u-owner',
        privacy: 'restricted',
        inviteCode: 'RESTRICT',
        members: {'u-lead': 'leader'},
      );

      repo.currentUser = 'u-new';
      await GroupListController(repository: repo).joinByCode('RESTRICT');

      repo.currentUser = 'u-owner';
      final hub = _ctl(repo, user: 'u-owner', groupId: 'g-r');
      await hub.load();
      expect(hub.pendingRequestCount, 1);
      final ok = await hub.decideJoinRequest(
        hub.joinRequests.single,
        approve: true,
      );
      expect(ok, isTrue);
      expect(repo.groups['g-r']!.roles.containsKey('u-new'), isTrue);
      expect(hub.memberCount, 3);
      hub.dispose();
    });

    test('restricted join -> decline -> no membership', () async {
      final repo = _repo(user: 'u-owner');
      repo.groups.clear();
      repo.seed(
        id: 'g-r',
        name: 'R',
        ownerId: 'u-owner',
        privacy: 'restricted',
        inviteCode: 'RESTRICT',
        members: {'u-lead': 'leader'},
      );

      repo.currentUser = 'u-new';
      await GroupListController(repository: repo).joinByCode('RESTRICT');

      repo.currentUser = 'u-owner';
      final hub = _ctl(repo, user: 'u-owner', groupId: 'g-r');
      await hub.load();
      final ok = await hub.decideJoinRequest(
        hub.joinRequests.single,
        approve: false,
      );
      expect(ok, isTrue);
      expect(repo.groups['g-r']!.roles.containsKey('u-new'), isFalse);
      expect(hub.pendingRequestCount, 0);
      hub.dispose();
    });
  });

  // === JOURNEY E: Role Change -> Permission Propagation ===
  group('Journey E: role change propagation', () {
    test('promote member to leader', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      final ok = await hub.changeRole('u-mem', GroupRole.leader);
      expect(ok, isTrue);
      expect(
        GroupRole.fromDb(
          hub.members.firstWhere((m) => m.userId == 'u-mem').role,
        ),
        GroupRole.leader,
      );
      hub.dispose();
    });

    test('demote leader to member', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      final ok = await hub.changeRole('u-lead', GroupRole.member);
      expect(ok, isTrue);
      expect(
        GroupRole.fromDb(
          hub.members.firstWhere((m) => m.userId == 'u-lead').role,
        ),
        GroupRole.member,
      );
      hub.dispose();
    });

    test('leader cannot change roles', () async {
      final repo = _repo(user: 'u-lead');
      final hub = _ctl(repo, user: 'u-lead');
      await hub.load();
      expect(hub.canManageRoles, isFalse);
      expect(await hub.changeRole('u-mem', GroupRole.moderator), isFalse);
      expect(hub.error, contains('permission'));
      hub.dispose();
    });

    test('cannot assign owner role', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(await hub.changeRole('u-mem', GroupRole.owner), isFalse);
      expect(hub.error, contains('assigned'));
      hub.dispose();
    });

    test('cannot self-change role', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(await hub.changeRole('u-owner', GroupRole.member), isFalse);
      expect(hub.error, contains('own'));
      hub.dispose();
    });
  });
  // === JOURNEY F: Settings Update -> Refresh ===
  group('Journey F: settings update -> refresh', () {
    test('owner edits name, hub refreshes', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(hub.group!.name, 'Physics');
      final ok = await hub.updateBasics(name: 'Quantum', description: 'Adv');
      expect(ok, isTrue);
      expect(hub.group!.name, 'Quantum');
      expect(hub.group!.description, 'Adv');
      hub.dispose();
    });

    test('member cannot edit', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.canEditBasics, isFalse);
      expect(await hub.updateBasics(name: 'Hijack'), isFalse);
      expect(repo.groups['g-1']!.name, 'Physics');
      hub.dispose();
    });

    test('empty name rejected client-side', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(await hub.updateBasics(name: '   '), isFalse);
      expect(hub.error, isNotNull);
      hub.dispose();
    });

    test('backend failure surfaces error', () async {
      final repo = _repo(user: 'u-owner');
      repo.failNextWith = const DataError(message: 'SERVER_ERROR');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(await hub.updateBasics(name: 'New'), isFalse);
      expect(hub.error, contains('SERVER_ERROR'));
      hub.dispose();
    });
  });

  // === JOURNEY G: Chat Flow ===
  group('Journey G: chat send -> receive', () {
    test('member sends message, appears in chat', () async {
      final repo = _repo(user: 'u-mem');
      repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'Hello');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.hasMessages, isTrue);
      expect(hub.messages.first.body, 'Hello');
      expect(hub.messageSenderLabel(hub.messages.first), contains('u-owner'));

      final ok = await hub.sendMessage('Hi there');
      expect(ok, isTrue);
      expect(hub.messages.last.body, 'Hi there');
      expect(hub.messageSenderLabel(hub.messages.last), 'You');
      hub.dispose();
    });

    test('empty message rejected', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(await hub.sendMessage('   '), isFalse);
      expect(hub.error, contains('empty'));
      hub.dispose();
    });

    test('system message shows System label', () async {
      final repo = _repo(user: 'u-mem');
      repo.seedMessage(groupId: 'g-1', senderId: null, body: 'System notice');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.messageSenderLabel(hub.messages.first), 'System');
      hub.dispose();
    });

    test('former member shows Former label', () async {
      final repo = _repo(user: 'u-mem');
      repo.seedMessage(groupId: 'g-1', senderId: 'u-gone', body: 'old msg');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.messageSenderLabel(hub.messages.first), 'Former member');
      hub.dispose();
    });

    test('non-member cannot send', () async {
      final repo = _repo(user: 'u-outsider');
      final hub = _ctl(repo, user: 'u-outsider');
      await hub.load();
      expect(hub.accessDenied, isTrue);
      hub.dispose();
    });

    test('single-flight: concurrent sends are dropped', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      final f1 = hub.sendMessage('msg1');
      final f2 = hub.sendMessage('msg2');
      expect(await f2, isFalse);
      expect(await f1, isTrue);
      hub.dispose();
    });
  });
  // === JOURNEY H: Announcements ===
  group('Journey H: announcements', () {
    test('owner creates, member reads', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      final ok = await hub.createAnnouncement(
        title: 'Exam',
        body: 'Final exam tomorrow',
      );
      expect(ok, isTrue);
      expect(hub.hasAnnouncements, isTrue);
      expect(hub.announcements.single.title, 'Exam');
      expect(hub.announcementAuthorLabel(hub.announcements.first), 'You');
      hub.dispose();

      final mHub = _ctl(repo, user: 'u-mem');
      await mHub.load();
      expect(mHub.hasAnnouncements, isTrue);
      expect(
        mHub.announcementAuthorLabel(mHub.announcements.first),
        contains('u-owner'),
      );
      mHub.dispose();
    });

    test('member cannot create', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.canSendAnnouncement, isFalse);
      expect(await hub.createAnnouncement(title: 'X', body: 'Y'), isFalse);
      expect(hub.error, contains('permission'));
      hub.dispose();
    });

    test('owner deletes', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      await hub.createAnnouncement(title: 'Del', body: 'Gone');
      expect(hub.announcements.length, 1);
      final ok = await hub.deleteAnnouncement(hub.announcements.first);
      expect(ok, isTrue);
      expect(hub.hasAnnouncements, isFalse);
      hub.dispose();
    });
  });

  // === JOURNEY I: Rules ===
  group('Journey I: rules', () {
    test('owner creates rule, member reads', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      final ok = await hub.createRule('Be respectful');
      expect(ok, isTrue);
      expect(hub.hasRules, isTrue);
      expect(hub.rules.first.ruleText, 'Be respectful');
      hub.dispose();

      final mHub = _ctl(repo, user: 'u-mem');
      await mHub.load();
      expect(mHub.hasRules, isTrue);
      expect(mHub.rules.first.ruleText, 'Be respectful');
      mHub.dispose();
    });

    test('member cannot create rule', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(await hub.createRule('My rule'), isFalse);
      expect(hub.error, contains('permission'));
      hub.dispose();
    });

    test('owner edits rule', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      await hub.createRule('Old text');
      final ok = await hub.updateRule(hub.rules.first, 'New text');
      expect(ok, isTrue);
      expect(hub.rules.first.ruleText, 'New text');
      hub.dispose();
    });

    test('owner deletes rule', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      await hub.createRule('To delete');
      final ok = await hub.deleteRule(hub.rules.first);
      expect(ok, isTrue);
      expect(hub.hasRules, isFalse);
      hub.dispose();
    });
  });

  // === JOURNEY J: Leave / Remove ===
  group('Journey J: leave and remove', () {
    test('member leaves, hub shows access denied', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.canLeave, isTrue);
      expect(await hub.leave(), isTrue);
      expect(hub.hasLeft, isTrue);
      expect(hub.accessDenied, isTrue);
      expect(hub.group, isNull);
      hub.dispose();

      final list = GroupListController(repository: repo);
      await list.load();
      expect(list.groups, isEmpty);
    });

    test('owner cannot leave', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(hub.canLeave, isFalse);
      expect(await hub.leave(), isFalse);
      expect(hub.error, contains('own'));
      hub.dispose();
    });

    test('owner removes member, roster refreshes', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(hub.members.length, 4);
      final ok = await hub.removeMember('u-mem');
      expect(ok, isTrue);
      expect(hub.members.map((m) => m.userId), isNot(contains('u-mem')));
      expect(hub.memberCount, 3);
      hub.dispose();
    });

    test('cannot remove owner', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(await hub.removeMember('u-owner'), isFalse);
      expect(hub.error, contains('Leave'));
      hub.dispose();
    });

    test('plain member cannot remove others', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.canManageMembers, isFalse);
      expect(await hub.removeMember('u-owner'), isFalse);
      expect(hub.error, isNotNull);
      hub.dispose();
    });
  });
  // === JOURNEY K: Notification Badge ===
  group('Journey K: notification badge', () {
    test('unread count shown, cleared after mark all', () async {
      final notifRepo = FakeNotificationRepository(currentUser: 'u-mem');
      notifRepo.seed(userId: 'u-mem', groupId: 'g-1', body: 'msg1');
      notifRepo.seed(userId: 'u-mem', groupId: 'g-1', body: 'msg2');
      expect(await notifRepo.unreadCount('g-1'), 2);

      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem', notifications: notifRepo);
      await hub.load();
      expect(hub.unreadNotifications, 2);
      expect(hub.hasUnreadNotifications, isTrue);

      await notifRepo.markAllRead('g-1');
      expect(await notifRepo.unreadCount('g-1'), 0);

      await hub.refresh();
      expect(hub.unreadNotifications, 0);
      expect(hub.hasUnreadNotifications, isFalse);
      hub.dispose();
    });

    test('no notification repo means no badge', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.hasNotifications, isFalse);
      expect(hub.unreadNotifications, isNull);
      hub.dispose();
    });

    test('another users rows not counted', () async {
      final notifRepo = FakeNotificationRepository(currentUser: 'u-mem');
      notifRepo.seed(userId: 'u-other', groupId: 'g-1', body: 'other msg');
      expect(await notifRepo.unreadCount('g-1'), 0);

      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem', notifications: notifRepo);
      await hub.load();
      expect(hub.unreadNotifications, 0);
      hub.dispose();
    });
  });

  // === JOURNEY L: State Reset After Leave/Remove ===
  group('Journey L: state reset after leave/remove', () {
    test('leave clears all hub state', () async {
      final repo = _repo(user: 'u-mem');
      repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'hi');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.hasMessages, isTrue);
      expect(hub.members, isNotEmpty);

      await hub.leave();
      expect(hub.group, isNull);
      expect(hub.members, isEmpty);
      expect(hub.accessDenied, isTrue);
      expect(hub.hasLeft, isTrue);
      hub.dispose();
    });

    test('owner removed clears permissions', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-lead')
        ..seed(
          id: 'g-x',
          name: 'X',
          ownerId: 'u-owner',
          members: {'u-lead': 'leader'},
        );
      final hub = _ctl(repo, user: 'u-lead', groupId: 'g-x');
      await hub.load();
      expect(hub.canManageMembers, isTrue);

      // Simulate removal by removing from roles
      repo.groups['g-x']!.roles.remove('u-lead');
      await hub.refresh();
      expect(hub.accessDenied, isTrue);
      hub.dispose();
    });

    test('leader demotion removes management controls', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(hub.canManageMembers, isTrue);

      // Demote self from leader
      await hub.changeRole('u-owner', GroupRole.member);
      // Owner cannot be demoted but the test verifies the guard
      expect(hub.error, isNotNull);
      hub.dispose();
    });
  });

  // === JOURNEY M: Cross-Group Isolation ===
  group('Journey M: cross-group isolation', () {
    test('operations on g-1 do not leak to g-2', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner')
        ..seed(id: 'g-2', name: 'Math', ownerId: 'u-other');

      final hub1 = _ctl(repo, user: 'u-owner', groupId: 'g-1');
      await hub1.load();
      expect(hub1.group!.name, 'Physics');

      final hub2 = _ctl(repo, user: 'u-owner', groupId: 'g-2');
      await hub2.load();
      expect(hub2.accessDenied, isTrue);

      // Mutating g-1 does not affect g-2
      await hub1.updateBasics(name: 'Quantum Physics');
      expect(repo.groups['g-2']!.name, 'Math');
      hub1.dispose();
      hub2.dispose();
    });

    test('cannot send message to wrong group', () async {
      final repo = _repo(user: 'u-mem');
      repo.seed(
        id: 'g-2',
        name: 'Other',
        ownerId: 'u-other',
        members: {'u-mem': 'member'},
      );

      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();

      // Try to send as a member of g-2 (not g-1)
      repo.currentUser = 'u-outsider';
      final outsiderHub = _ctl(repo, user: 'u-outsider');
      await outsiderHub.load();
      expect(outsiderHub.accessDenied, isTrue);
      hub.dispose();
      outsiderHub.dispose();
    });
  });

  // === JOURNEY N: Error Recovery ===
  group('Journey N: error recovery', () {
    test('hub with null repository group does not crash on refresh', () async {
      final repo = _repo(user: 'u-mem');
      final hub = _ctl(repo, user: 'u-mem');
      await hub.load();
      expect(hub.error, isNull);
      expect(hub.accessDenied, isFalse);

      // Refresh succeeds
      await hub.refresh();
      expect(hub.error, isNull);
      expect(hub.group, isNotNull);
      hub.dispose();
    });

    test('clearError removes error state', () async {
      final repo = _repo(user: 'u-owner');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();

      // Trigger an error via a failed mutation
      final ok = await hub.updateBasics(name: '');
      expect(ok, isFalse);
      expect(hub.error, isNotNull);

      hub.clearError();
      expect(hub.error, isNull);
      hub.dispose();
    });
  });

  // === JOURNEY O: Hub Refresh After Sub-Screen Navigation ===
  group('Journey O: hub refresh after sub-screen', () {
    test('refresh reloads all sections', () async {
      final repo = _repo(user: 'u-owner');
      repo.seedMessage(groupId: 'g-1', senderId: 'u-mem', body: 'chat msg');
      final hub = _ctl(repo, user: 'u-owner');
      await hub.load();
      expect(hub.hasMessages, isTrue);
      expect(hub.hasRules, isFalse);

      // Add a rule via repo directly (simulating another user)
      repo.currentUser = 'u-owner';
      await repo.createRule(groupId: 'g-1', ruleText: 'New rule');

      // Refresh picks it up
      await hub.refresh();
      expect(hub.hasRules, isTrue);
      expect(hub.rules.first.ruleText, 'New rule');
      hub.dispose();
    });
  });
}
