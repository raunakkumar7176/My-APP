// G4 — Members Hub: roster states, local search + role filter, member
// detail (permitted fields only), and the role / remove actions reused from
// G1/G3 through the shared MemberTile. The fake mirrors the live rules.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group_member.dart';
import 'package:my_praperation/features/group/domain/group_role.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/screens/group_members_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

InMemoryGroupRepository _roster({String me = 'u-me', String myRole = 'owner'}) {
  final repo = InMemoryGroupRepository(currentUser: me);
  final owner = myRole == 'owner' ? me : 'u-owner';
  repo.seed(
    id: 'g-1',
    name: 'Physics',
    ownerId: owner,
    members: {
      if (myRole != 'owner') me: myRole,
      'u-asha': 'leader',
      'u-ravi': 'moderator',
      'u-neha': 'member',
    },
  );
  repo.profileNames.addAll({
    'u-asha': 'Asha Verma',
    'u-ravi': 'Ravi Kumar',
    'u-neha': 'Neha Singh',
    'u-me': 'Me Myself',
    'u-owner': 'Owner One',
  });
  repo.studentCodes.addAll({'u-asha': 'STU-1001', 'u-neha': 'STU-2002'});
  repo.bios['u-asha'] = 'Loves optics.';
  return repo;
}

void main() {
  group('GroupMember profile fields', () {
    test('parses student_code and bio from the embed; never mobile', () {
      final m = GroupMember.fromJson({
        'group_id': 'g-1',
        'user_id': 'u-1',
        'role': 'member',
        'joined_at': '2026-09-02T08:00:00Z',
        'profiles': {
          'full_name': 'Asha',
          'avatar_url': null,
          'student_code': 'STU-1',
          'bio': 'hi',
          'mobile': '9999999999',
        },
      });
      expect(m.studentCode, 'STU-1');
      expect(m.bio, 'hi');
      // The model has no field for it, so it can never be displayed.
      expect(m.toString().contains('9999'), isFalse);
    });
  });

  group('Search and role filter (local, over the permitted roster)', () {
    test(
      'no filter → full roster; query is case-insensitive and trimmed',
      () async {
        final c = _hub(_roster());
        await c.load();
        expect(c.filteredMembers.length, 4);
        expect(c.hasMemberFilter, isFalse);

        c.setMemberQuery('  ASHA ');
        expect(c.filteredMembers.map((m) => m.userId), ['u-asha']);
        c.setMemberQuery('stu-2');
        expect(c.filteredMembers.map((m) => m.userId), [
          'u-neha',
        ], reason: 'student code matches too');
        c.setMemberQuery('   ');
        expect(c.hasMemberFilter, isFalse);
        expect(c.filteredMembers.length, 4);
        c.dispose();
      },
    );

    test('role filter alone, and combined with the query (AND)', () async {
      final c = _hub(_roster());
      await c.load();
      for (final r in GroupRole.values) {
        c.setRoleFilter(r);
        expect(
          c.filteredMembers.every((m) => GroupRole.fromDb(m.role) == r),
          isTrue,
        );
      }
      c.setRoleFilter(GroupRole.member);
      expect(c.filteredMembers.map((m) => m.userId), ['u-neha']);
      c.setMemberQuery('asha'); // leader, not member → nothing
      expect(c.filteredMembers, isEmpty);
      c.setRoleFilter(GroupRole.leader);
      expect(c.filteredMembers.map((m) => m.userId), ['u-asha']);

      c.clearMemberFilters();
      expect(c.hasMemberFilter, isFalse);
      expect(c.filteredMembers.length, 4);
      c.dispose();
    });

    test('filters never widen the roster and survive a refresh', () async {
      final repo = _roster();
      final c = _hub(repo);
      await c.load();
      c.setMemberQuery('neha');
      await c.refresh();
      expect(c.memberQuery, 'neha');
      expect(c.filteredMembers.map((m) => m.userId), ['u-neha']);
      expect(c.members.length, 4, reason: 'unfiltered roster intact');
      c.dispose();
    });

    test('me resolves the caller\'s own row', () async {
      final c = _hub(_roster(myRole: 'member'));
      await c.load();
      expect(c.me?.userId, 'u-me');
      expect(GroupRole.fromDb(c.me!.role), GroupRole.member);
      c.dispose();
    });
  });

  group('Member count stays server-derived', () {
    test('remove and role change reload the count', () async {
      final repo = _roster();
      final c = _hub(repo);
      await c.load();
      expect(c.memberCount, 4);
      expect(await c.removeMember('u-neha'), isTrue);
      expect(c.memberCount, 3);
      expect(await c.changeRole('u-ravi', GroupRole.member), isTrue);
      expect(c.memberCount, 3);
      expect(c.members.firstWhere((m) => m.userId == 'u-ravi').role, 'member');
      c.dispose();
    });
  });

  group('Members screen', () {
    Future<GroupHubController> pump(
      WidgetTester tester,
      InMemoryGroupRepository repo, {
      String user = 'u-me',
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _hub(repo, user: user);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupMembersScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('loading → loaded: names, badges, codes, You marker', (
      tester,
    ) async {
      final c = await pump(tester, _roster());
      expect(find.byKey(const Key('members_title')), findsOneWidget);
      expect(find.text('Members · 4'), findsOneWidget);
      expect(find.text('Me Myself (you)'), findsOneWidget);
      expect(find.text('Asha Verma'), findsOneWidget);
      expect(find.byKey(const Key('member_code_u-asha')), findsOneWidget);
      expect(find.byKey(const Key('member_code_u-ravi')), findsNothing);
      expect(find.byKey(const Key('role_badge_owner')), findsOneWidget);
      expect(find.byKey(const Key('role_badge_leader')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('search + role chips + no-match + clear', (tester) async {
      final c = await pump(tester, _roster());
      await tester.enterText(find.byKey(const Key('member_search')), 'RAVI');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member_u-ravi')), findsOneWidget);
      expect(find.byKey(const Key('member_u-asha')), findsNothing);

      await tester.tap(find.byKey(const Key('role_chip_member')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('members_no_match')), findsOneWidget);

      await tester.tap(find.byKey(const Key('members_clear_filters')));
      await tester.pumpAndSettle();
      expect(c.hasMemberFilter, isFalse);
      expect(find.byKey(const Key('member_u-asha')), findsOneWidget);
      expect(find.byKey(const Key('member_search_clear')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('error → retry', (tester) async {
      final repo = _roster();
      repo.failNextWith = const DataError(message: 'Network error.');
      // groupForMember is not guarded by failNextWith; simulate a load error
      // through a repository that throws on the roster read.
      final c = await pump(tester, _FailingRosterRepository(repo));
      expect(find.byKey(const Key('members_retry')), findsOneWidget);
      expect(find.text('Network error.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('non-member sees the access state', (tester) async {
      final repo = _roster()..currentUser = 'u-outsider';
      final c = await pump(tester, repo, user: 'u-outsider');
      expect(find.text('Group not available'), findsOneWidget);
      expect(find.byKey(const Key('member_search')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('member detail shows only permitted fields', (tester) async {
      final c = await pump(tester, _roster());
      await tester.tap(find.byKey(const Key('member_u-asha')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member_detail')), findsOneWidget);
      expect(find.byKey(const Key('detail_code')), findsOneWidget);
      expect(find.byKey(const Key('detail_bio')), findsOneWidget);
      expect(find.text('Loves optics.'), findsOneWidget);
      expect(find.text('Physics'), findsOneWidget);
      expect(find.textContaining('Member since'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // dismiss
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('member_u-ravi')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail_code')), findsNothing);
      expect(find.byKey(const Key('detail_bio')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets(
      'owner: role menu shows old → new and applies; owner row has no actions',
      (tester) async {
        final repo = _roster();
        final c = await pump(tester, repo);
        expect(find.byKey(const Key('role_menu_u-me')), findsNothing);
        expect(find.byKey(const Key('remove_u-me')), findsNothing);

        await tester.tap(find.byKey(const Key('role_menu_u-neha')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('role_option_u-neha_moderator')));
        await tester.pumpAndSettle();
        expect(find.text('Neha Singh: Member → Moderator'), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirm_role_change')));
        await tester.pumpAndSettle();
        expect(repo.groups['g-1']!.roles['u-neha'], 'moderator');
        expect(find.text('Neha Singh is now Moderator.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('remove: confirm → roster and count refresh; failure shown', (
      tester,
    ) async {
      final repo = _roster();
      final c = await pump(tester, repo);
      await tester.tap(find.byKey(const Key('remove_u-neha')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member_u-neha')), findsNothing);
      expect(find.text('Members · 3'), findsOneWidget);

      repo.failNextWith = const DataError(message: 'Network error.');
      await tester.tap(find.byKey(const Key('remove_u-ravi')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_remove')));
      await tester.pumpAndSettle();
      expect(find.text('Network error.'), findsWidgets);
      expect(find.byKey(const Key('member_u-ravi')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('leader: remove offered, role menu not; member: nothing', (
      tester,
    ) async {
      final repo = _roster(myRole: 'leader');
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('remove_u-neha')), findsOneWidget);
      expect(find.byKey(const Key('role_menu_u-neha')), findsNothing);
      expect(find.byKey(const Key('remove_u-owner')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();

      final repo2 = _roster(myRole: 'member');
      final c2 = await pump(tester, repo2);
      expect(find.byType(PopupMenuButton<GroupRole>), findsNothing);
      expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c2.dispose();
    });

    testWidgets('hub: View all opens the members hub', (tester) async {
      final repo = _roster();
      final c = _hub(repo);
      // Tall viewport: the roster sits below the G6/G7 sections in the
      // hub's lazy ListView.
      tester.view.physicalSize = const Size(800, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupHubScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hub_members_heading')), findsOneWidget);
      expect(find.byKey(const Key('view_all_members')), findsOneWidget);
      expect(find.byKey(const Key('member_u-asha')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

/// Roster read fails once, so the screen reaches its error/retry state.
class _FailingRosterRepository extends InMemoryGroupRepository {
  _FailingRosterRepository(InMemoryGroupRepository source)
    : super(currentUser: source.currentUser) {
    groups.addAll(source.groups);
    profileNames.addAll(source.profileNames);
  }
  bool _failed = false;

  @override
  Future<List<GroupMember>> members(String groupId) async {
    if (!_failed) {
      _failed = true;
      throw const DataError(message: 'Network error.');
    }
    return super.members(groupId);
  }
}
