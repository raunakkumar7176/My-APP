// G1 — Group Core. Model parsing, list/create/join state, hub access,
// leave, permission-aware removal and the error/empty states.
// Every fake mirrors a live rule; none of it invents backend behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/group_member.dart';
import 'package:my_praperation/features/group/data/group_repository.dart';
import 'package:my_praperation/features/group/domain/group_errors.dart';
import 'package:my_praperation/features/group/domain/group_privacy.dart';
import 'package:my_praperation/features/group/domain/group_role.dart';
import 'package:my_praperation/features/group/screens/group_create_screen.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/screens/group_list_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_list_controller.dart';

import 'fakes.dart';

void main() {
  group('Group model', () {
    test('parses the 7-column list RPC row and never carries invite_code', () {
      final g = Group.fromJson({
        'id': 'g-1',
        'name': 'Physics',
        'owner_id': 'u-owner',
        'logo_url': null,
        'created_at': '2026-09-01T10:00:00Z',
        'member_count': 4,
        'user_role': 'leader',
      });
      expect(g.id, 'g-1');
      expect(g.memberCount, 4);
      expect(g.userRole, 'leader');
      expect(g.isLeader, isTrue);
      expect(g.description, isNull);
      expect(g.privacy, isNull);
      expect(g.toJson().containsKey('invite_code'), isFalse);
    });

    test('parses a groups-table row with profile columns', () {
      final g = Group.fromJson({
        'id': 'g-1',
        'name': 'Physics',
        'description': 'Class 12',
        'owner_id': 'u-owner',
        'logo_url': null,
        'privacy': 'restricted',
        'created_at': '2026-09-01T10:00:00Z',
        'member_count': 2,
        'user_role': 'owner',
      });
      expect(g.description, 'Class 12');
      expect(GroupPrivacy.fromDb(g.privacy), GroupPrivacy.restricted);
      expect(g.isOwner, isTrue);
    });

    test('member_count defaults to 0 and user_role to member', () {
      final g = Group.fromJson({
        'id': 'g-1',
        'name': 'X',
        'owner_id': 'u-1',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(g.memberCount, 0);
      expect(g.isMember, isTrue);
    });

    test('GroupMember reads the embedded profile and keys on (group,user)', () {
      final m = GroupMember.fromJson({
        'group_id': 'g-1',
        'user_id': 'u-2',
        'role': 'moderator',
        'joined_at': '2026-09-02T08:00:00Z',
        'profiles': {'full_name': 'Asha', 'avatar_url': null},
      });
      expect(m.displayName, 'Asha');
      expect(GroupRole.fromDb(m.role), GroupRole.moderator);
      expect(
        m,
        GroupMember(
          groupId: 'g-1',
          userId: 'u-2',
          role: 'moderator',
          joinedAt: DateTime(2026, 9, 2),
        ),
      );
    });

    test('GroupMember falls back when the profile was not selected', () {
      final m = GroupMember.fromJson({
        'group_id': 'g-1',
        'user_id': 'u-3',
        'role': 'member',
        'joined_at': '2026-09-02T08:00:00Z',
      });
      expect(m.displayName, 'Member');
    });
  });

  group('Roles and validation', () {
    test('unknown or null role degrades to member, never to a privilege', () {
      expect(GroupRole.fromDb(null), GroupRole.member);
      expect(GroupRole.fromDb('admin'), GroupRole.member);
      expect(GroupRole.fromDb('OWNER'), GroupRole.owner);
      expect(GroupRole.owner.mayManageMembersByDefault, isTrue);
      expect(GroupRole.leader.mayManageMembersByDefault, isTrue);
      expect(GroupRole.moderator.mayManageMembersByDefault, isFalse);
      expect(GroupRole.member.mayManageMembersByDefault, isFalse);
      // Live: GROUP_SETTINGS is seeded for no role, so only the owner edits.
      expect(GroupRole.leader.mayEditGroupByDefault, isFalse);
      expect(GroupRole.owner.mayEditGroupByDefault, isTrue);
    });

    test('name validation mirrors the live 1..80 CHECK', () {
      expect(GroupErrors.validateName(''), isNotNull);
      expect(GroupErrors.validateName('   '), isNotNull);
      expect(GroupErrors.validateName('ok'), isNull);
      expect(GroupErrors.validateName('x' * 80), isNull);
      expect(GroupErrors.validateName('x' * 81), isNotNull);
    });

    test('invite codes are normalised the way fn_join_group compares them', () {
      expect(GroupErrors.normalizeInviteCode(' ab12cd34 '), 'AB12CD34');
      expect(GroupErrors.validateInviteCode(''), isNotNull);
    });

    test('server codes map to real messages', () {
      expect(
        GroupErrors.map('INVALID_INVITE_CODE', context: GroupErrorContext.join),
        contains('invite code'),
      );
      expect(
        GroupErrors.map(
          'NOT_AUTHORIZED',
          context: GroupErrorContext.removeMember,
        ),
        contains('permission'),
      );
      expect(
        GroupErrors.map(
          'new row violates row-level security policy',
          context: GroupErrorContext.update,
        ),
        contains('permission'),
      );
      expect(
        GroupErrors.map(
          'SocketException: failed',
          context: GroupErrorContext.load,
        ),
        contains('Network'),
      );
    });
  });

  group('GroupListController', () {
    test(
      'loads only the caller\'s groups; empty state after a clean load',
      () async {
        final repo = InMemoryGroupRepository(currentUser: 'u-me');
        final c = GroupListController(repository: repo);
        await c.load();
        expect(c.isEmpty, isTrue);
        expect(c.error, isNull);

        repo.seed(id: 'g-mine', ownerId: 'u-me');
        repo.seed(id: 'g-theirs', ownerId: 'u-other');
        await c.refresh();
        expect(c.groups.map((g) => g.id), ['g-mine']);
        expect(c.isEmpty, isFalse);
      },
    );

    test(
      'load failure surfaces a message and keeps the screen usable',
      () async {
        final repo = _FailingRepository();
        final c = GroupListController(repository: repo);
        await c.load();
        expect(c.error, isNotNull);
        expect(c.hasLoaded, isTrue);
        expect(c.groups, isEmpty);
      },
    );

    test('create: rejects an empty name before calling the server', () async {
      final repo = InMemoryGroupRepository();
      final c = GroupListController(repository: repo);
      expect(await c.create(name: '   '), isNull);
      expect(c.error, isNotNull);
      expect(repo.calls.where((x) => x.startsWith('create')), isEmpty);
    });

    test(
      'create: server creates group + owner membership, list refreshes',
      () async {
        final repo = InMemoryGroupRepository(currentUser: 'u-me');
        final c = GroupListController(repository: repo);
        final id = await c.create(name: '  Maths Batch  ', description: 'x');
        expect(id, isNotNull);
        expect(c.groups.single.name, 'Maths Batch');
        expect(
          c.groups.single.userRole,
          'owner',
          reason: 'seeded by fn_create_group',
        );
        expect(c.groups.single.memberCount, 1);
        expect(c.error, isNull);
      },
    );

    test(
      'create: a second call while busy is dropped (no duplicate group)',
      () async {
        final repo = _SlowRepository();
        final c = GroupListController(repository: repo);
        final first = c.create(name: 'A');
        final second = c.create(name: 'A');
        expect(await second, isNull, reason: 'busy → dropped');
        expect(await first, isNotNull);
        expect(repo.createCalls, 1);
      },
    );

    test('create: server error is surfaced, nothing is added', () async {
      final repo = InMemoryGroupRepository()
        ..failNextWith = const DataError(message: 'INVALID_PRIVACY');
      final c = GroupListController(repository: repo);
      expect(await c.create(name: 'A'), isNull);
      expect(c.error, isNotNull);
      expect(c.groups, isEmpty);
    });

    test('join: public group joins and appears in the list', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', inviteCode: 'ABCD1234');
      final c = GroupListController(repository: repo);
      final outcome = await c.joinByCode('abcd1234'); // case-insensitive
      expect(outcome, isA<JoinedGroup>());
      expect((outcome! as JoinedGroup).groupId, 'g-1');
      expect(c.groups.single.id, 'g-1');
    });

    test('join: restricted group files a request and joins nothing', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(
          id: 'g-r',
          ownerId: 'u-owner',
          privacy: 'restricted',
          inviteCode: 'RESTRICT',
        );
      final c = GroupListController(repository: repo);
      expect(await c.joinByCode('RESTRICT'), isA<JoinRequestFiled>());
      expect(c.groups, isEmpty);
      expect(repo.joinRequests, ['g-r:u-me']);
    });

    test('join: joining twice is idempotent, not an error', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', inviteCode: 'ABCD1234');
      final c = GroupListController(repository: repo);
      await c.joinByCode('ABCD1234');
      final again = await c.joinByCode('ABCD1234');
      expect(again, isA<JoinedGroup>());
      expect((again! as JoinedGroup).alreadyMember, isTrue);
      expect(c.groups.length, 1);
      expect(c.groups.single.memberCount, 2);
    });

    test('join: an unknown code is rejected with the server message', () async {
      final repo = InMemoryGroupRepository();
      final c = GroupListController(repository: repo);
      expect(await c.joinByCode('NOPE0000'), isNull);
      expect(c.error, contains('invite code'));
      expect(
        await c.joinByCode('  '),
        isNull,
        reason: 'blank never hits the server',
      );
    });
  });

  group('GroupHubController access', () {
    test('member opens the hub with role, count and privacy', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-me',
      );
      await c.load();
      expect(c.accessDenied, isFalse);
      expect(c.myRole, GroupRole.member);
      expect(c.memberCount, 2);
      expect(c.privacy, GroupPrivacy.public);
      expect(c.members.length, 2);
      expect(c.canManageMembers, isFalse);
      expect(c.canLeave, isTrue);
      c.dispose();
    });

    test('owner opens the hub, can manage members, cannot leave', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me', members: {'u-2': 'member'});
      final c = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-me',
      );
      await c.load();
      expect(c.isOwner, isTrue);
      expect(c.canManageMembers, isTrue);
      expect(c.canEditBasics, isTrue);
      expect(c.canLeave, isFalse, reason: 'no ownership transfer exists');
      expect(await c.leave(), isFalse);
      expect(c.error, contains('own this group'));
      c.dispose();
    });

    test(
      'non-member is denied even though a public group row is readable',
      () async {
        final repo = InMemoryGroupRepository(currentUser: 'u-outsider')
          ..seed(id: 'g-1', ownerId: 'u-owner', privacy: 'public');
        final c = GroupHubController(
          groupId: 'g-1',
          repository: repo,
          currentUserId: 'u-outsider',
        );
        await c.load();
        expect(c.accessDenied, isTrue);
        expect(c.group, isNull);
        expect(c.members, isEmpty);
        c.dispose();
      },
    );

    test('invalid / deleted group id is handled as access denied', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me');
      final c = GroupHubController(
        groupId: 'does-not-exist',
        repository: repo,
        currentUserId: 'u-me',
      );
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(c.error, isNull, reason: 'not an error state, an access state');
      c.dispose();
    });

    test(
      'load failure keeps an error state, not a false access denial',
      () async {
        final c = GroupHubController(
          groupId: 'g-1',
          repository: _FailingRepository(),
          currentUserId: 'u-me',
        );
        await c.load();
        expect(c.error, isNotNull);
        expect(c.accessDenied, isFalse);
        c.dispose();
      },
    );
  });

  group('Leave and remove', () {
    test('leaving removes the membership and access', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-me',
      );
      await c.load();
      expect(await c.leave(), isTrue);
      expect(c.hasLeft, isTrue);
      expect(c.accessDenied, isTrue);

      // And the group is gone from the list the server returns.
      final list = GroupListController(repository: repo);
      await list.load();
      expect(list.groups, isEmpty);
      c.dispose();
    });

    test('leader removes a member; the roster and count refresh', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(
          id: 'g-1',
          ownerId: 'u-owner',
          members: {'u-me': 'leader', 'u-2': 'member'},
        );
      final c = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-me',
      );
      await c.load();
      expect(c.canManageMembers, isTrue);
      expect(await c.removeMember('u-2'), isTrue);
      expect(c.members.map((m) => m.userId), isNot(contains('u-2')));
      expect(c.memberCount, 2);
      c.dispose();
    });

    test(
      'plain member is refused by the server even if the call is made',
      () async {
        final repo = InMemoryGroupRepository(currentUser: 'u-me')
          ..seed(
            id: 'g-1',
            ownerId: 'u-owner',
            members: {'u-me': 'member', 'u-2': 'member'},
          );
        final c = GroupHubController(
          groupId: 'g-1',
          repository: repo,
          currentUserId: 'u-me',
        );
        await c.load();
        expect(c.canManageMembers, isFalse, reason: 'button is hidden');
        expect(
          await c.removeMember('u-2'),
          isFalse,
          reason: 'and the server refuses',
        );
        expect(c.error, contains('permission'));
        expect(repo.groups['g-1']!.roles.containsKey('u-2'), isTrue);
        c.dispose();
      },
    );

    test(
      'the owner can never be removed, and you cannot remove yourself',
      () async {
        final repo = InMemoryGroupRepository(currentUser: 'u-me')
          ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'leader'});
        final c = GroupHubController(
          groupId: 'g-1',
          repository: repo,
          currentUserId: 'u-me',
        );
        await c.load();
        expect(await c.removeMember('u-owner'), isFalse);
        expect(c.error, contains('owner'));
        expect(await c.removeMember('u-me'), isFalse);
        expect(c.error, contains('Leave group'));
        expect(repo.groups['g-1']!.roles.containsKey('u-owner'), isTrue);
        c.dispose();
      },
    );

    test('updateBasics: owner succeeds, non-owner is refused', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-me');
      final owner = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-me',
      );
      await owner.load();
      expect(
        await owner.updateBasics(name: ' New name ', description: 'd'),
        isTrue,
      );
      expect(owner.group!.name, 'New name');
      expect(await owner.updateBasics(name: ''), isFalse);
      owner.dispose();

      repo.currentUser = 'u-2';
      repo.groups['g-1']!.roles['u-2'] = 'leader';
      final leader = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-2',
      );
      await leader.load();
      expect(leader.canEditBasics, isFalse);
      expect(await leader.updateBasics(name: 'Hijack'), isFalse);
      expect(repo.groups['g-1']!.name, 'New name');
      leader.dispose();
    });
  });

  group('Screens', () {
    testWidgets('list: loading → cards with count and role; empty state', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me');
      final c = GroupListController(repository: repo);
      await tester.pumpWidget(
        MaterialApp(home: GroupListScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('groups_empty')), findsOneWidget);

      repo.seed(
        id: 'g-1',
        name: 'Physics',
        ownerId: 'u-me',
        members: {'u-2': 'member'},
      );
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group_card_g-1')), findsOneWidget);
      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('2 members · Owner'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('create screen: empty name blocked, valid name submits once', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me');
      final c = GroupListController(repository: repo);
      // A real router: creating must land on the new group's hub route.
      final router = GoRouter(
        initialLocation: '/groups/create',
        routes: [
          GoRoute(
            path: '/groups/create',
            builder: (_, _) => GroupCreateScreen(controller: c),
          ),
          GoRoute(
            path: '/groups/:groupId',
            builder: (_, state) =>
                Scaffold(body: Text('hub:${state.pathParameters['groupId']}')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('create_group_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Group name is required.'), findsOneWidget);
      expect(repo.calls.where((x) => x.startsWith('create')), isEmpty);

      await tester.enterText(find.byKey(const Key('group_name_field')), 'Chem');
      await tester.tap(find.byKey(const Key('privacy_restricted')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create_group_submit')));
      await tester.pump();
      expect(repo.calls.where((x) => x.startsWith('create')).length, 1);
      expect(repo.groups.values.single.privacy, 'restricted');
      await tester.pumpAndSettle();
      expect(find.textContaining('hub:'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('hub: header, roster, remove offered only with permission', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(
          id: 'g-1',
          name: 'Physics',
          ownerId: 'u-me',
          members: {'u-2': 'member'},
        );
      final c = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-me',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GroupHubScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('group_header_meta')), findsOneWidget);
      expect(find.text('2 members · Owner · Public'), findsOneWidget);
      expect(find.byKey(const Key('member_u-2')), findsOneWidget);
      expect(find.byKey(const Key('remove_u-2')), findsOneWidget);
      // The owner's own row is never removable.
      expect(find.byKey(const Key('remove_u-me')), findsNothing);
      // And the owner cannot leave — the reason is shown, not a dead button.
      expect(find.byKey(const Key('leave_group_button')), findsNothing);
      expect(find.byKey(const Key('leave_blocked_note')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('hub: non-member sees the access state, not the group', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository(currentUser: 'u-out')
        ..seed(id: 'g-1', name: 'Secret', ownerId: 'u-owner');
      final c = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-out',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GroupHubScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Group not available'), findsOneWidget);
      expect(find.text('Secret'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('hub: member sees a working Leave button and confirmation', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = GroupHubController(
        groupId: 'g-1',
        repository: repo,
        currentUserId: 'u-me',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GroupHubScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('leave_group_button')));
      await tester.pumpAndSettle();
      expect(find.text('Leave group?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.groups['g-1']!.roles.containsKey('u-me'), isTrue);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

class _FailingRepository implements GroupRepository {
  @override
  Future<List<Group>> myGroups() async =>
      throw const DataError(message: 'Could not load groups.');
  @override
  Future<Group?> groupForMember(String groupId) async =>
      throw const DataError(message: 'Could not load groups.');
  @override
  Future<List<GroupMember>> members(String groupId) async => const [];
  @override
  Future<String> create({
    required String name,
    String description = '',
    String privacy = 'public',
  }) async => throw const DataError(message: 'nope');
  @override
  Future<JoinOutcome> joinByCode(String inviteCode) async =>
      throw const DataError(message: 'nope');
  @override
  Future<void> leave(String groupId) async {}
  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {}
  @override
  Future<bool> canManageMembers(String groupId) async => false;
  @override
  Future<void> updateBasics({
    required String groupId,
    required String name,
    required String description,
    String? privacy,
  }) async {}
  @override
  Future<bool> canEditSettings(String groupId) async => false;
  @override
  Future<void> clearLogo(String groupId) async {}
}

/// Create takes a turn to complete, so the busy guard can be observed.
class _SlowRepository extends InMemoryGroupRepository {
  int createCalls = 0;

  @override
  Future<String> create({
    required String name,
    String description = '',
    String privacy = 'public',
  }) async {
    createCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.create(name: name, description: description, privacy: privacy);
  }
}
