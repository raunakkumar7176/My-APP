// G5.2 — pending join lifecycle on the verified contracts:
//   fn_join_group(text) → uuid (member/joined) | NULL (restricted → request)
//   group_join_requests: own rows readable; pending|approved|declined.
// A pending request is never membership and never opens a hub.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/group_join_request.dart';
import 'package:my_praperation/features/group/data/group_repository.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/screens/group_list_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_list_controller.dart';
import 'package:my_praperation/features/group/widgets/join_group_sheet.dart';

import 'fakes.dart';

InMemoryGroupRepository _repo() => InMemoryGroupRepository(currentUser: 'u-me')
  ..seed(
    id: 'g-open',
    ownerId: 'u-o1',
    privacy: 'public',
    inviteCode: 'OPEN0001',
  )
  ..seed(
    id: 'g-locked',
    name: 'Locked',
    ownerId: 'u-o2',
    privacy: 'restricted',
    inviteCode: 'LOCK0001',
  );

void main() {
  group('GroupJoinRequest', () {
    test('J: parses exactly the live columns; extra keys are ignored', () {
      final r = GroupJoinRequest.fromJson({
        'id': 'r-1',
        'group_id': 'g-1',
        'user_id': 'u-1',
        'status': 'pending',
        'created_at': '2026-09-10T10:00:00Z',
        'expires_at': 'never', // does not exist live; must be ignored
      });
      expect(r.isPending, isTrue);
      expect(r.toJson().keys, {
        'id',
        'group_id',
        'user_id',
        'status',
        'created_at',
      });
      expect(
        GroupJoinRequest.fromJson(r.toJson()..['status'] = 'approved')
            .isApproved,
        isTrue,
      );
      expect(
        GroupJoinRequest.fromJson(r.toJson()..['status'] = 'declined')
            .isDeclined,
        isTrue,
      );
    });

    test('K: invite_code never enters Group payloads', () {
      final g = Group.fromJson({
        'id': 'g',
        'name': 'n',
        'owner_id': 'o',
        'created_at': '2026-09-10T10:00:00Z',
        'invite_code': 'LEAK',
      });
      expect(g.toJson().containsKey('invite_code'), isFalse);
    });
  });

  group('GroupListController join lifecycle', () {
    test(
      'A/G: id returned → joined; repeat join idempotent; no request read',
      () async {
        final repo = _repo();
        final c = GroupListController(repository: repo);
        await c.load();
        final first = await c.joinByCode('open0001');
        expect(first, isA<JoinedGroup>());
        expect(c.groups.map((g) => g.id), contains('g-open'));
        final again = await c.joinByCode('OPEN0001');
        expect((again! as JoinedGroup).alreadyMember, isTrue);
        expect(c.hasPendingRequests, isFalse);
        expect(
          repo.requestReads.where((x) => x != 'mine:pending'),
          isEmpty,
          reason:
              'only the own-pending read runs, never a per-group or broad list',
        );
      },
    );

    test(
      'B/C: NULL → own pending rows re-read → pending state; no membership',
      () async {
        final repo = _repo();
        final c = GroupListController(repository: repo);
        await c.load();
        expect(repo.requestReads, ['mine:pending']);
        final outcome = await c.joinByCode('LOCK0001');
        expect(outcome, isA<JoinRequestFiled>());
        expect(repo.requestReads.last, 'mine:pending');
        expect(c.hasPendingRequests, isTrue);
        expect(c.pendingRequests.single.groupId, 'g-locked');
        expect(c.pendingRequests.single.isPending, isTrue);
        expect(
          c.groups.map((g) => g.id),
          isNot(contains('g-locked')),
          reason: 'a pending request is not membership',
        );
      },
    );

    test(
      'D: same code while pending is refused client-side; server not called',
      () async {
        final repo = _repo();
        final c = GroupListController(repository: repo);
        await c.load();
        await c.joinByCode('LOCK0001');
        final joinCalls = repo.calls.where((x) => x.startsWith('join')).length;
        expect(await c.joinByCode(' lock0001 '), isNull);
        expect(c.error, contains('already pending'));
        expect(repo.calls.where((x) => x.startsWith('join')).length, joinCalls);
      },
    );

    test('F: invalid code → mapped message; pending state untouched', () async {
      final repo = _repo();
      final c = GroupListController(repository: repo);
      await c.load();
      expect(await c.joinByCode('NOPE0000'), isNull);
      expect(c.error, contains('invite code'));
      expect(c.hasPendingRequests, isFalse);
    });

    test(
      'H: approved/declined externally → server decides; nothing fabricated',
      () async {
        final repo = _repo();
        final c = GroupListController(repository: repo);
        await c.load();
        await c.joinByCode('LOCK0001');
        expect(c.hasPendingRequests, isTrue);

        // Manager declines externally.
        repo.requestStatus['g-locked:u-me'] = 'declined';
        await c.refresh();
        expect(c.hasPendingRequests, isFalse);
        expect(c.groups.map((g) => g.id), isNot(contains('g-locked')));

        // Manager approves externally: only the membership row grants access.
        repo.requestStatus['g-locked:u-me'] = 'approved';
        repo.groups['g-locked']!.roles['u-me'] = 'member';
        await c.refresh();
        expect(c.hasPendingRequests, isFalse);
        expect(c.groups.map((g) => g.id), contains('g-locked'));
      },
    );

    test(
      'I: myJoinRequest reads the exact group id and the caller only',
      () async {
        final repo = _repo();
        repo.requestStatus['g-locked:u-me'] = 'pending';
        repo.requestStatus['g-locked:u-other'] = 'pending';
        final mine = await repo.myJoinRequest('g-locked');
        expect(mine!.userId, 'u-me');
        expect(repo.requestReads, ['mine:g-locked']);
        expect(await repo.myJoinRequest('g-open'), isNull);
        final pending = await repo.myPendingJoinRequests();
        expect(pending.every((r) => r.userId == 'u-me'), isTrue);
      },
    );

    test('pending-list read failure never hides the groups list', () async {
      final repo = _FailingPendingRepository();
      repo.seed(id: 'g-1', ownerId: 'u-me');
      final c = GroupListController(repository: repo);
      await c.load();
      expect(c.groups.single.id, 'g-1');
      expect(c.error, isNull);
      expect(c.hasPendingRequests, isFalse);
    });
  });

  group('Screens', () {
    testWidgets('E: pending request never opens the hub; sheet shows pending', (
      tester,
    ) async {
      final repo = _repo();
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
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('join_group_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite_code_field')),
        'LOCK0001',
      );
      await tester.tap(find.byKey(const Key('join_submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('join_request_filed')), findsOneWidget);
      expect(find.textContaining('Join request pending'), findsOneWidget);
      expect(pushed, isEmpty, reason: 'no hub navigation on a pending request');

      // Re-open the sheet: pending banner shown, duplicate submit refused.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending_requests_banner')), findsOneWidget);
      await tester.tap(find.byKey(const Key('join_group_action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('join_pending_banner')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('invite_code_field')),
        'LOCK0001',
      );
      await tester.tap(find.byKey(const Key('join_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('join_error')), findsOneWidget);
      expect(pushed, isEmpty);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('A: joined → hub opened (existing behaviour)', (tester) async {
      final repo = _repo();
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
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('join_group_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite_code_field')),
        'OPEN0001',
      );
      await tester.tap(find.byKey(const Key('join_submit')));
      await tester.pumpAndSettle();
      expect(pushed, ['g-open']);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('E: hub for a group with only a pending request is denied', (
      tester,
    ) async {
      final repo = _repo();
      repo.requestStatus['g-locked:u-me'] = 'pending';
      final hub = GroupHubController(
        groupId: 'g-locked',
        repository: repo,
        currentUserId: 'u-me',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GroupHubScreen(groupId: 'g-locked', controller: hub),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Group not available'), findsOneWidget);
      expect(find.text('Locked'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      hub.dispose();
    });

    testWidgets('sheet still shows the plain "request sent" copy when no own '
        'row is returned', (tester) async {
      final repo = _NoRowsPendingRepository()
        ..seed(
          id: 'g-locked',
          ownerId: 'u-o2',
          privacy: 'restricted',
          inviteCode: 'LOCK0001',
        );
      final c = GroupListController(repository: repo);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => JoinGroupSheet.show(ctx, controller: c),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await c.load();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite_code_field')),
        'LOCK0001',
      );
      await tester.tap(find.byKey(const Key('join_submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Request sent.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  // ── G5.7 — Withdraw own pending join request ──
  group('Withdraw join request', () {
    test('A: own pending request can be withdrawn', () async {
      final repo = _repo();
      final c = GroupListController(repository: repo);
      await c.load();
      await c.joinByCode('LOCK0001');
      expect(c.hasPendingRequests, isTrue);
      final request = c.pendingRequests.single;
      expect(request.isPending, isTrue);
      expect(await c.withdrawJoinRequest(request), isTrue);
      expect(c.hasPendingRequests, isFalse);
      expect(repo.calls, contains('withdraw:${request.id}'));
      // Server row is gone.
      expect(repo.requestStatus.containsKey('g-locked:u-me'), isFalse);
    });

    test('B: another user\'s request cannot be withdrawn', () async {
      final repo = _repo();
      repo.requestStatus['g-locked:u-other'] = 'pending';
      final otherId = repo.seedJoinRequest(
        groupId: 'g-locked',
        userId: 'u-other',
      );
      final c = GroupListController(repository: repo);
      await c.load();
      final other = GroupJoinRequest(
        id: otherId,
        groupId: 'g-locked',
        userId: 'u-other',
        status: 'pending',
        createdAt: DateTime(2026, 9, 10),
      );
      expect(await c.withdrawJoinRequest(other), isFalse);
      expect(c.error, isNotNull);
      // Server row untouched.
      expect(repo.requestStatus['g-locked:u-other'], 'pending');
    });

    test('C: approved request cannot be withdrawn', () async {
      final repo = _repo();
      repo.requestStatus['g-locked:u-me'] = 'approved';
      final c = GroupListController(repository: repo);
      await c.load();
      expect(c.hasPendingRequests, isFalse);
      final approved = GroupJoinRequest(
        id: 'r-approved',
        groupId: 'g-locked',
        userId: 'u-me',
        status: 'approved',
        createdAt: DateTime(2026, 9, 10),
      );
      expect(await c.withdrawJoinRequest(approved), isFalse);
      expect(c.error, contains('pending'));
    });

    test('D: declined request cannot be withdrawn', () async {
      final repo = _repo();
      repo.requestStatus['g-locked:u-me'] = 'declined';
      final c = GroupListController(repository: repo);
      await c.load();
      expect(c.hasPendingRequests, isFalse);
      final declined = GroupJoinRequest(
        id: 'r-declined',
        groupId: 'g-locked',
        userId: 'u-me',
        status: 'declined',
        createdAt: DateTime(2026, 9, 10),
      );
      expect(await c.withdrawJoinRequest(declined), isFalse);
      expect(c.error, contains('pending'));
    });

    test(
      'E: cross-group forged request id cannot affect another request',
      () async {
        final repo = _repo();
        // u-me has a pending request for g-locked.
        repo.seedJoinRequest(groupId: 'g-locked', userId: 'u-me');
        final c = GroupListController(repository: repo);
        await c.load();
        expect(c.hasPendingRequests, isTrue);
        // Try to withdraw with a forged id that doesn't exist.
        final forged = GroupJoinRequest(
          id: 'forged-id',
          groupId: 'g-locked',
          userId: 'u-me',
          status: 'pending',
          createdAt: DateTime(2026, 9, 10),
        );
        expect(await c.withdrawJoinRequest(forged), isFalse);
        expect(c.error, isNotNull);
        // Original request still exists.
        expect(c.hasPendingRequests, isTrue);
      },
    );

    test('F: successful withdrawal refreshes state', () async {
      final repo = _repo();
      final c = GroupListController(repository: repo);
      await c.load();
      await c.joinByCode('LOCK0001');
      expect(c.hasPendingRequests, isTrue);
      final request = c.pendingRequests.single;
      expect(await c.withdrawJoinRequest(request), isTrue);
      expect(c.hasPendingRequests, isFalse);
      expect(c.error, isNull);
    });

    test(
      'F2: failed withdrawal keeps the pending state; retry works',
      () async {
        final repo = _repo();
        final c = GroupListController(repository: repo);
        await c.load();
        await c.joinByCode('LOCK0001');
        final request = c.pendingRequests.single;
        repo.failNextWith = const DataError(message: 'Network error.');
        expect(await c.withdrawJoinRequest(request), isFalse);
        expect(c.error, 'Network error.');
        expect(c.hasPendingRequests, isTrue, reason: 're-read: still pending');
        expect(repo.requestStatus['g-locked:u-me'], 'pending');
        expect(await c.withdrawJoinRequest(request), isTrue, reason: 'retry');
        expect(c.hasPendingRequests, isFalse);
      },
    );

    test('F3: after withdrawal the same code can be applied again', () async {
      final repo = _repo();
      final c = GroupListController(repository: repo);
      await c.load();
      await c.joinByCode('LOCK0001');
      expect(c.isCodePending('LOCK0001'), isTrue);
      await c.withdrawJoinRequest(c.pendingRequests.single);
      expect(c.isCodePending('LOCK0001'), isFalse);
      expect(await c.joinByCode('LOCK0001'), isA<JoinRequestFiled>());
      expect(c.hasPendingRequests, isTrue);
    });

    test('G: single-flight protection', () async {
      final repo = _SlowWithdrawRepository()
        ..seed(
          id: 'g-locked',
          name: 'Locked',
          ownerId: 'u-o2',
          privacy: 'restricted',
          inviteCode: 'LOCK0001',
        );
      final c = GroupListController(repository: repo);
      await c.load();
      await c.joinByCode('LOCK0001');
      expect(c.hasPendingRequests, isTrue);
      final request = c.pendingRequests.single;
      final a = c.withdrawJoinRequest(request);
      final b = c.withdrawJoinRequest(request);
      expect(await b, isFalse, reason: 'second call blocked by single-flight');
      expect(await a, isTrue);
      expect(
        repo.calls.where((x) => x.startsWith('withdraw')).length,
        1,
        reason: 'only one server call',
      );
    });

    testWidgets('H: confirmation required — UI shows dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _repo();
      final c = GroupListController(repository: repo);
      await c.load();
      await c.joinByCode('LOCK0001');
      await tester.pumpWidget(
        MaterialApp(home: GroupListScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('withdraw_request_${c.pendingRequests.single.id}')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(Key('withdraw_request_${c.pendingRequests.single.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm_withdraw')), findsOneWidget);
      expect(c.hasPendingRequests, isTrue, reason: 'not withdrawn yet');
      await tester.tap(find.byKey(const Key('confirm_withdraw')));
      await tester.pumpAndSettle();
      expect(c.hasPendingRequests, isFalse);
      expect(find.text('Join request withdrawn.'), findsOneWidget);
    });

    test('I: permission/auth failure handled', () async {
      final repo = _repo();
      final c = GroupListController(repository: repo);
      await c.load();
      await c.joinByCode('LOCK0001');
      expect(c.hasPendingRequests, isTrue);
      final request = c.pendingRequests.single;
      repo.failNextWith = const DataError(message: 'NOT_AUTHORIZED');
      expect(await c.withdrawJoinRequest(request), isFalse);
      expect(c.error, isNotNull);
      // Pending state re-read from server.
      expect(c.hasPendingRequests, isTrue);
    });

    test('J: operation never touches group_members', () async {
      final repo = _repo();
      final c = GroupListController(repository: repo);
      await c.load();
      await c.joinByCode('LOCK0001');
      final membersBefore = Map.of(repo.groups['g-locked']!.roles);
      final request = c.pendingRequests.single;
      await c.withdrawJoinRequest(request);
      expect(repo.groups['g-locked']!.roles, membersBefore);
      expect(repo.calls.where((x) => x.startsWith('remove')), isEmpty);
    });

    test('K: operation never touches group_invitations', () async {
      final repo = _repo();
      repo.seedInvitation(
        id: 'i-test',
        groupId: 'g-locked',
        inviterId: 'u-o2',
        inviteeId: 'u-me',
      );
      final c = GroupListController(repository: repo);
      await c.load();
      await c.joinByCode('LOCK0001');
      final request = c.pendingRequests.single;
      await c.withdrawJoinRequest(request);
      expect(repo.invitations.any((i) => i.id == 'i-test'), isTrue);
      expect(
        repo.calls.where((x) => x.startsWith('cancelInvitation')),
        isEmpty,
      );
    });
  });
}

class _FailingPendingRepository extends InMemoryGroupRepository {
  _FailingPendingRepository() : super(currentUser: 'u-me');
  @override
  Future<List<GroupJoinRequest>> myPendingJoinRequests() async =>
      throw Exception('boom');
}

/// Restricted join files a request server-side but the read returns no rows
/// (e.g. replication lag): the client must still show a request-sent state.
class _NoRowsPendingRepository extends InMemoryGroupRepository {
  _NoRowsPendingRepository() : super(currentUser: 'u-me');
  @override
  Future<List<GroupJoinRequest>> myPendingJoinRequests() async => const [];
}

class _SlowWithdrawRepository extends InMemoryGroupRepository {
  _SlowWithdrawRepository() : super(currentUser: 'u-me');
  @override
  Future<void> withdrawJoinRequest(String requestId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.withdrawJoinRequest(requestId);
  }
}
