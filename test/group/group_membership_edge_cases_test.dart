// G15 - Group Membership Edge Cases.
// Tests leave (all roles), remove member, owner protection, self-removal
// guard, stale-state clearance, error handling, and confirmation flows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/features/group/data/group_repository.dart';
import 'package:my_praperation/features/group/domain/group_role.dart';
import 'package:my_praperation/features/group/screens/group_info_screen.dart';
import 'package:my_praperation/features/group/screens/group_settings_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_list_controller.dart';

import 'fakes.dart';

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 4100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

GroupHubController _hub(
  InMemoryGroupRepository repo, {
  String user = 'u-me',
}) => GroupHubController(
  groupId: 'g-1',
  repository: repo,
  currentUserId: user,
);

// Leave now lives in Settings' Danger Zone (Phase 2, item A/B.9), not
// Info's old one — this router is used only by the leave-flow dialog
// tests below, so its one route points straight at Settings.
GoRouter _router({
  required GroupHubController controller,
  String initial = '/groups/g-1',
}) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/groups',
      builder: (_, _) => const Scaffold(body: Text('Groups list')),
    ),
    GoRoute(
      path: '/groups/:groupId',
      builder: (_, _) =>
          GroupSettingsScreen(groupId: 'g-1', controller: controller),
    ),
  ],
);

void main() {
  group('A. Member leave', () {
    test('member can leave; state clears; group gone from list', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.canLeave, isTrue);
      expect(await c.leave(), isTrue);
      expect(c.hasLeft, isTrue);
      expect(c.accessDenied, isTrue);
      expect(c.group, isNull);
      expect(c.members, isEmpty);
      final list = GroupListController(repository: repo);
      await list.load();
      expect(list.groups, isEmpty);
      c.dispose();
    });

    testWidgets(
      'leave flow: dialog, confirm, snack, navigate to /groups',
      (tester) async {
        _tallView(tester);
        final repo = InMemoryGroupRepository(currentUser: 'u-me')
          ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner',
              members: {'u-me': 'member'});
        final c = _hub(repo);
        final router = _router(controller: c);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('settings_leave_button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('settings_leave_button')));
        await tester.pumpAndSettle();
        expect(find.text('Leave group?'), findsOneWidget);
        expect(find.textContaining('Physics'), findsWidgets);
        await tester.tap(find.byKey(const Key('confirm_leave')));
        await tester.pumpAndSettle();
        expect(find.text('Groups list'), findsOneWidget);
        expect(repo.groups['g-1']!.roles.containsKey('u-me'), isFalse);
        router.dispose();
        c.dispose();
      },
    );

    testWidgets('leave flow: cancel does nothing', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(home: GroupSettingsScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_leave_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_leave_button')), findsOneWidget);
      expect(repo.groups['g-1']!.roles.containsKey('u-me'), isTrue);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    test('leave failure surfaces error, membership intact', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.failNextWith = const DataError(message: 'Network error.');
      final c = _hub(repo);
      await c.load();
      expect(await c.leave(), isFalse);
      expect(c.error, contains('Network'));
      expect(c.hasLeft, isFalse);
      expect(c.accessDenied, isFalse);
      expect(repo.groups['g-1']!.roles.containsKey('u-me'), isTrue);
      c.dispose();
    });

    test('leave busy guard: second call dropped', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = _hub(repo);
      await c.load();
      final first = c.leave();
      final second = c.leave();
      expect(await second, isFalse);
      expect(await first, isTrue);
      c.dispose();
    });
  });

  group('B. Leader leave', () {
    test('leader can leave; permissions gone after re-read', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner',
            members: {'u-me': 'leader', 'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.myRole, GroupRole.admin);
      expect(c.canManageMembers, isTrue);
      expect(c.canLeave, isTrue);
      expect(await c.leave(), isTrue);
      expect(c.hasLeft, isTrue);
      final list = GroupListController(repository: repo);
      await list.load();
      expect(list.groups, isEmpty);
      c.dispose();
    });

    testWidgets('leader leave: same dialog flow as member', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', name: 'Maths', ownerId: 'u-owner',
            members: {'u-me': 'leader', 'u-2': 'member'});
      final c = _hub(repo);
      final router = _router(controller: c);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_leave_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings_leave_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_leave')));
      await tester.pumpAndSettle();
      expect(find.text('Groups list'), findsOneWidget);
      router.dispose();
      c.dispose();
    });
  });

  group('C. Moderator leave', () {
    test('moderator can leave; membership clears', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner',
            members: {'u-me': 'moderator', 'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.myRole, GroupRole.admin);
      expect(c.canLeave, isTrue);
      expect(await c.leave(), isTrue);
      expect(c.hasLeft, isTrue);
      c.dispose();
    });
  });

  group('D. Owner leave protection', () {
    test('owner cannot leave; canLeave is false; error is set', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.canLeave, isFalse);
      expect(await c.leave(), isFalse);
      expect(c.error, contains('own this group'));
      expect(repo.groups['g-1']!.roles.containsKey('u-me'), isTrue);
      c.dispose();
    });

    testWidgets('owner hub: leave button and blocked-reason text both absent',
        (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(home: GroupInfoScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      // Phase 1: the owner sees no Leave affordance at all, not even the
      // explanatory text — the server-side reason is still available via
      // c.leaveBlockedReason, just never rendered for the owner.
      expect(find.byKey(const Key('leave_group_button')), findsNothing);
      expect(find.byKey(const Key('leave_blocked_note')), findsNothing);
      expect(c.leaveBlockedReason, contains('own this group'));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets(
      'owner Settings: Danger Zone offers Transfer/Delete, never a Leave button',
      (tester) async {
        // Product decision: the owner can delete a group at any time,
        // regardless of other members (0102) -- canDeleteGroup is
        // unconditionally true for an owner now. Danger Zone (moved to
        // Settings, Phase 2) shows Transfer + Delete for the owner; Leave
        // never shows for an owner.
        final repo = InMemoryGroupRepository(currentUser: 'u-me')
          ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
        final c = _hub(repo);
        tester.view.physicalSize = const Size(800, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(home: GroupSettingsScreen(groupId: 'g-1', controller: c)),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('delete_group_button')), findsOneWidget);
        expect(find.byKey(const Key('settings_transfer_ownership_button')), findsOneWidget);
        expect(find.byKey(const Key('settings_leave_button')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  });

  group('E. Remove member', () {
    test('owner can remove a member; roster and count refresh', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me',
            members: {'u-2': 'member', 'u-3': 'leader'});
      final c = _hub(repo);
      await c.load();
      expect(c.canManageMembers, isTrue);
      expect(c.members.length, 3);
      expect(await c.removeMember('u-2'), isTrue);
      expect(c.members.map((m) => m.userId), isNot(contains('u-2')));
      expect(c.memberCount, 2);
      c.dispose();
    });

    test('owner cannot remove themselves via removeMember', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(await c.removeMember('u-me'), isFalse);
      expect(c.error, contains('Leave group'));
      c.dispose();
    });

    test('owner cannot be removed by anyone', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'leader'});
      final c = _hub(repo);
      await c.load();
      expect(await c.removeMember('u-owner'), isFalse);
      expect(c.error, contains('owner'));
      c.dispose();
    });

    test('unauthorized member cannot remove anyone', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner',
            members: {'u-me': 'member', 'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.canManageMembers, isFalse);
      expect(await c.removeMember('u-2'), isFalse);
      expect(c.error, contains('permission'));
      expect(repo.groups['g-1']!.roles.containsKey('u-2'), isTrue);
      c.dispose();
    });

    test('cross-group target: removing a user not in this group succeeds silently', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(await c.removeMember('u-99'), isTrue);
      expect(repo.groups['g-1']!.roles.containsKey('u-2'), isTrue);
      c.dispose();
    });

    test('remove failure surfaces error, target stays', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      repo.failNextWith = const DataError(message: 'Network error.');
      final c = _hub(repo);
      await c.load();
      expect(await c.removeMember('u-2'), isFalse);
      expect(c.error, contains('Network'));
      expect(repo.groups['g-1']!.roles.containsKey('u-2'), isTrue);
      c.dispose();
    });

    testWidgets('remove flow: confirm dialog', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      repo.profileNames['u-2'] = 'Ravi Kumar';
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(home: GroupInfoScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('remove_u-2')), findsOneWidget);
      await tester.tap(find.byKey(const Key('remove_u-2')));
      await tester.pumpAndSettle();
      expect(find.text('Remove member?'), findsOneWidget);
      expect(find.textContaining('Ravi Kumar'), findsAtLeastNWidgets(1));
      await tester.tap(find.byKey(const Key('confirm_remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member_u-2')), findsNothing);
      expect(find.textContaining('was removed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('remove flow: cancel does nothing', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(home: GroupInfoScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove_u-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member_u-2')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('plain member: no remove buttons offered', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner',
            members: {'u-me': 'member', 'u-2': 'member'});
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(home: GroupInfoScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('remove_u-2')), findsNothing);
      expect(find.byKey(const Key('remove_u-me')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('F. Role + removal interaction', () {
    test('after removing a leader, controls refresh from server', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me',
            members: {'u-asha': 'leader', 'u-ravi': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.canManageMembers, isTrue);
      expect(await c.removeMember('u-asha'), isTrue);
      expect(c.members.map((m) => m.userId), isNot(contains('u-asha')));
      c.dispose();
    });

    test('after demoting a leader to member, their permissions gone',
        () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-asha': 'leader'});
      final c = _hub(repo);
      await c.load();
      expect(c.canManageRoles, isTrue);
      expect(await c.changeRole('u-asha', GroupRole.member), isTrue);
      final asha = c.members.firstWhere((m) => m.userId == 'u-asha');
      expect(GroupRole.fromDb(asha.role), GroupRole.member);
      c.dispose();
    });
  });

  group('G. Join request / invitation interaction', () {
    test('pending join request survives member leaving', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.seedJoinRequest(groupId: 'g-1', userId: 'u-outside');
      final c = _hub(repo);
      await c.load();
      expect(await c.leave(), isTrue);
      expect(repo.requestStatus['g-1:u-outside'], 'pending');
      c.dispose();
    });

    test('pending invitation survives member leaving', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.seedInvitation(id: 'inv-1', groupId: 'g-1', inviteeId: 'u-outside');
      final c = _hub(repo);
      await c.load();
      expect(await c.leave(), isTrue);
      expect(repo.invitations.any((i) => i.id == 'inv-1'), isTrue);
      c.dispose();
    });
  });

  group('H. Group deletion', () {
    test('no deleteGroup on GroupRepository interface', () {
      expect(
        () => (GroupRepository as dynamic).deleteGroup,
        throwsA(anything),
      );
    });
  });

  group('I. Owner transfer', () {
    test('assignableRoles excludes owner', () {
      expect(GroupHubController.assignableRoles,
          isNot(contains(GroupRole.owner)));
    });

    test('changeRole cannot set anyone to owner', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'leader'});
      final c = _hub(repo);
      await c.load();
      expect(await c.changeRole('u-2', GroupRole.owner), isFalse);
      expect(c.error, contains('cannot be assigned'));
      c.dispose();
    });

    // Phase 2: fn_transfer_group_ownership — the real transfer feature.
    test('owner can transfer; old owner becomes admin, new owner becomes owner', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(await c.transferOwnership('u-2'), isTrue);
      expect(repo.groups['g-1']!.ownerId, 'u-2');
      expect(repo.groups['g-1']!.roles['u-2'], 'owner');
      expect(repo.groups['g-1']!.roles['u-me'], 'admin');
      // The caller is re-read: they're now admin, not owner.
      expect(c.isOwner, isFalse);
      c.dispose();
    });

    test('non-owner cannot transfer ownership', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-2')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo, user: 'u-2');
      await c.load();
      expect(await c.transferOwnership('u-me'), isFalse);
      expect(c.error, contains('Only the owner'));
      expect(repo.groups['g-1']!.ownerId, 'u-me');
      c.dispose();
    });

    test('cannot transfer to someone who is not already a member', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(await c.transferOwnership('u-not-a-member'), isFalse);
      expect(repo.groups['g-1']!.ownerId, 'u-me');
      c.dispose();
    });

    test('a transfer always leaves exactly one owner in the roster', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member', 'u-3': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(await c.transferOwnership('u-2'), isTrue);
      final owners = repo.groups['g-1']!.roles.values.where((r) => r == 'owner');
      expect(owners.length, 1);
      c.dispose();
    });
  });

  group('J. Removed-member approval gate (migration 0111)', () {
    test('a member removed by someone else cannot rejoin by invite code without approval', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', ownerId: 'u-owner', privacy: 'public', members: {'u-2': 'member'});
      // Owner removes u-2 — an actual removal, not a self-leave.
      final ownerC = _hub(repo, user: 'u-owner');
      await ownerC.load();
      expect(await ownerC.removeMember('u-2'), isTrue);
      ownerC.dispose();

      // u-2 tries to rejoin the same (public!) group with the invite code.
      repo.currentUser = 'u-2';
      final outcome = await repo.joinByCode(repo.groups['g-1']!.inviteCode);
      expect(
        outcome,
        isA<JoinRequestFiled>(),
        reason: 'a removed member is routed through approval even though the group is public',
      );
      expect(repo.groups['g-1']!.roles.containsKey('u-2'), isFalse);
    });

    test('approving that join request clears the removed-member mark', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', ownerId: 'u-owner', privacy: 'public', members: {'u-2': 'member'});
      final ownerC = _hub(repo, user: 'u-owner');
      await ownerC.load();
      await ownerC.removeMember('u-2');

      repo.currentUser = 'u-2';
      await repo.joinByCode(repo.groups['g-1']!.inviteCode);
      repo.currentUser = 'u-owner';
      final requestId = repo.seedJoinRequest(groupId: 'g-1', userId: 'u-2');
      await repo.decideJoinRequest(requestId, approve: true);

      expect(repo.groups['g-1']!.roles.containsKey('u-2'), isTrue);
      expect(repo.groups['g-1']!.removedUserIds.contains('u-2'), isFalse);
      ownerC.dispose();
    });

    test('a member who voluntarily leaves is NOT treated as removed', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-2')
        ..seed(id: 'g-1', ownerId: 'u-owner', privacy: 'public', members: {'u-2': 'member'});
      final c = _hub(repo, user: 'u-2');
      await c.load();
      await c.leave();
      c.dispose();

      final outcome = await repo.joinByCode(repo.groups['g-1']!.inviteCode);
      expect(
        outcome,
        isA<JoinedGroup>(),
        reason: 'leaving voluntarily is not a punishment — straight rejoin via a public group',
      );
    });
  });

  group('K. Invite expiry / max-uses (migration 0111)', () {
    test('an expired invite code is refused', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', ownerId: 'u-owner', privacy: 'public');
      repo.groups['g-1']!.inviteExpiresAt = DateTime.now().subtract(const Duration(days: 1));
      repo.currentUser = 'u-2';
      await expectLater(
        repo.joinByCode(repo.groups['g-1']!.inviteCode),
        throwsA(isA<DataError>()),
      );
    });

    test('an invite code refuses joins once its max-uses budget is spent', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', ownerId: 'u-owner', privacy: 'public');
      repo.groups['g-1']!.inviteMaxUses = 1;
      repo.currentUser = 'u-2';
      final first = await repo.joinByCode(repo.groups['g-1']!.inviteCode);
      expect(first, isA<JoinedGroup>());

      repo.currentUser = 'u-3';
      await expectLater(
        repo.joinByCode(repo.groups['g-1']!.inviteCode),
        throwsA(isA<DataError>()),
      );
    });

    test('rotating the invite code resets the use counter', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', ownerId: 'u-owner', privacy: 'public');
      repo.currentUser = 'u-2';
      await repo.joinByCode(repo.groups['g-1']!.inviteCode);
      expect(repo.groups['g-1']!.inviteUseCount, 1);

      repo.currentUser = 'u-owner';
      await repo.rotateInviteCode('g-1');
      expect(repo.groups['g-1']!.inviteUseCount, 0);
    });

    test('setInviteLimits requires GROUP_SETTINGS or owner', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-2')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-2': 'member'});
      await expectLater(
        repo.setInviteLimits(groupId: 'g-1', expiresAt: null, maxUses: 5),
        throwsA(anything),
      );
    });
  });

  group('Stale state clearance', () {
    test('after leave, all local state is cleared', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner',
            members: {'u-me': 'leader', 'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.members, isNotEmpty);
      expect(c.group, isNotNull);
      await c.leave();
      expect(c.group, isNull);
      expect(c.members, isEmpty);
      expect(c.hasLeft, isTrue);
      expect(c.accessDenied, isTrue);
      expect(c.isBusy, isFalse);
      c.dispose();
    });

    test('after removeMember, roster is refreshed from server', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me',
            members: {'u-2': 'member', 'u-3': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.members.length, 3);
      await c.removeMember('u-2');
      expect(c.members.map((m) => m.userId), contains('u-3'));
      expect(c.members.map((m) => m.userId), isNot(contains('u-2')));
      expect(c.memberCount, 2);
      c.dispose();
    });
  });
}
