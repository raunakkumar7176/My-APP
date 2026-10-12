// G3 — roles & permission engine. The fake mirrors the LIVE rules verified
// by the G3 audit (docs/G3_LIVE_AUDIT_AND_CLOSURE.md): the "role changes"
// UPDATE policy is (role <> 'owner') AND MANAGE_ROLES on both USING and CHECK,
// with no self-update branch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/features/group/domain/group_permission.dart';
import 'package:my_praperation/features/group/domain/group_role.dart';
import 'package:my_praperation/features/group/screens/group_info_screen.dart';
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
      expect(await c.changeRole('u-2', GroupRole.admin), isTrue);
      expect(c.members.firstWhere((m) => m.userId == 'u-2').role, 'admin');
      expect(repo.calls, contains('setRole:g-1:u-2:admin'));
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
        expect(await c.changeRole('u-2', GroupRole.admin), isFalse);
        expect(c.error, contains('permission'));
        expect(repo.calls.where((x) => x.startsWith('setRole')), isEmpty);
        expect(repo.groups['g-1']!.roles['u-2'], 'member');
        c.dispose();
      },
    );

    test(
      'unauthorized: live policy matches 0 rows if the client is bypassed',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(
            id: 'g-1',
            ownerId: 'u-owner',
            members: {'u-me': 'leader', 'u-2': 'member'},
          );
        // Live USING clause: a non-MANAGE_ROLES caller matches 0 rows —
        // PostgREST reports success with nothing changed.
        await repo.setMemberRole(
          groupId: 'g-1',
          userId: 'u-2',
          role: GroupRole.admin,
        );
        expect(repo.groups['g-1']!.roles['u-2'], 'member');
      },
    );

    test(
      'self-role escalation: client refuses; live policy also blocks it',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
        repo.roleGrants.add(
          'g-1:member:MANAGE_ROLES',
        ); // even with the permission
        final c = _hub(repo);
        await c.load();
        // Role changes are owner-only (migration 0108) — a plain member is
        // refused before the self-targeting check is even reached.
        expect(await c.changeRole('u-me', GroupRole.admin), isFalse);
        expect(c.error, contains('permission to change roles'));
        expect(repo.calls.where((x) => x.startsWith('setRole')), isEmpty);

        // LIVE: the "role changes" RLS USING clause actually IS
        // `MANAGE_ROLES OR user_id = auth.uid()` — a bare self-update row
        // DOES match (that's the real self-promotion hole this session
        // found and closed). What actually stops it is the
        // `fn_prevent_owner_removal` trigger (migration 0108), which runs
        // on any row RLS lets through and rejects any role change from a
        // non-owner — so the bypass now throws, it doesn't silently no-op.
        repo.roleGrants.clear();
        await expectLater(
          repo.setMemberRole(groupId: 'g-1', userId: 'u-me', role: GroupRole.admin),
          throwsA(isA<DataError>()),
        );
        expect(
          repo.groups['g-1']!.roles['u-me'],
          'member',
          reason: 'trigger blocks self-role escalation',
        );
        c.dispose();
      },
    );

    test(
      'owner protection: cannot demote the owner, cannot assign owner',
      () async {
        // Role changes are owner-only (migration 0108) — these invariants
        // (can't demote yourself out of being owner, can't hand 'owner' to
        // anyone) are checked regardless of who's acting, so the actor here
        // must actually be the owner to reach them.
        final repo = InMemoryGroupRepository()
          ..seed(
            id: 'g-1',
            ownerId: 'u-me',
            members: {'u-2': 'member'},
          );
        final c = _hub(repo);
        await c.load();

        // The owner can't demote themself via this action (the only way
        // to stop being owner is role changes, which have no self-branch).
        expect(await c.changeRole('u-me', GroupRole.member), isFalse);
        expect(c.error, contains('own role'));
        // 'owner' is never an assignable target, even for the owner.
        expect(await c.changeRole('u-2', GroupRole.owner), isFalse);
        expect(c.error, contains('cannot be assigned'));
        expect(repo.calls.where((x) => x.startsWith('setRole')), isEmpty);
        expect(
          GroupHubController.assignableRoles,
          isNot(contains(GroupRole.owner)),
        );

        // Server side (live): the trigger blocks demoting the owner row
        // regardless of actor — bypassing the client raises, it doesn't
        // silently no-op.
        await expectLater(
          repo.setMemberRole(groupId: 'g-1', userId: 'u-me', role: GroupRole.member),
          throwsA(isA<DataError>()),
        );
        expect(repo.groups['g-1']!.roles['u-me'], 'owner');
        await expectLater(
          repo.setMemberRole(
            groupId: 'g-1',
            userId: 'u-2',
            role: GroupRole.owner,
          ),
          throwsA(isA<DataError>()),
        );
        expect(repo.groups['g-1']!.roles['u-2'], 'member');
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
      expect(await c.changeRole('u-elsewhere', GroupRole.admin), isFalse);
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
      expect(await c.changeRole('u-2', GroupRole.admin), isFalse);
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

      final first = c.changeRole('u-2', GroupRole.admin);
      final second = c.changeRole('u-2', GroupRole.admin);
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(repo.roleCalls, 1);
      expect(repo.groups['g-1']!.roles['u-2'], 'admin');
      c.dispose();
    });

    test('backend failure surfaces the message; role unchanged', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = _hub(repo);
      await c.load();
      repo.failNextWith = const DataError(message: 'Network error.');
      expect(await c.changeRole('u-2', GroupRole.admin), isFalse);
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
      // Tall viewport: the hub's lazy ListView must build the roster below
      // the G6 rules and G7 announcements sections too.
      tester.view.physicalSize = const Size(800, 3700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(groupId: 'g-1', controller: c),
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
      await tester.tap(find.byKey(const Key('role_option_u-2_admin')));
      await tester.pumpAndSettle();
      expect(find.text('Change role?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_role_change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('role_badge_admin')), findsOneWidget);
      expect(repo.groups['g-1']!.roles['u-2'], 'admin');

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
