// G5.5 — outgoing invitation management on the verified contracts:
//   group_invitations SELECT (invitee ∨ inviter ∨ member), DELETE (inviter ∨
//   MANAGE_MEMBERS), INSERT (inviter = uid ∧ MANAGE_MEMBERS), UNIQUE(group,
//   invitee), statuses pending|accepted|declined|expired, no expiry column.
// No RPC, no profile lookup, no student-code resolver (that is G5.6).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group_invitation.dart';
import 'package:my_praperation/features/group/data/group_repository.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

/// g-1 owned by u-me with one invitation per status; g-2 owned by u-other
/// with its own pending invitation.
InMemoryGroupRepository _repo() {
  final repo = InMemoryGroupRepository(currentUser: 'u-me')
    ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me')
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  repo.seedInvitation(
    id: 'i-pend',
    groupId: 'g-1',
    inviterId: 'u-me',
    inviteeId: 'u-a',
  );
  repo.seedInvitation(
    id: 'i-acc',
    groupId: 'g-1',
    inviterId: 'u-me',
    inviteeId: 'u-b',
    status: 'accepted',
  );
  repo.seedInvitation(
    id: 'i-dec',
    groupId: 'g-1',
    inviterId: 'u-me',
    inviteeId: 'u-c',
    status: 'declined',
  );
  repo.seedInvitation(
    id: 'i-exp',
    groupId: 'g-1',
    inviterId: 'u-me',
    inviteeId: 'u-d',
    status: 'expired',
  );
  repo.seedInvitation(
    id: 'i-g2',
    groupId: 'g-2',
    inviterId: 'u-other',
    inviteeId: 'u-z',
  );
  return repo;
}

void main() {
  group('Load (permission gate)', () {
    test('A/C: manager loads exact-group rows, all statuses', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(c.canManageMembers, isTrue);
      expect(c.outgoingInvitations.map((i) => i.id).toSet(), {
        'i-pend',
        'i-acc',
        'i-dec',
        'i-exp',
      });
      expect(c.outgoingInvitations.every((i) => i.groupId == 'g-1'), isTrue);
      expect(repo.invitationReads, ['group:g-1']);
    });

    test('B: plain member never triggers groupInvitations', () async {
      final repo = _repo();
      repo.groups['g-1']!.roles['u-member'] = 'member';
      repo.currentUser = 'u-member';
      final c = _hub(repo, user: 'u-member');
      await c.load();
      expect(c.canManageMembers, isFalse);
      expect(c.outgoingInvitations, isEmpty);
      expect(repo.invitationReads, isEmpty);
    });

    test('D: empty', () async {
      final repo = InMemoryGroupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await c.load();
      expect(c.outgoingInvitations, isEmpty);
      expect(c.outgoingError, isNull);
    });

    test('F: read failure isolated; retry recovers', () async {
      final repo = _FailingOutgoingRepository();
      repo.seed(id: 'g-1', ownerId: 'u-me');
      repo.seedInvitation(
        id: 'i-1',
        groupId: 'g-1',
        inviterId: 'u-me',
        inviteeId: 'u-a',
      );
      final c = _hub(repo);
      await c.load();
      expect(c.group, isNotNull);
      expect(c.outgoingError, isNotNull);
      repo.failReads = false;
      await c.retryOutgoingInvitations();
      expect(c.outgoingError, isNull);
      expect(c.outgoingInvitations.single.id, 'i-1');
    });
  });

  group('Cancel', () {
    test('K/M: exact-id delete; list re-read from the server', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      final pend = c.outgoingInvitations.firstWhere((i) => i.id == 'i-pend');
      expect(await c.cancelInvitation(pend), isTrue);
      expect(repo.calls, contains('cancelInvitation:i-pend'));
      expect(c.outgoingInvitations.any((i) => i.id == 'i-pend'), isFalse);
      expect(c.outgoingInvitations.length, 3);
      // Nothing else touched.
      expect(repo.groups['g-1']!.roles.length, 1);
      expect(repo.requestStatus, isEmpty);
    });

    test('L: single-flight per invitation', () async {
      final repo = _SlowCancelRepository();
      repo.seed(id: 'g-1', ownerId: 'u-me');
      repo.seedInvitation(
        id: 'i-1',
        groupId: 'g-1',
        inviterId: 'u-me',
        inviteeId: 'u-a',
      );
      final c = _hub(repo);
      await c.load();
      final inv = c.outgoingInvitations.single;
      final first = c.cancelInvitation(inv);
      final dup = c.cancelInvitation(inv);
      expect(await dup, isFalse);
      expect(await first, isTrue);
      expect(repo.calls.where((x) => x == 'cancelInvitation:i-1').length, 1);
    });

    test(
      'N: failed cancel → mapped error, server re-read, nothing fabricated',
      () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final pend = c.outgoingInvitations.firstWhere((i) => i.id == 'i-pend');
        repo.failNextWith = const DataError(message: 'Network error.');
        expect(await c.cancelInvitation(pend), isFalse);
        expect(c.error, 'Network error.');
        expect(c.outgoingInvitations.any((i) => i.id == 'i-pend'), isTrue);
        expect(c.actingInvitationId, isNull);
      },
    );

    test('H/J: accepted / expired cannot be cancelled', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      for (final id in ['i-acc', 'i-exp']) {
        final inv = c.outgoingInvitations.firstWhere((i) => i.id == id);
        expect(await c.cancelInvitation(inv), isFalse);
        expect(c.error, contains('pending'));
      }
      expect(
        repo.calls.where((x) => x.startsWith('cancelInvitation')),
        isEmpty,
      );
    });

    test('T: cross-group cancel is rejected by the server boundary', () async {
      final repo = _repo();
      final c = _hub(repo); // manages g-1 only
      await c.load();
      // Forged row from g-2 (never returned by RLS to this manager).
      final foreign = GroupInvitation(
        id: 'i-g2',
        groupId: 'g-1', // lying about the group
        inviterId: 'u-other',
        inviteeId: 'u-z',
        status: 'pending',
        createdAt: _epoch,
      );
      expect(await c.cancelInvitation(foreign), isFalse);
      expect(c.error, contains('could not be cancelled'));
      expect(repo.invitations.any((i) => i.id == 'i-g2'), isTrue);
      expect(
        repo.calls.last,
        'cancelInvitation:i-g2',
        reason: 'only the invitation id is sent',
      );
    });
  });

  group('Re-invite', () {
    test('I/P: declined → old row deleted, new pending row inserted by the '
        'current manager (UNIQUE respected)', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      final dec = c.outgoingInvitations.firstWhere((i) => i.id == 'i-dec');
      expect(c.canReinvite(dec), isTrue);
      expect(await c.reinvite(dec), isTrue);
      expect(
        repo.calls,
        containsAllInOrder([
          'cancelInvitation:i-dec',
          'insertInvitation:g-1:u-c',
        ]),
      );
      final fresh = c.outgoingInvitations.where((i) => i.inviteeId == 'u-c');
      expect(fresh.length, 1, reason: 'exactly one row per (group, invitee)');
      expect(fresh.single.isPending, isTrue);
      expect(fresh.single.inviterId, 'u-me');
      expect(fresh.single.id, isNot('i-dec'));
    });

    test(
      'O: never for pending / accepted / expired, nor for a member',
      () async {
        final repo = _repo();
        repo.groups['g-1']!.roles['u-c'] = 'member'; // declined invitee joined
        final c = _hub(repo);
        await c.load();
        for (final id in ['i-pend', 'i-acc', 'i-exp', 'i-dec']) {
          final inv = c.outgoingInvitations.firstWhere((i) => i.id == id);
          expect(c.canReinvite(inv), isFalse);
          expect(await c.reinvite(inv), isFalse);
        }
        expect(
          repo.calls.where((x) => x.startsWith('insertInvitation')),
          isEmpty,
        );
        expect(
          repo.calls.where((x) => x.startsWith('cancelInvitation')),
          isEmpty,
        );
      },
    );

    test(
      'Q: INSERT failure after DELETE is reported explicitly, never silent',
      () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final dec = c.outgoingInvitations.firstWhere((i) => i.id == 'i-dec');
        repo.failInsertWith = const DataError(message: 'Network error.');
        expect(await c.reinvite(dec), isFalse);
        expect(c.error, startsWith(reinviteIncompletePrefix));
        expect(c.error, contains('Network error.'));
        expect(
          c.outgoingInvitations.any((i) => i.inviteeId == 'u-c'),
          isFalse,
          reason: 'declined row gone, nothing pending — and the user was told',
        );
      },
    );

    test(
      'DELETE failure leaves the declined row and inserts nothing',
      () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final dec = c.outgoingInvitations.firstWhere((i) => i.id == 'i-dec');
        repo.failNextWith = const DataError(message: 'Network error.');
        expect(await c.reinvite(dec), isFalse);
        expect(c.error, 'Network error.');
        expect(c.outgoingInvitations.any((i) => i.id == 'i-dec'), isTrue);
        expect(
          repo.calls.where((x) => x.startsWith('insertInvitation')),
          isEmpty,
        );
      },
    );
  });

  group('Scope guards', () {
    test(
      'R/S/V: no resolver, no profile query, no send-invitation surface',
      () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        expect(repo.calls.where((x) => x.contains('profile')), isEmpty);
        expect(repo.calls.where((x) => x.startsWith('members')).length, 1);
        // The only INSERT path is the re-invite of an existing declined row.
        expect(
          repo.calls.where((x) => x.startsWith('insertInvitation')),
          isEmpty,
        );
      },
    );
  });

  group('Hub screen', () {
    Future<GroupHubController> pump(
      WidgetTester tester,
      InMemoryGroupRepository repo, {
      String user = 'u-me',
    }) async {
      tester.view.physicalSize = const Size(800, 2200);
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

    testWidgets('G/H/I/J: actions per status; statuses shown verbatim', (
      tester,
    ) async {
      final c = await pump(tester, _repo());
      expect(find.byKey(const Key('outgoing_invitations')), findsOneWidget);
      expect(find.byKey(const Key('outgoing_pending_count')), findsOneWidget);
      expect(find.byKey(const Key('cancel_invitation_i-pend')), findsOneWidget);
      expect(find.byKey(const Key('cancel_invitation_i-acc')), findsNothing);
      expect(find.byKey(const Key('reinvite_i-acc')), findsNothing);
      expect(find.byKey(const Key('reinvite_i-dec')), findsOneWidget);
      expect(find.byKey(const Key('cancel_invitation_i-exp')), findsNothing);
      expect(find.byKey(const Key('reinvite_i-exp')), findsNothing);
      expect(find.text('expired'), findsOneWidget);
      expect(
        find.textContaining('xpires'),
        findsNothing,
        reason: 'no expiry date is ever computed or shown',
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('B: member sees no outgoing section', (tester) async {
      final repo = _repo();
      repo.groups['g-1']!.roles['u-member'] = 'member';
      repo.currentUser = 'u-member';
      final c = await pump(tester, repo, user: 'u-member');
      expect(find.byKey(const Key('outgoing_invitations')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('E/F: loading then error + retry', (tester) async {
      final repo = _FailingOutgoingRepository();
      repo.seed(id: 'g-1', ownerId: 'u-me');
      repo.seedInvitation(
        id: 'i-1',
        groupId: 'g-1',
        inviterId: 'u-me',
        inviteeId: 'u-a',
      );
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('outgoing_error')), findsOneWidget);
      repo.failReads = false;
      await tester.tap(find.byKey(const Key('outgoing_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cancel_invitation_i-1')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets(
      'K: cancel → confirm → row gone; re-invite → confirm → new row',
      (tester) async {
        final repo = _repo();
        final c = await pump(tester, repo);
        await tester.tap(find.byKey(const Key('cancel_invitation_i-pend')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_cancel_invitation')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('outgoing_i-pend')), findsNothing);

        await tester.tap(find.byKey(const Key('reinvite_i-dec')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_reinvite')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('outgoing_i-dec')), findsNothing);
        expect(find.byKey(const Key('outgoing_pending_count')), findsOneWidget);
        final fresh = repo.invitations.where((i) => i.inviteeId == 'u-c');
        expect(fresh.single.isPending, isTrue);
        expect(
          find.byKey(Key('cancel_invitation_${fresh.single.id}')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  });
}

final _epoch = DateTime(2026, 9, 1);

class _FailingOutgoingRepository extends InMemoryGroupRepository {
  _FailingOutgoingRepository() : super(currentUser: 'u-me');
  bool failReads = true;
  @override
  Future<List<GroupInvitation>> groupInvitations(String groupId) async {
    if (failReads) throw const DataError(message: 'Network error.');
    return super.groupInvitations(groupId);
  }
}

class _SlowCancelRepository extends InMemoryGroupRepository {
  _SlowCancelRepository() : super(currentUser: 'u-me');
  @override
  Future<void> cancelInvitation(String invitationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.cancelInvitation(invitationId);
  }
}
