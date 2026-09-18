// G3 — roles & permission engine. The fake reproduces the live rules,
// including the live "role changes" UPDATE policy's self-update branch, so
// these tests prove the client never relies on it and document what the
// server must still enforce (see G3 report, section E).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/features/group/domain/group_permission.dart';
import 'package:my_praperation/features/group/domain/group_role.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

void main() {
  group('Parsing', () {
    test('GroupRole: all four live values, unknown → member', () {
      for (final r in GroupRole.values) {
        expect(GroupRole.fromDb(r.db), r);
        expect(GroupRole.fromDb(r.db.toUpperCase()), r);
      }
      expect(GroupRole.fromDb('superuser'), GroupRole.member);
      expect(GroupRole.fromDb(''), GroupRole.member);
    });

    test('GroupPermission: all 12 live labels round-trip, unknown kept', () {
      expect(GroupPermission.live.length, 12);
      for (final p in GroupPermission.live) {
        expect(GroupPermission.fromDb(p.db), p);
        expect(p.db, isNotEmpty);
      }
      expect(
        GroupPermission.fromDb('DELETE_EVERYTHING'),
        GroupPermission.unknown,
      );
      expect(GroupPermission.fromDb(null), GroupPermission.unknown);
      expect(GroupPermission.live, isNot(contains(GroupPermission.unknown)));
    });

    test('GroupPermissions is a plain set view', () {
      const p = GroupPermissions({
        GroupPermission.manageRoles,
        GroupPermission.createTest,
      });
      expect(p.canManageRoles, isTrue);
      expect(p.canManageMembers, isFalse);
      expect(p.canEditSettings, isFalse);
      expect(GroupPermissions.none.granted, isEmpty);
    });
  });

  group('Effective permissions (server probe)', () {
    test('owner holds everything without role_permissions rows', () async {
      final repo = InMemoryGroupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await c.load();
      expect(c.canManageMembers, isTrue);
      expect(c.canManageRoles, isTrue);
      expect(c.canEditBasics, isTrue);
      c.dispose();
    });

    test(
      'leader: live seeding = 10 permissions, not MANAGE_ROLES/GROUP_SETTINGS',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'leader'});
        final all = await repo.permissionsFor('g-1');
        expect(all.granted.length, 10);
        expect(all.canManageMembers, isTrue);
        expect(all.canManageRoles, isFalse);
        expect(all.canEditSettings, isFalse);

        final c = _hub(repo);
        await c.load();
        expect(c.canManageRoles, isFalse);
        c.dispose();

        // An explicit role_permissions row changes the answer, not the role.
        repo.roleGrants.add('g-1:leader:MANAGE_ROLES');
        final c2 = _hub(repo);
        await c2.load();
        expect(c2.canManageRoles, isTrue);
        c2.dispose();
      },
    );

    test('moderator and member hold nothing by default', () async {
      final repo = InMemoryGroupRepository()
        ..seed(
          id: 'g-1',
          ownerId: 'u-owner',
          members: {'u-mod': 'moderator', 'u-me': 'member'},
        );
      expect((await repo.permissionsFor('g-1')).granted, isEmpty);
      repo.currentUser = 'u-mod';
      expect((await repo.permissionsFor('g-1')).granted, isEmpty);
    });
  });

  group('Role change', () {
    test('authorized: owner promotes a member; roster refreshes', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(await c.changeRole('u-2', GroupRole.leader), isTrue);
      expect(c.members.firstWhere((m) => m.userId == 'u-2').role, 'leader');
      expect(repo.calls, contains('setRole:g-1:u-2:leader'));
      expect(c.error, isNull);
      c.dispose();
    });

    test(
      'unauthorized: leader (no MANAGE_ROLES) is refused before the call',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(
            id: 'g-1',
            ownerId: 'u-owner',
            members: {'u-me': 'leader', 'u-2': 'member'},
          );
        final c = _hub(repo);
        await c.load();
        expect(c.canManageRoles, isFalse);
        expect(await c.changeRole('u-2', GroupRole.moderator), isFalse);
        expect(c.error, contains('permission'));
        expect(repo.calls.where((x) => x.startsWith('setRole')), isEmpty);
        expect(repo.groups['g-1']!.roles['u-2'], 'member');
        c.dispose();
      },
    );

    test(
      'unauthorized: server refuses even if the client is bypassed',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(
            id: 'g-1',
            ownerId: 'u-owner',
            members: {'u-me': 'leader', 'u-2': 'member'},
          );
        await expectLater(
          repo.setMemberRole(
            groupId: 'g-1',
            userId: 'u-2',
            role: GroupRole.leader,
          ),
          throwsA(isA<DataError>()),
        );
        expect(repo.groups['g-1']!.roles['u-2'], 'member');
      },
    );

    test(
      'self-role escalation: client refuses; the LIVE policy would not',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
        repo.roleGrants.add(
          'g-1:member:MANAGE_ROLES',
        ); // even with the permission
        final c = _hub(repo);
        await c.load();
        expect(await c.changeRole('u-me', GroupRole.leader), isFalse);
        expect(c.error, contains('own role'));
        expect(repo.calls.where((x) => x.startsWith('setRole')), isEmpty);

        // Documented live defect: the "role changes" policy's
        // `user_id = auth.uid()` branch lets a direct table update through.
        // This is what the G3 backend fix must close; the client never uses it.
        repo.roleGrants.clear();
        await repo.setMemberRole(
          groupId: 'g-1',
          userId: 'u-me',
          role: GroupRole.leader,
        );
        expect(
          repo.groups['g-1']!.roles['u-me'],
          'leader',
          reason: 'live policy defect reproduced, not endorsed',
        );
        c.dispose();
      },
    );

    test(
      'owner protection: cannot demote the owner, cannot assign owner',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(
            id: 'g-1',
            ownerId: 'u-owner',
            members: {'u-me': 'leader', 'u-2': 'member'},
          );
        repo.roleGrants.add('g-1:leader:MANAGE_ROLES');
        final c = _hub(repo);
        await c.load();
        expect(c.canManageRoles, isTrue);

        expect(await c.changeRole('u-owner', GroupRole.member), isFalse);
        expect(c.error, contains('owner'));
        expect(await c.changeRole('u-2', GroupRole.owner), isFalse);
        expect(c.error, contains('cannot be assigned'));
        expect(repo.calls.where((x) => x.startsWith('setRole')), isEmpty);
        expect(
          GroupHubController.assignableRoles,
          isNot(contains(GroupRole.owner)),
        );

        // Server side: trg_owner_guard refuses demotion even when bypassed.
        await expectLater(
          repo.setMemberRole(
            groupId: 'g-1',
            userId: 'u-owner',
            role: GroupRole.member,
          ),
          throwsA(isA<DataError>()),
        );
        expect(repo.groups['g-1']!.roles['u-owner'], 'owner');
        c.dispose();
      },
    );

    test('target not a member of this group → refused, nothing sent', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me')
        ..seed(
          id: 'g-2',
          ownerId: 'u-other',
          members: {'u-elsewhere': 'member'},
        );
      final c = _hub(repo);
      await c.load();
      expect(await c.changeRole('u-elsewhere', GroupRole.leader), isFalse);
      expect(c.error, contains('not a member'));
      expect(repo.calls.where((x) => x.startsWith('setRole')), isEmpty);
      expect(
        repo.groups['g-2']!.roles['u-elsewhere'],
        'member',
        reason: 'group isolation',
      );
      c.dispose();
    });

    test('invalid role from the server maps to a clear message', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      repo.failNextWith = const DataError(
        message: 'invalid input value for enum group_role: "admin"',
      );
      expect(await c.changeRole('u-2', GroupRole.leader), isFalse);
      expect(c.error, contains('enum'));
      c.dispose();
    });

    test('same role is a no-op; second call while busy is dropped', () async {
      final repo = _SlowRoleRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(await c.changeRole('u-2', GroupRole.member), isTrue);
      expect(repo.roleCalls, 0);

      final first = c.changeRole('u-2', GroupRole.leader);
      final second = c.changeRole('u-2', GroupRole.moderator);
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(repo.roleCalls, 1);
      expect(repo.groups['g-1']!.roles['u-2'], 'leader');
      c.dispose();
    });

    test('backend failure surfaces the message; role unchanged', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      repo.failNextWith = const DataError(message: 'Network error.');
      expect(await c.changeRole('u-2', GroupRole.leader), isFalse);
      expect(c.error, 'Network error.');
      expect(c.members.firstWhere((m) => m.userId == 'u-2').role, 'member');
      expect(c.isBusy, isFalse);
      c.dispose();
    });
  });

  group('Permission-driven UI', () {
    Future<GroupHubController> pump(
      WidgetTester tester,
      InMemoryGroupRepository repo,
    ) async {
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupHubScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('owner sees role menus for others, never for self/owner', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('role_menu_u-2')), findsOneWidget);
      expect(find.byKey(const Key('role_menu_u-me')), findsNothing);
      expect(find.byKey(const Key('role_badge_owner')), findsOneWidget);
      expect(find.byKey(const Key('role_badge_member')), findsOneWidget);

      await tester.tap(find.byKey(const Key('role_menu_u-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('role_option_u-2_owner')), findsNothing);
      await tester.tap(find.byKey(const Key('role_option_u-2_leader')));
      await tester.pumpAndSettle();
      expect(find.text('Change role?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_role_change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('role_badge_leader')), findsOneWidget);
      expect(repo.groups['g-1']!.roles['u-2'], 'leader');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets(
      'leader without MANAGE_ROLES sees no role menu (but can remove)',
      (tester) async {
        final repo = InMemoryGroupRepository()
          ..seed(
            id: 'g-1',
            ownerId: 'u-owner',
            members: {'u-me': 'leader', 'u-2': 'member'},
          );
        final c = await pump(tester, repo);
        expect(find.byKey(const Key('role_menu_u-2')), findsNothing);
        expect(find.byKey(const Key('remove_u-2')), findsOneWidget);
        expect(find.byKey(const Key('remove_u-owner')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('member sees badges only', (tester) async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = await pump(tester, repo);
      expect(find.byType(PopupMenuButton<GroupRole>), findsNothing);
      expect(find.byKey(const Key('remove_u-owner')), findsNothing);
      expect(find.byKey(const Key('role_badge_owner')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

class _SlowRoleRepository extends InMemoryGroupRepository {
  int roleCalls = 0;

  @override
  Future<void> setMemberRole({
    required String groupId,
    required String userId,
    required GroupRole role,
  }) async {
    roleCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.setMemberRole(groupId: groupId, userId: userId, role: role);
  }
}
