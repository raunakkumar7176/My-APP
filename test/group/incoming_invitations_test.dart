// G5.4 — incoming invitations on the verified contracts:
//   group_invitations (id, group_id, inviter_id, invitee_id, status, created_at)
//   fn_accept_group_invitation(uuid) / fn_decline_group_invitation(uuid)
// An invitation is never membership; only the server-created membership row
// (visible through rpc_get_user_groups after refresh) opens a hub.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/group_invitation.dart';
import 'package:my_praperation/features/group/domain/group_errors.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/screens/group_list_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_list_controller.dart';
import 'package:my_praperation/features/group/widgets/incoming_invitations_section.dart';

import 'fakes.dart';

InMemoryGroupRepository _repo() => InMemoryGroupRepository(currentUser: 'u-me')
  ..seed(
    id: 'g-priv',
    name: 'Private Group',
    ownerId: 'u-owner',
    privacy: 'private',
  );

void main() {
  group('GroupInvitation model', () {
    test('N/O: parses only the live columns; no expiry field exists', () {
      final i = GroupInvitation.fromJson({
        'id': 'i-1',
        'group_id': 'g-1',
        'inviter_id': 'u-a',
        'invitee_id': 'u-me',
        'status': 'pending',
        'created_at': '2026-09-12T09:30:00Z',
        'expires_at': '2099-01-01', // not live; must be ignored
      });
      expect(i.isPending, isTrue);
      expect(i.toJson().keys, {
        'id',
        'group_id',
        'inviter_id',
        'invitee_id',
        'status',
        'created_at',
      });
      expect(i.toJson().containsKey('expires_at'), isFalse);
      for (final s in ['accepted', 'declined', 'expired']) {
        expect(
          GroupInvitation.fromJson(i.toJson()..['status'] = s).isPending,
          isFalse,
        );
      }
    });

    test('P: no invitation data in Group', () {
      final g = Group.fromJson({
        'id': 'g',
        'name': 'n',
        'owner_id': 'o',
        'created_at': '2026-09-12T09:30:00Z',
        'invitation_id': 'i-1',
      });
      expect(g.toJson().keys.any((k) => k.contains('invit')), isFalse);
    });
  });

  group('GroupListController invitations', () {
    test('A/Q: only the caller\'s pending invitee rows, one query', () async {
      final repo = _repo()
        ..seedInvitation(id: 'i-mine', groupId: 'g-priv')
        ..seedInvitation(id: 'i-other', groupId: 'g-priv', inviteeId: 'u-other')
        ..seedInvitation(id: 'i-done', groupId: 'g-priv', status: 'accepted');
      final c = GroupListController(repository: repo);
      await c.load();
      expect(c.invitations.map((i) => i.id), ['i-mine']);
      expect(repo.invitationReads, ['mine:pending']);
      expect(c.hasInvitations, isTrue);
    });

    test('C: empty state', () async {
      final c = GroupListController(repository: _repo());
      await c.load();
      expect(c.hasInvitations, isFalse);
      expect(c.invitationsError, isNull);
    });

    test('E: read failure is isolated; retry recovers', () async {
      final repo = _FailingInvitationsRepository()
        ..seed(id: 'g-mine', ownerId: 'u-me')
        ..seedInvitation(id: 'i-1', groupId: 'g-priv');
      final c = GroupListController(repository: repo);
      await c.load();
      expect(c.groups.single.id, 'g-mine', reason: 'groups still shown');
      expect(c.invitationsError, isNotNull);
      expect(c.invitations, isEmpty);
      repo.failReads = false;
      await c.retryInvitations();
      expect(c.invitationsError, isNull);
      expect(c.invitations.single.id, 'i-1');
    });

    test('F/H: accept calls the function with the exact id; groups + '
        'invitations refresh; group id returned only via membership', () async {
      final repo = _repo()..seedInvitation(id: 'i-1', groupId: 'g-priv');
      final c = GroupListController(repository: repo);
      await c.load();
      expect(c.groups, isEmpty);
      final groupId = await c.acceptInvitation(c.invitations.single);
      expect(repo.calls, contains('acceptInvitation:i-1'));
      expect(groupId, 'g-priv', reason: 'server inserted the membership row');
      expect(c.groups.single.id, 'g-priv');
      expect(c.hasInvitations, isFalse);
      expect(c.error, isNull);
    });

    test(
      'I: accept whose membership is not visible returns null (no guess)',
      () async {
        final repo = _NoMembershipAcceptRepository()
          ..seed(id: 'g-priv', ownerId: 'u-owner', privacy: 'private')
          ..seedInvitation(id: 'i-1', groupId: 'g-priv');
        final c = GroupListController(repository: repo);
        await c.load();
        final groupId = await c.acceptInvitation(c.invitations.single);
        expect(groupId, isNull);
        expect(c.groups, isEmpty);
        expect(c.error, isNull);
      },
    );

    test('G/K: accept and decline are single-flight', () async {
      final repo = _SlowInvitationRepository()
        ..seed(id: 'g-priv', ownerId: 'u-owner', privacy: 'private')
        ..seedInvitation(id: 'i-1', groupId: 'g-priv')
        ..seedInvitation(id: 'i-2', groupId: 'g-priv');
      final c = GroupListController(repository: repo);
      await c.load();
      final a = c.acceptInvitation(c.invitations[0]);
      final b = c.declineInvitation(c.invitations[1]);
      expect(await b, isFalse, reason: 'dropped while the accept runs');
      expect(await a, 'g-priv');
      expect(repo.calls.where((x) => x.contains('Invitation:')).length, 1);
    });

    test(
      'J: decline calls the function with the exact id; no membership',
      () async {
        final repo = _repo()..seedInvitation(id: 'i-1', groupId: 'g-priv');
        final c = GroupListController(repository: repo);
        await c.load();
        expect(await c.declineInvitation(c.invitations.single), isTrue);
        expect(repo.calls, contains('declineInvitation:i-1'));
        expect(c.hasInvitations, isFalse);
        expect(c.groups, isEmpty);
        expect(repo.groups['g-priv']!.roles.containsKey('u-me'), isFalse);
      },
    );

    test('L2: live codes INVITATION_NOT_FOUND / INVITATION_NOT_PENDING map to the stale message (F-06)', () {
      for (final raw in ['INVITATION_NOT_FOUND', 'INVITATION_NOT_PENDING', 'P0001: INVITATION_NOT_PENDING']) {
        expect(GroupErrors.map(raw, context: GroupErrorContext.invitation), contains('no longer available'), reason: raw);
      }
    });

    test('L: INVITE_NOT_FOUND → stale message and list refreshed', () async {
      final repo = _repo()..seedInvitation(id: 'i-1', groupId: 'g-priv');
      final c = GroupListController(repository: repo);
      await c.load();
      final stale = c.invitations.single;
      // Invitation withdrawn/decided externally between load and click.
      repo.invitations.clear();
      expect(await c.acceptInvitation(stale), isNull);
      expect(c.error, contains('no longer available'));
      expect(c.hasInvitations, isFalse, reason: 're-read from the server');
      expect(c.groups, isEmpty);
    });

    test(
      'network failure on decline surfaces the message; row untouched',
      () async {
        final repo = _repo()..seedInvitation(id: 'i-1', groupId: 'g-priv');
        final c = GroupListController(repository: repo);
        await c.load();
        repo.failNextWith = const DataError(message: 'Network error.');
        expect(await c.declineInvitation(c.invitations.single), isFalse);
        expect(c.error, 'Network error.');
        expect(c.invitations.single.isPending, isTrue);
        expect(c.actingInvitationId, isNull);
      },
    );
  });

  group('Screens', () {
    Future<void> pumpTall(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: home));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'B/D: pending invitation renders Accept/Decline; loading first',
      (tester) async {
        final repo = _SlowInvitationRepository()
          ..seed(id: 'g-priv', ownerId: 'u-owner', privacy: 'private')
          ..seedInvitation(id: 'i-1', groupId: 'g-priv');
        final c = GroupListController(repository: repo);
        await tester.pumpWidget(
          MaterialApp(home: GroupListScreen(controller: c)),
        );
        await tester.pump(); // load in flight (slow invitations read)
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('invitations_section')), findsOneWidget);
        expect(find.byKey(const Key('accept_i-1')), findsOneWidget);
        expect(find.byKey(const Key('decline_i-1')), findsOneWidget);
        expect(find.text('Group invitation'), findsOneWidget);
        expect(
          find.text('Private Group'),
          findsNothing,
          reason: 'group name is not resolved for a non-member',
        );
        expect(find.textContaining('xpire'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('M: non-pending rows show status only, no controls', (
      tester,
    ) async {
      final stale = GroupInvitation(
        id: 'i-old',
        groupId: 'g-priv',
        inviterId: 'u-owner',
        inviteeId: 'u-me',
        status: 'expired',
        createdAt: DateTime(2026, 9, 1),
      );
      final repo = _StaleRowsRepository(stale)
        ..seed(id: 'g-priv', ownerId: 'u-owner', privacy: 'private');
      final c = GroupListController(repository: repo);
      await c.load();
      await pumpTall(
        tester,
        Scaffold(
          body: IncomingInvitationsSection(controller: c, onAccepted: (_) {}),
        ),
      );
      expect(find.byKey(const Key('invitation_i-old')), findsOneWidget);
      expect(find.byKey(const Key('accept_i-old')), findsNothing);
      expect(find.byKey(const Key('decline_i-old')), findsNothing);
      expect(
        find.textContaining('expired'),
        findsOneWidget,
        reason: 'server status shown verbatim; no date invented',
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('E: read failure card with Retry', (tester) async {
      final repo = _FailingInvitationsRepository()
        ..seedInvitation(id: 'i-1', groupId: 'g-priv');
      final c = GroupListController(repository: repo);
      await pumpTall(tester, GroupListScreen(controller: c));
      expect(find.byKey(const Key('invitations_error')), findsOneWidget);
      repo.failReads = false;
      await tester.tap(find.byKey(const Key('invitations_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('accept_i-1')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('H/I: accept opens the hub only via confirmed membership; '
        'decline confirms and removes', (tester) async {
      final repo = _repo()
        ..seedInvitation(id: 'i-1', groupId: 'g-priv')
        ..seedInvitation(id: 'i-2', groupId: 'g-priv');
      // Second invitation for the same group would violate UNIQUE live; use
      // a second group instead.
      repo.invitations.removeLast();
      repo.seed(id: 'g-2', ownerId: 'u-owner', privacy: 'private');
      repo.seedInvitation(id: 'i-2', groupId: 'g-2');
      final c = GroupListController(repository: repo);
      final pushed = <String>[];
      final router = GoRouter(
        initialLocation: '/groups',
        routes: [
          GoRoute(
            path: '/groups',
            builder: (_, _) => GroupListScreen(controller: c),
            routes: [
              GoRoute(
                path: ':groupId',
                builder: (_, state) {
                  pushed.add(state.pathParameters['groupId']!);
                  return const Scaffold(body: Text('hub'));
                },
              ),
            ],
          ),
        ],
      );
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('decline_i-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_decline')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invitation_i-2')), findsNothing);
      expect(pushed, isEmpty);

      await tester.tap(find.byKey(const Key('accept_i-1')));
      await tester.pumpAndSettle();
      expect(pushed, ['g-priv'], reason: 'membership confirmed by refresh');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('I: hub stays closed for an invitee who has not accepted', (
      tester,
    ) async {
      final repo = _repo()..seedInvitation(id: 'i-1', groupId: 'g-priv');
      final hub = GroupHubController(
        groupId: 'g-priv',
        repository: repo,
        currentUserId: 'u-me',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GroupHubScreen(groupId: 'g-priv', controller: hub),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Group not available'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      hub.dispose();
    });
  });
}

class _FailingInvitationsRepository extends InMemoryGroupRepository {
  _FailingInvitationsRepository() : super(currentUser: 'u-me');
  bool failReads = true;
  @override
  Future<List<GroupInvitation>> myInvitations() async {
    if (failReads) throw const DataError(message: 'Network error.');
    return super.myInvitations();
  }
}

/// Accept succeeds server-side but the membership is not visible yet.
class _NoMembershipAcceptRepository extends InMemoryGroupRepository {
  _NoMembershipAcceptRepository() : super(currentUser: 'u-me');
  @override
  Future<void> acceptInvitation(String invitationId) async {
    calls.add('acceptInvitation:$invitationId');
    invitations.removeWhere((i) => i.id == invitationId);
  }
}

class _SlowInvitationRepository extends InMemoryGroupRepository {
  _SlowInvitationRepository() : super(currentUser: 'u-me');
  @override
  Future<List<GroupInvitation>> myInvitations() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.myInvitations();
  }

  @override
  Future<void> acceptInvitation(String invitationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.acceptInvitation(invitationId);
  }
}

/// Returns a non-pending row (as the live SELECT would if the client asked
/// for all statuses) to prove the UI never offers controls on it.
class _StaleRowsRepository extends InMemoryGroupRepository {
  _StaleRowsRepository(this.stale) : super(currentUser: 'u-me');
  final GroupInvitation stale;
  @override
  Future<List<GroupInvitation>> myInvitations() async => [stale];
}
