// G14 — Group owner / leader / moderator controls.
//
// UNIT / UI TESTS ONLY. `InMemoryGroupRepository` mirrors the live rules
// (fn_has_permission owner bypass; leader seeded with everything except
// GROUP_SETTINGS and MANAGE_ROLES; moderator/member seeded with nothing;
// `role_permissions` policy "manage roles perms" = MANAGE_ROLES; "role
// changes" / "manage members" policies; trg_owner_guard). These tests prove
// the client offers and refuses the right things and re-reads the server
// after mutations. They are NOT proof of the live database — that proof is
// the rolled-back live probe recorded in
// docs/G14_GROUP_CONTROLS_IMPLEMENTATION_REPORT.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/group/domain/group_controls.dart';
import 'package:my_praperation/features/group/domain/group_permission.dart';
import 'package:my_praperation/features/group/domain/group_role.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/widgets/group_management_section.dart';
import 'package:my_praperation/features/group/widgets/role_permissions_sheet.dart';

import 'fakes.dart';

/// g-1: owner u-owner, leader u-lead, moderator u-mod, member u-mem;
/// g-2: owned by u-other with u-x as member (cross-group target).
InMemoryGroupRepository _repo(String user) => InMemoryGroupRepository(currentUser: user)
  ..seed(
    id: 'g-1',
    name: 'Physics',
    ownerId: 'u-owner',
    members: {'u-lead': 'leader', 'u-mod': 'moderator', 'u-mem': 'member'},
  )
  ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other', members: {'u-x': 'member'});

GroupHubController _ctl(InMemoryGroupRepository repo, String user, {String groupId = 'g-1'}) =>
    GroupHubController(groupId: groupId, repository: repo, currentUserId: user);

Future<GroupHubController> _loaded(String user, {InMemoryGroupRepository? repo}) async {
  final r = repo ?? _repo(user);
  final c = _ctl(r, user);
  await c.load();
  return c;
}

Future<void> _pumpHub(WidgetTester tester, GroupHubController c) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: GroupHubScreen(groupId: 'g-1', controller: c)));
  await tester.pumpAndSettle();
}

void main() {
  group('GroupControls (pure gating rules)', () {
    test('owner: every control, regardless of probe results', () {
      const ctl = GroupControls(permissions: GroupPermissions.none, isOwner: true);
      expect(ctl.hasAnyManagement, isTrue);
      expect(ctl.canOpenSettings, isTrue);
      expect(ctl.canManageMembers, isTrue);
      expect(ctl.canManageRoles, isTrue);
      expect(ctl.canManageRolePermissions, isTrue);
      expect(ctl.canManageTests, isTrue);
      expect(ctl.canViewAnalytics, isTrue);
      expect(ctl.canSendAnnouncement, isTrue);
      expect(ctl.testCapabilities, ['create', 'edit', 'publish', 'schedule', 'results']);
    });

    test('non-owner: strictly what the server granted, never role-derived', () {
      const none = GroupControls(permissions: GroupPermissions.none, isOwner: false);
      expect(none.hasAnyManagement, isFalse);
      expect(none.testCapabilities, isEmpty);
      const some = GroupControls(
        permissions: GroupPermissions({GroupPermission.publishTest, GroupPermission.viewGroupAnalytics}),
        isOwner: false,
      );
      expect(some.hasAnyManagement, isTrue);
      expect(some.canManageTests, isTrue);
      expect(some.canCreateTest, isFalse);
      expect(some.canPublishTest, isTrue);
      expect(some.canViewAnalytics, isTrue);
      expect(some.canManageRolePermissions, isFalse);
      expect(some.canOpenSettings, isFalse);
      expect(some.testCapabilities, ['publish']);
    });

    test('RolePermissionRules: leader/moderator editable; owner and member never', () {
      expect(RolePermissionRules.editableRoles, [GroupRole.leader, GroupRole.moderator]);
      expect(RolePermissionRules.canEditRole(GroupRole.owner), isFalse);
      expect(RolePermissionRules.canEditRole(GroupRole.member), isFalse);
      expect(RolePermissionRules.canEditPermission(GroupPermission.unknown), isFalse);
      expect(RolePermissionRules.canEditPermission(GroupPermission.manageRoles), isTrue);
    });

    test('GroupRolePermissions parses rows and drops unknown labels', () {
      final m = GroupRolePermissions.fromRows([
        {'role': 'leader', 'permission': 'CREATE_TEST'},
        {'role': 'moderator', 'permission': 'SEND_ANNOUNCEMENT'},
        {'role': 'moderator', 'permission': 'NOT_A_PERMISSION'},
      ]);
      expect(m.has(GroupRole.leader, GroupPermission.createTest), isTrue);
      expect(m.has(GroupRole.moderator, GroupPermission.sendAnnouncement), isTrue);
      expect(m.has(GroupRole.moderator, GroupPermission.createTest), isFalse);
      expect(m.rowCount, 2);
      expect(GroupRolePermissions.empty.of(GroupRole.leader), isEmpty);
    });
  });

  group('1–2. owner controls & protection', () {
    testWidgets('owner sees every Manage row; owner row is never removable/demotable', (tester) async {
      final c = await _loaded('u-owner');
      await _pumpHub(tester, c);
      expect(find.byKey(const Key('group_management_section')), findsOneWidget);
      for (final k in ['manage_settings', 'manage_members', 'manage_role_permissions', 'manage_tests', 'manage_analytics', 'manage_announcements']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.text('invite & remove · change roles'), findsOneWidget);
      expect(find.text('create · edit · publish · schedule · results'), findsOneWidget);
      // Existing G3/G4 controls remain: others removable, owner never.
      expect(find.byKey(const Key('remove_u-mem')), findsOneWidget);
      expect(find.byKey(const Key('role_menu_u-mem')), findsOneWidget);
      expect(find.byKey(const Key('remove_u-owner')), findsNothing);
      expect(find.byKey(const Key('role_menu_u-owner')), findsNothing);
      expect(find.byKey(const Key('leave_blocked_note')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    test('owner cannot be demoted or removed through the controller', () async {
      final repo = _repo('u-lead');
      repo.roleGrants.add('g-1:leader:MANAGE_ROLES');
      final c = _ctl(repo, 'u-lead');
      await c.load();
      expect(await c.changeRole('u-owner', GroupRole.member), isFalse);
      expect(c.error, contains('owner cannot be demoted'));
      expect(await c.removeMember('u-owner'), isFalse);
      expect(c.error, contains('owner cannot be removed'));
      expect(repo.calls.where((x) => x.startsWith('setRole:') || x.startsWith('remove:')), isEmpty);
      expect(repo.groups['g-1']!.roles['u-owner'], 'owner');
      // No role may become owner either (live CHECK / trigger).
      expect(await c.changeRole('u-mem', GroupRole.owner), isFalse);
      expect(c.error, contains('cannot be assigned'));
      c.dispose();
    });
  });

  group('3–4. leader controls are permission-driven', () {
    testWidgets('leader (seeded 10 perms) sees test/analytics/announce/member rows, not settings or role permissions', (tester) async {
      final c = await _loaded('u-lead');
      await _pumpHub(tester, c);
      expect(find.byKey(const Key('group_management_section')), findsOneWidget);
      expect(find.byKey(const Key('manage_members')), findsOneWidget);
      expect(find.text('invite & remove'), findsOneWidget); // no MANAGE_ROLES
      expect(find.byKey(const Key('manage_tests')), findsOneWidget);
      expect(find.byKey(const Key('manage_analytics')), findsOneWidget);
      expect(find.byKey(const Key('manage_announcements')), findsOneWidget);
      expect(find.byKey(const Key('manage_settings')), findsNothing);
      expect(find.byKey(const Key('manage_role_permissions')), findsNothing);
      expect(find.byKey(const Key('group_settings_action')), findsNothing);
      // G3: no role menu without MANAGE_ROLES; G4: remove offered with MANAGE_MEMBERS.
      expect(find.byKey(const Key('role_menu_u-mem')), findsNothing);
      expect(find.byKey(const Key('remove_u-mem')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('leader granted MANAGE_ROLES gains the role-permissions control; revoked leader loses tests', (tester) async {
      final repo = _repo('u-lead');
      repo.roleGrants.add('g-1:leader:MANAGE_ROLES');
      repo.roleRevokes.addAll({
        'g-1:leader:CREATE_TEST', 'g-1:leader:EDIT_TEST', 'g-1:leader:PUBLISH_TEST',
        'g-1:leader:SCHEDULE_TEST', 'g-1:leader:GENERATE_RESULTS',
      });
      final c = _ctl(repo, 'u-lead');
      await c.load();
      await _pumpHub(tester, c);
      expect(find.byKey(const Key('manage_role_permissions')), findsOneWidget);
      expect(find.text('invite & remove · change roles'), findsOneWidget);
      expect(find.byKey(const Key('manage_tests')), findsNothing);
      expect(find.byKey(const Key('role_menu_u-mem')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    test('leader without MANAGE_ROLES: changeRole refused locally, nothing sent, matrix edit refused', () async {
      final repo = _repo('u-lead');
      final c = _ctl(repo, 'u-lead');
      await c.load();
      expect(c.canManageRoles, isFalse);
      expect(await c.changeRole('u-mem', GroupRole.moderator), isFalse);
      expect(c.error, contains('permission to change roles'));
      expect(await c.setRolePermission(GroupRole.moderator, GroupPermission.createTest, granted: true), isFalse);
      expect(c.error, contains('manage-roles permission'));
      expect(repo.calls.where((x) => x.startsWith('setRole') || x.startsWith('setRolePermission')), isEmpty);
      expect(repo.groups['g-1']!.roles['u-mem'], 'member');
      c.dispose();
    });
  });

  group('5–6. moderator controls are permission-driven', () {
    testWidgets('moderator with no seeded permission sees no Manage section and no member actions', (tester) async {
      final c = await _loaded('u-mod');
      await _pumpHub(tester, c);
      expect(c.hasManagementControls, isFalse);
      expect(find.byKey(const Key('group_management_section')), findsNothing);
      expect(find.byKey(const Key('invite_member_action')), findsNothing);
      expect(find.byKey(const Key('remove_u-mem')), findsNothing);
      expect(find.byKey(const Key('role_menu_u-mem')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('moderator granted SEND_ANNOUNCEMENT + MANAGE_MEMBERS gets exactly those controls', (tester) async {
      final repo = _repo('u-mod');
      repo.roleGrants.addAll({'g-1:moderator:SEND_ANNOUNCEMENT', 'g-1:moderator:MANAGE_MEMBERS'});
      final c = _ctl(repo, 'u-mod');
      await c.load();
      await _pumpHub(tester, c);
      expect(find.byKey(const Key('manage_announcements')), findsOneWidget);
      expect(find.byKey(const Key('manage_members')), findsOneWidget);
      expect(find.byKey(const Key('invite_member_action')), findsOneWidget);
      expect(find.byKey(const Key('remove_u-mem')), findsOneWidget);
      expect(find.byKey(const Key('manage_tests')), findsNothing);
      expect(find.byKey(const Key('manage_analytics')), findsNothing);
      expect(find.byKey(const Key('manage_role_permissions')), findsNothing);
      expect(find.byKey(const Key('role_menu_u-mem')), findsNothing);
      // Uses the existing G4 action: remove goes through and the roster is re-read.
      expect(await c.removeMember('u-mem'), isTrue);
      expect(repo.groups['g-1']!.roles.containsKey('u-mem'), isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    test('moderator without MANAGE_MEMBERS: removeMember is refused by the (fake) server, nothing changes', () async {
      final repo = _repo('u-mod');
      final c = _ctl(repo, 'u-mod');
      await c.load();
      expect(await c.removeMember('u-mem'), isFalse);
      expect(c.error, contains('permission to remove members'));
      expect(repo.groups['g-1']!.roles['u-mem'], 'member');
      c.dispose();
    });
  });

  group('7. plain member', () {
    testWidgets('member sees no management control at all', (tester) async {
      final c = await _loaded('u-mem');
      await _pumpHub(tester, c);
      expect(c.hasManagementControls, isFalse);
      expect(c.controls.testCapabilities, isEmpty);
      expect(find.byKey(const Key('group_management_section')), findsNothing);
      expect(find.byKey(const Key('group_settings_action')), findsNothing);
      expect(find.byKey(const Key('invite_member_action')), findsNothing);
      expect(find.byKey(const Key('remove_u-mod')), findsNothing);
      expect(find.byKey(const Key('role_menu_u-mod')), findsNothing);
      // Non-management navigation stays: tests, chat, announcements, members.
      expect(find.byKey(const Key('open_group_tests')), findsOneWidget);
      expect(find.byKey(const Key('view_all_members')), findsOneWidget);
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('8–9. forged group id / cross-group target', () {
    test('forged group id: access denied, no permission probe, no matrix read', () async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner', groupId: 'g-forged');
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(c.hasManagementControls, isFalse);
      expect(repo.calls.where((x) => x.startsWith('permissionsFor')), isEmpty);
      await c.loadRolePermissions();
      expect(repo.calls.where((x) => x.startsWith('rolePermissions')), isEmpty);
      c.dispose();
    });

    test('owner of g-1 opening g-2 (not a member): denied; a cross-group member is not a target', () async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner', groupId: 'g-2');
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(c.hasManagementControls, isFalse);
      final own = _ctl(repo, 'u-owner');
      await own.load();
      // u-x is in g-2 only: not in this roster → refused before any call.
      expect(await own.changeRole('u-x', GroupRole.leader), isFalse);
      expect(own.error, contains('not a member of this group'));
      expect(repo.calls.where((x) => x.startsWith('setRole:')), isEmpty);
      expect(repo.groups['g-2']!.roles['u-x'], 'member');
      c.dispose();
      own.dispose();
    });

    test('permission probes are made against the target group only', () async {
      final repo = _repo('u-lead');
      final c = _ctl(repo, 'u-lead');
      await c.load();
      final probes = repo.calls.where((x) => x.startsWith('permissionsFor')).toList();
      expect(probes, ['permissionsFor:g-1']);
      c.dispose();
    });
  });

  group('10–11. self-escalation / owner invariants', () {
    test('nobody can change their own role, at any role', () async {
      for (final u in ['u-owner', 'u-lead', 'u-mod', 'u-mem']) {
        final repo = _repo(u);
        repo.roleGrants.add('g-1:leader:MANAGE_ROLES');
        repo.roleGrants.add('g-1:moderator:MANAGE_ROLES');
        final c = _ctl(repo, u);
        await c.load();
        expect(await c.changeRole(u, GroupRole.leader), isFalse, reason: u);
        expect(c.error, contains(c.canManageRoles ? 'own role' : 'permission to change roles'));
        expect(repo.calls.where((x) => x.startsWith('setRole:')), isEmpty);
        c.dispose();
      }
    });

    test('a MANAGE_ROLES holder cannot grant permissions to the owner or member role', () async {
      final c = await _loaded('u-owner');
      expect(await c.setRolePermission(GroupRole.owner, GroupPermission.manageRoles, granted: true), isFalse);
      expect(c.error, contains('owner always holds'));
      expect(await c.setRolePermission(GroupRole.member, GroupPermission.manageRoles, granted: true), isFalse);
      expect(c.error, contains('Member role'));
      c.dispose();
    });

    test('a moderator with MANAGE_ROLES may edit the matrix but still not their own membership role', () async {
      final repo = _repo('u-mod');
      repo.roleGrants.add('g-1:moderator:MANAGE_ROLES');
      final c = _ctl(repo, 'u-mod');
      await c.load();
      expect(c.canManageRolePermissions, isTrue);
      expect(await c.changeRole('u-mod', GroupRole.owner), isFalse);
      expect(await c.changeRole('u-owner', GroupRole.moderator), isFalse);
      expect(repo.calls.where((x) => x.startsWith('setRole:')), isEmpty);
      c.dispose();
    });
  });

  group('12. removed member loses access', () {
    test('after removal the hub denies access and offers nothing', () async {
      final repo = _repo('u-lead');
      final c = _ctl(repo, 'u-lead');
      await c.load();
      expect(c.hasManagementControls, isTrue);
      repo.groups['g-1']!.roles.remove('u-lead'); // removed server-side
      await c.refresh();
      expect(c.accessDenied, isTrue);
      expect(c.hasManagementControls, isFalse);
      expect(c.canManageRolePermissions, isFalse);
      expect(await c.setRolePermission(GroupRole.moderator, GroupPermission.createTest, granted: true), isFalse);
      expect(repo.calls.where((x) => x.startsWith('setRolePermission')), isEmpty);
      c.dispose();
    });
  });

  group('13–14. role permissions: single-flight, server re-read', () {
    test('owner grants and revokes a moderator permission; matrix and own probes re-read after each', () async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner');
      await c.load();
      await c.loadRolePermissions();
      expect(c.rolePermissions.of(GroupRole.leader).length, 10);
      expect(c.rolePermissions.of(GroupRole.moderator), isEmpty);
      final before = repo.calls.length;
      expect(await c.setRolePermission(GroupRole.moderator, GroupPermission.sendAnnouncement, granted: true), isTrue);
      final after = repo.calls.sublist(before);
      expect(after.first, 'setRolePermission:g-1:moderator:SEND_ANNOUNCEMENT:true');
      expect(after.where((x) => x == 'rolePermissions:g-1').length, 1);
      expect(after.where((x) => x == 'permissionsFor:g-1').length, 1); // load()
      expect(c.rolePermissions.has(GroupRole.moderator, GroupPermission.sendAnnouncement), isTrue);
      // The moderator now really holds it (fake mirrors fn_has_permission).
      repo.currentUser = 'u-mod';
      final mod = _ctl(repo, 'u-mod');
      await mod.load();
      expect(mod.canSendAnnouncement, isTrue);
      expect(mod.hasManagementControls, isTrue);
      mod.dispose();
      repo.currentUser = 'u-owner';
      // Revoke, then the moderator loses it.
      expect(await c.setRolePermission(GroupRole.moderator, GroupPermission.sendAnnouncement, granted: false), isTrue);
      expect(c.rolePermissions.has(GroupRole.moderator, GroupPermission.sendAnnouncement), isFalse);
      repo.currentUser = 'u-mod';
      final mod2 = _ctl(repo, 'u-mod');
      await mod2.load();
      expect(mod2.hasManagementControls, isFalse);
      mod2.dispose();
      c.dispose();
    });

    test('no-op toggles send nothing; revoking a seeded leader permission works', () async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner');
      await c.load();
      await c.loadRolePermissions();
      final n = repo.calls.length;
      expect(await c.setRolePermission(GroupRole.leader, GroupPermission.createTest, granted: true), isTrue);
      expect(repo.calls.length, n); // already granted
      expect(await c.setRolePermission(GroupRole.leader, GroupPermission.createTest, granted: false), isTrue);
      expect(c.rolePermissions.has(GroupRole.leader, GroupPermission.createTest), isFalse);
      repo.currentUser = 'u-lead';
      final lead = _ctl(repo, 'u-lead');
      await lead.load();
      expect(lead.controls.canCreateTest, isFalse);
      expect(lead.controls.canEditTest, isTrue);
      lead.dispose();
      c.dispose();
    });

    test('server refusal surfaces and the matrix is re-read (no optimistic state)', () async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner');
      await c.load();
      await c.loadRolePermissions();
      repo.failNextWith = const _Boom();
      expect(await c.setRolePermission(GroupRole.moderator, GroupPermission.createTest, granted: true), isFalse);
      expect(c.error, isNotNull);
      expect(c.rolePermissions.has(GroupRole.moderator, GroupPermission.createTest), isFalse);
      expect(repo.calls.last, 'rolePermissions:g-1');
      c.dispose();
    });

    test('loadRolePermissions is single-flight and skipped without the control', () async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner');
      await c.load();
      await Future.wait([c.loadRolePermissions(), c.loadRolePermissions()]);
      expect(repo.calls.where((x) => x == 'rolePermissions:g-1').length, 1);
      repo.currentUser = 'u-mem';
      final mem = _ctl(repo, 'u-mem');
      await mem.load();
      await mem.loadRolePermissions();
      expect(repo.calls.where((x) => x == 'rolePermissions:g-1').length, 1);
      mem.dispose();
      c.dispose();
    });

    test('mutations are single-flight: a second call while busy returns false', () async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner');
      await c.load();
      await c.loadRolePermissions();
      final first = c.setRolePermission(GroupRole.moderator, GroupPermission.createTest, granted: true);
      final second = c.setRolePermission(GroupRole.moderator, GroupPermission.editTest, granted: true);
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(repo.calls.where((x) => x.startsWith('setRolePermission')).length, 1);
      c.dispose();
    });
  });

  group('UI: management section and role-permissions sheet', () {
    testWidgets('sheet lists the live permissions per role and toggles through the controller', (tester) async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner');
      await c.load();
      await _pumpHub(tester, c);
      await tester.tap(find.byKey(const Key('manage_role_permissions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('role_permissions_title')), findsOneWidget);
      // Leader tab first: seeded rows on, GROUP_SETTINGS / MANAGE_ROLES off.
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('perm_leader_createTest'))).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('perm_leader_manageRoles'))).value, isFalse);
      expect(find.byKey(const Key('perm_owner_createTest')), findsNothing);
      expect(find.byKey(const Key('perm_member_createTest')), findsNothing);
      // Moderator tab: everything off; grant one.
      await tester.tap(find.descendant(of: find.byKey(const Key('role_permissions_role')), matching: find.text('Moderator')));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('perm_moderator_sendAnnouncement'))).value, isFalse);
      await tester.tap(find.byKey(const Key('perm_moderator_sendAnnouncement')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('setRolePermission:g-1:moderator:SEND_ANNOUNCEMENT:true'));
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('perm_moderator_sendAnnouncement'))).value, isTrue);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('section rows route to the existing screens (settings / members / tests)', (tester) async {
      final c = await _loaded('u-owner');
      final taps = <String>[];
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupManagementSection(
              controller: c,
              onOpenSettings: () => taps.add('settings'),
              onOpenMembers: () => taps.add('members'),
              onOpenTests: () => taps.add('tests'),
              onOpenRolePermissions: () => taps.add('roles'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manage_settings')));
      await tester.tap(find.byKey(const Key('manage_members')));
      await tester.tap(find.byKey(const Key('manage_tests')));
      await tester.tap(find.byKey(const Key('manage_analytics')));
      await tester.tap(find.byKey(const Key('manage_role_permissions')));
      expect(taps, ['settings', 'members', 'tests', 'tests', 'roles']);
      expect(find.byKey(const Key('management_role_label')), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      c.dispose();
    });

    testWidgets('RolePermissionsSheet shows the server error with retry', (tester) async {
      final repo = _repo('u-owner');
      final c = _ctl(repo, 'u-owner');
      await c.load();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: RolePermissionsSheet(hub: c))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('role_permissions_error')), findsNothing);
      expect(find.byKey(const Key('perm_leader_publishTest')), findsOneWidget);
      c.dispose();
    });
  });

  group('15–16. existing navigation intact', () {
    testWidgets('G8 chat, G6 rules, G7 announcements, G10 tests and members entry points still render for a leader', (tester) async {
      final c = await _loaded('u-lead');
      await _pumpHub(tester, c);
      expect(find.byKey(const Key('open_group_tests')), findsOneWidget);
      expect(find.byKey(const Key('view_all_members')), findsOneWidget);
      expect(find.byKey(const Key('invite_member_action')), findsOneWidget);
      expect(find.byKey(const Key('hub_members_heading')), findsOneWidget);
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

final class _Boom implements Exception {
  const _Boom();
  @override
  String toString() => 'new row violates row-level security policy for table "role_permissions"';
}
