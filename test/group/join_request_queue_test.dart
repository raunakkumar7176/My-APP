// G5.3 — manager join-request queue on the verified contracts:
//   group_join_requests SELECT (own row OR MANAGE_MEMBERS), no requester DELETE
//   fn_approve_group_join_request(p_request_id, p_approve) → derives the group
//   from the row and checks MANAGE_MEMBERS there.
// Only the request id is ever sent; the client never authorizes by group id.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group_join_request.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

/// g-1 owned by u-me (MANAGE_MEMBERS via owner bypass), one pending request
/// from u-req; g-2 owned by someone else with its own pending request.
InMemoryGroupRepository _repo() {
  final repo = InMemoryGroupRepository(currentUser: 'u-me')
    ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me', privacy: 'restricted')
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other', privacy: 'restricted');
  repo.seedJoinRequest(groupId: 'g-1', userId: 'u-req');
  repo.seedJoinRequest(groupId: 'g-2', userId: 'u-req2');
  return repo;
}

void main() {
  group('Queue load (permission gate)', () {
    test('A/C: MANAGE_MEMBERS loads exact-group pending rows only', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(c.canManageMembers, isTrue);
      expect(c.joinRequests.map((r) => r.groupId), ['g-1']);
      expect(c.joinRequests.single.userId, 'u-req');
      expect(c.pendingRequestCount, 1);
      expect(repo.requestReads, ['group:g-1']);
    });

    test('B: a plain member never queries the queue', () async {
      final repo = _repo();
      repo.groups['g-1']!.roles['u-member'] = 'member';
      repo.currentUser = 'u-member';
      final c = _hub(repo, user: 'u-member');
      await c.load();
      expect(c.canManageMembers, isFalse);
      expect(c.joinRequests, isEmpty);
      expect(repo.requestReads, isEmpty);
      expect(
        await c.decideJoinRequest(
          GroupJoinRequest(
            id: 'r-1',
            groupId: 'g-1',
            userId: 'u-req',
            status: 'pending',
            createdAt: DateTime(2026),
          ),
          approve: true,
        ),
        isFalse,
      );
      expect(c.error, contains('permission'));
      expect(repo.calls.where((x) => x.startsWith('decide')), isEmpty);
    });

    test('C: leader (seeded MANAGE_MEMBERS) also sees the queue', () async {
      final repo = _repo();
      repo.groups['g-1']!.roles['u-lead'] = 'leader';
      repo.currentUser = 'u-lead';
      final c = _hub(repo, user: 'u-lead');
      await c.load();
      expect(c.canManageMembers, isTrue);
      expect(c.joinRequests.length, 1);
    });

    test('D: empty queue', () async {
      final repo = InMemoryGroupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await c.load();
      expect(c.joinRequests, isEmpty);
      expect(c.joinRequestsError, isNull);
    });

    test('F: queue read failure is isolated; retry recovers', () async {
      final repo = _FailingQueueRepository();
      repo.seed(id: 'g-1', ownerId: 'u-me');
      repo.seedJoinRequest(groupId: 'g-1', userId: 'u-req');
      final c = _hub(repo);
      await c.load();
      expect(c.group, isNotNull, reason: 'hub still usable');
      expect(c.joinRequestsError, isNotNull);
      repo.failReads = false;
      await c.retryJoinRequests();
      expect(c.joinRequestsError, isNull);
      expect(c.joinRequests.length, 1);
    });
  });

  group('Decide', () {
    test('H/K/N: approve sends exact id + true; hub reloads; membership from '
        'the server row, count re-read', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(c.memberCount, 1);
      final r = c.joinRequests.single;
      expect(await c.decideJoinRequest(r, approve: true), isTrue);
      expect(repo.calls, contains('decide:${r.id}:true'));
      expect(c.joinRequests, isEmpty);
      expect(c.memberCount, 2);
      expect(c.members.any((m) => m.userId == 'u-req'), isTrue);
      expect(
        repo.groups['g-1']!.roles['u-req'],
        'member',
        reason: 'inserted by the function, not the client',
      );
      expect(repo.requestStatus['g-1:u-req'], 'approved');
    });

    test(
      'I/L/O: decline sends exact id + false; queue refreshes; no membership',
      () async {
        final repo = _repo();
        repo.groups['g-1']!.roles['u-existing'] = 'member';
        final c = _hub(repo);
        await c.load();
        final r = c.joinRequests.single;
        expect(await c.decideJoinRequest(r, approve: false), isTrue);
        expect(repo.calls, contains('decide:${r.id}:false'));
        expect(c.joinRequests, isEmpty);
        expect(repo.groups['g-1']!.roles.containsKey('u-req'), isFalse);
        expect(
          repo.groups['g-1']!.roles['u-existing'],
          'member',
          reason: 'decline never removes an existing member',
        );
        expect(repo.requestStatus['g-1:u-req'], 'declined');
      },
    );

    test('J: each request is single-flight', () async {
      final repo = _SlowDecideRepository();
      repo.seed(id: 'g-1', ownerId: 'u-me', privacy: 'restricted');
      repo.seedJoinRequest(groupId: 'g-1', userId: 'u-a');
      repo.seedJoinRequest(groupId: 'g-1', userId: 'u-b');
      final c = _hub(repo);
      await c.load();
      final a = c.joinRequests[0];
      final first = c.decideJoinRequest(a, approve: true);
      final dup = c.decideJoinRequest(a, approve: true);
      expect(await dup, isFalse);
      expect(await first, isTrue);
      expect(repo.calls.where((x) => x.startsWith('decide:${a.id}')).length, 1);
    });

    test(
      'M: stale/failed mutation → mapped error and server re-read',
      () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final r = c.joinRequests.single;
        // Another manager decided it meanwhile.
        repo.requestStatus['g-1:u-req'] = 'declined';
        repo.failNextWith = const DataError(message: 'Network error.');
        expect(await c.decideJoinRequest(r, approve: true), isFalse);
        expect(c.error, 'Network error.');
        expect(c.joinRequests, isEmpty, reason: 're-read from the server');
        expect(repo.groups['g-1']!.roles.containsKey('u-req'), isFalse);
        expect(c.actingRequestId, isNull);
      },
    );

    test('R: manager of A cannot decide a request of B — server derives the '
        'group from the row; only the request id is sent', () async {
      final repo = _repo();
      final c = _hub(repo); // manages g-1 only
      await c.load();
      // Client never sees g-2's row (RLS) — simulate a forged/stale id.
      final foreign = GroupJoinRequest(
        id: repo.seedJoinRequest(groupId: 'g-2', userId: 'u-req2'),
        groupId: 'g-1', // lying about the group changes nothing
        userId: 'u-req2',
        status: 'pending',
        createdAt: DateTime(2026),
      );
      expect(await c.decideJoinRequest(foreign, approve: true), isFalse);
      expect(c.error, contains('permission'));
      expect(
        repo.calls.last,
        'decide:${foreign.id}:true',
        reason: 'request id only — no group id in the call',
      );
      expect(repo.groups['g-2']!.roles.containsKey('u-req2'), isFalse);
      expect(repo.requestStatus['g-2:u-req2'], 'pending');
    });

    test(
      'P/Q: requester is not treated as a member and no profile is fetched',
      () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        expect(c.members.any((m) => m.userId == 'u-req'), isFalse);
        expect(repo.calls.where((x) => x.startsWith('members')).length, 1);
        // The model carries no identity fields at all.
        expect(c.joinRequests.single.toJson().keys, {
          'id',
          'group_id',
          'user_id',
          'status',
          'created_at',
        });
      },
    );
  });

  group('Hub screen', () {
    Future<GroupHubController> pump(
      WidgetTester tester,
      InMemoryGroupRepository repo, {
      String user = 'u-me',
    }) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _hub(repo, user: user);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupHubScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets(
      'G/E: manager sees badge, item, approve/decline; loading first',
      (tester) async {
        final repo = _SlowQueueRepository();
        repo.seed(id: 'g-1', ownerId: 'u-me', privacy: 'restricted');
        final id = repo.seedJoinRequest(groupId: 'g-1', userId: 'u-req');
        tester.view.physicalSize = const Size(800, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = _hub(repo);
        await tester.pumpWidget(
          MaterialApp(
            home: GroupHubScreen(groupId: 'g-1', controller: c),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('join_request_queue')), findsOneWidget);
        expect(find.byKey(const Key('join_request_badge')), findsOneWidget);
        expect(find.byKey(Key('approve_request_$id')), findsOneWidget);
        expect(find.byKey(Key('decline_request_$id')), findsOneWidget);
        expect(find.text('Join request'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('B: member sees no queue at all', (tester) async {
      final repo = _repo();
      repo.groups['g-1']!.roles['u-member'] = 'member';
      repo.currentUser = 'u-member';
      final c = await pump(tester, repo, user: 'u-member');
      expect(find.byKey(const Key('join_request_queue')), findsNothing);
      expect(repo.requestReads, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('K: approve → confirm → item gone, member count updated', (
      tester,
    ) async {
      final repo = _repo();
      final id = repo.seedJoinRequest(groupId: 'g-1', userId: 'u-req');
      final c = await pump(tester, repo);
      expect(find.text('Members · 1'), findsOneWidget);
      await tester.tap(find.byKey(Key('approve_request_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_approve_request')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('join_request_$id')), findsNothing);
      expect(find.byKey(const Key('join_requests_empty')), findsOneWidget);
      expect(find.text('Members · 2'), findsOneWidget);
      expect(find.byKey(const Key('member_u-req')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets(
      'L/M: decline → confirm → gone; failure shows error + re-read',
      (tester) async {
        final repo = _repo();
        final id = repo.seedJoinRequest(groupId: 'g-1', userId: 'u-req');
        final c = await pump(tester, repo);
        repo.failNextWith = const DataError(message: 'Network error.');
        await tester.tap(find.byKey(Key('decline_request_$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_decline_request')));
        await tester.pumpAndSettle();
        expect(find.text('Network error.'), findsWidgets);
        expect(
          find.byKey(Key('join_request_$id')),
          findsOneWidget,
          reason: 'still pending server-side, re-read',
        );

        await tester.tap(find.byKey(Key('decline_request_$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_decline_request')));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('join_request_$id')), findsNothing);
        expect(find.text('Members · 1'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('F: read failure shows Retry', (tester) async {
      final repo = _FailingQueueRepository();
      repo.seed(id: 'g-1', ownerId: 'u-me');
      final id = repo.seedJoinRequest(groupId: 'g-1', userId: 'u-req');
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('join_requests_error')), findsOneWidget);
      repo.failReads = false;
      await tester.tap(find.byKey(const Key('join_requests_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('approve_request_$id')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

class _FailingQueueRepository extends InMemoryGroupRepository {
  _FailingQueueRepository() : super(currentUser: 'u-me');
  bool failReads = true;
  @override
  Future<List<GroupJoinRequest>> pendingJoinRequests(String groupId) async {
    if (failReads) throw const DataError(message: 'Network error.');
    return super.pendingJoinRequests(groupId);
  }
}

class _SlowDecideRepository extends InMemoryGroupRepository {
  _SlowDecideRepository() : super(currentUser: 'u-me');
  @override
  Future<void> decideJoinRequest(
    String requestId, {
    required bool approve,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.decideJoinRequest(requestId, approve: approve);
  }
}

class _SlowQueueRepository extends InMemoryGroupRepository {
  _SlowQueueRepository() : super(currentUser: 'u-me');
  @override
  Future<List<GroupJoinRequest>> pendingJoinRequests(String groupId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.pendingJoinRequests(groupId);
  }
}
