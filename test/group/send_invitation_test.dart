// G5.6 — send invitation to an existing registered user by student code.
//   lookup: rpc_find_profile_by_student_code(p_code) → at most one row of
//           id, full_name, avatar_url, student_code (PROPOSED — see the
//           migration file; the fake mirrors that exact contract)
//   send:   INSERT group_invitations {group_id, invitee_id}, inviter = uid,
//           policy inviter_id = uid AND MANAGE_MEMBERS, UNIQUE(group, invitee)
// Nothing here touches group_members or group_join_requests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/profile_match.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/invite_member_controller.dart';
import 'package:my_praperation/features/group/widgets/invite_member_sheet.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

InMemoryGroupRepository _repo() {
  final repo = InMemoryGroupRepository(currentUser: 'u-me')
    ..seed(
      id: 'g-1',
      name: 'Physics',
      ownerId: 'u-me',
      members: {'u-mem': 'member'},
    )
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  repo.registry.addAll({
    'MP-AAAAA': 'u-alice',
    'MP-MEMBR': 'u-mem',
    'MP-PENDG': 'u-pend',
    'MP-DECLN': 'u-dec',
    'MP-EXPRD': 'u-exp',
    'MP-ACCPT': 'u-acc',
    'MP-MYSLF': 'u-me',
  });
  repo.profileNames.addAll({'u-alice': 'Alice Roy', 'u-mem': 'Mem Ber'});
  repo.seedInvitation(
    id: 'i-p',
    groupId: 'g-1',
    inviterId: 'u-me',
    inviteeId: 'u-pend',
  );
  repo.seedInvitation(
    id: 'i-d',
    groupId: 'g-1',
    inviterId: 'u-me',
    inviteeId: 'u-dec',
    status: 'declined',
  );
  repo.seedInvitation(
    id: 'i-e',
    groupId: 'g-1',
    inviterId: 'u-me',
    inviteeId: 'u-exp',
    status: 'expired',
  );
  repo.seedInvitation(
    id: 'i-a',
    groupId: 'g-1',
    inviterId: 'u-me',
    inviteeId: 'u-acc',
    status: 'accepted',
  );
  return repo;
}

Future<InviteMemberController> _invite(
  InMemoryGroupRepository repo, {
  String user = 'u-me',
}) async {
  final hub = _hub(repo, user: user);
  await hub.load();
  final c = InviteMemberController(
    groupId: 'g-1',
    currentUserId: user,
    members: hub.members,
    invitations: hub.outgoingInvitations,
    repository: repo,
  );
  hub.dispose();
  return c;
}

void main() {
  group('Lookup', () {
    test(
      'C/D/Q: trimmed + upper-cased exact lookup; only identity fields',
      () async {
        final repo = _repo();
        final c = await _invite(repo);
        await c.search('  mp-aaaaa ');
        expect(repo.lookups, ['MP-AAAAA']);
        final m = c.match!;
        expect(m.id, 'u-alice');
        expect(m.fullName, 'Alice Roy');
        expect(m.studentCode, 'MP-AAAAA');
        expect(m.toJson().keys, {
          'id',
          'full_name',
          'student_code',
          'avatar_url',
        });
        expect(c.stateFor(m), InviteeState.canInvite);
        expect(c.error, isNull);
        c.dispose();
      },
    );

    test(
      'E: unknown code → generic not-found; blank never hits the server',
      () async {
        final repo = _repo();
        final c = await _invite(repo);
        await c.search('MP-NOPE0');
        expect(c.match, isNull);
        expect(c.hasSearched, isTrue);
        expect(c.error, contains('No user found'));
        await c.search('   ');
        expect(repo.lookups, [
          'MP-NOPE0',
        ], reason: 'blank rejected client-side');
        c.dispose();
      },
    );

    test('lookup failure maps and clears on the next search', () async {
      final repo = _repo();
      final c = await _invite(repo);
      repo.failNextWith = const DataError(message: 'Network error.');
      await c.search('MP-AAAAA');
      expect(c.error, 'Network error.');
      expect(c.match, isNull);
      await c.search('MP-AAAAA');
      expect(c.error, isNull);
      expect(c.match, isNotNull);
      c.dispose();
    });

    test('search is single-flight', () async {
      final repo = _SlowLookupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      repo.registry['MP-AAAAA'] = 'u-alice';
      final c = await _invite(repo);
      final a = c.search('MP-AAAAA');
      final b = c.search('MP-AAAAA');
      await Future.wait([a, b]);
      expect(repo.lookups.length, 1);
      c.dispose();
    });
  });

  group('Send', () {
    test('F/G/H/J: send inserts {group, invitee} with the session inviter; '
        'pending row appears on refresh', () async {
      final repo = _repo();
      final c = await _invite(repo);
      await c.search('MP-AAAAA');
      expect(await c.send(), isTrue);
      expect(c.sent, isTrue);
      expect(repo.calls, contains('insertInvitation:g-1:u-alice'));
      final row = repo.invitations.firstWhere((i) => i.inviteeId == 'u-alice');
      expect(row.groupId, 'g-1');
      expect(row.inviterId, 'u-me');
      expect(row.isPending, isTrue);
      // Hub refresh shows it as an outgoing invitation.
      final hub = _hub(repo);
      await hub.load();
      expect(
        hub.outgoingInvitations.any((i) => i.inviteeId == 'u-alice'),
        isTrue,
      );
      hub.dispose();
      c.dispose();
    });

    test('I: send is single-flight', () async {
      final repo = _SlowSendRepository()..seed(id: 'g-1', ownerId: 'u-me');
      repo.registry['MP-AAAAA'] = 'u-alice';
      final c = await _invite(repo);
      await c.search('MP-AAAAA');
      final a = c.send();
      final b = c.send();
      expect(await b, isFalse);
      expect(await a, isTrue);
      expect(
        repo.calls.where((x) => x.startsWith('insertInvitation')).length,
        1,
      );
      c.dispose();
    });

    test(
      'R/S: sending touches neither group_members nor join requests',
      () async {
        final repo = _repo();
        final c = await _invite(repo);
        await c.search('MP-AAAAA');
        final rolesBefore = Map.of(repo.groups['g-1']!.roles);
        await c.send();
        expect(repo.groups['g-1']!.roles, rolesBefore);
        expect(repo.requestStatus, isEmpty);
        c.dispose();
      },
    );
  });

  group('Pre-send states (UX) and server boundary', () {
    test('L: already a member → refused, nothing sent', () async {
      final repo = _repo();
      final c = await _invite(repo);
      await c.search('MP-MEMBR');
      expect(c.stateFor(c.match!), InviteeState.alreadyMember);
      expect(await c.send(), isFalse);
      expect(c.error, contains('already a member'));
      expect(
        repo.calls.where((x) => x.startsWith('insertInvitation')),
        isEmpty,
      );
      c.dispose();
    });

    test(
      'K: pending exists → refused locally; server UNIQUE also refuses',
      () async {
        final repo = _repo();
        final c = await _invite(repo);
        await c.search('MP-PENDG');
        expect(c.stateFor(c.match!), InviteeState.alreadyPending);
        expect(await c.send(), isFalse);
        expect(c.error, contains('already pending'));
        // Bypass the client check: the fake's UNIQUE mirror rejects it.
        await expectLater(
          repo.sendInvitation(groupId: 'g-1', inviteeId: 'u-pend'),
          throwsA(isA<DataError>()),
        );
        expect(
          repo.invitations.where((i) => i.inviteeId == 'u-pend').length,
          1,
        );
        c.dispose();
      },
    );

    test(
      'M: declined → explicit state, deferred to the G5.5 re-invite path',
      () async {
        final repo = _repo();
        final c = await _invite(repo);
        await c.search('MP-DECLN');
        expect(c.stateFor(c.match!), InviteeState.declined);
        expect(await c.send(), isFalse);
        expect(c.error, contains('Re-invite'));
        expect(
          repo.invitations.firstWhere((i) => i.inviteeId == 'u-dec').status,
          'declined',
          reason: 'old row not silently mutated',
        );
        c.dispose();
      },
    );

    test('N: expired → explicit state, no expiry logic invented', () async {
      final repo = _repo();
      final c = await _invite(repo);
      await c.search('MP-EXPRD');
      expect(c.stateFor(c.match!), InviteeState.expired);
      expect(await c.send(), isFalse);
      expect(c.error, contains('expired'));
      expect(
        repo.invitations.firstWhere((i) => i.inviteeId == 'u-exp').status,
        'expired',
      );
      c.dispose();
    });

    test('accepted → treated as already invited; self → refused', () async {
      final repo = _repo();
      final c = await _invite(repo);
      await c.search('MP-ACCPT');
      expect(c.stateFor(c.match!), InviteeState.accepted);
      expect(await c.send(), isFalse);
      await c.search('MP-MYSLF');
      expect(c.stateFor(c.match!), InviteeState.self);
      expect(await c.send(), isFalse);
      expect(
        repo.calls.where((x) => x.startsWith('insertInvitation')),
        isEmpty,
      );
      c.dispose();
    });

    test('P/O: non-manager or forged group → INSERT policy refuses', () async {
      final repo = _repo();
      // Leader has MANAGE_MEMBERS (seeded); a plain member does not.
      repo.currentUser = 'u-mem';
      await expectLater(
        repo.sendInvitation(groupId: 'g-1', inviteeId: 'u-alice'),
        throwsA(isA<DataError>()),
      );
      // Manager of g-1 forging g-2 (no MANAGE_MEMBERS there).
      repo.currentUser = 'u-me';
      await expectLater(
        repo.sendInvitation(groupId: 'g-2', inviteeId: 'u-alice'),
        throwsA(isA<DataError>()),
      );
      expect(repo.invitations.any((i) => i.inviteeId == 'u-alice'), isFalse);
    });
  });

  group('Hub / sheet', () {
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

    testWidgets(
      'A/B: manager sees Invite; member does not and never looks up',
      (tester) async {
        final c = await pump(tester, _repo());
        expect(find.byKey(const Key('invite_member_action')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();

        final repo = _repo()..currentUser = 'u-mem';
        final m = await pump(tester, repo, user: 'u-mem');
        expect(find.byKey(const Key('invite_member_action')), findsNothing);
        expect(repo.lookups, isEmpty);
        await tester.pumpWidget(const SizedBox());
        m.dispose();
      },
    );

    testWidgets(
      'search → match card → confirm → sent → hub outgoing refreshed',
      (tester) async {
        final repo = _repo();
        final c = await pump(tester, repo);
        await tester.tap(find.byKey(const Key('invite_member_action')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('invite_send')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('invite_send')))
              .onPressed,
          isNull,
          reason: 'nothing to send yet',
        );
        await tester.enterText(
          find.byKey(const Key('invite_code_input')),
          ' mp-aaaaa ',
        );
        await tester.tap(find.byKey(const Key('invite_search')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('invite_match')), findsOneWidget);
        expect(find.text('Alice Roy'), findsOneWidget);
        expect(find.text('MP-AAAAA'), findsOneWidget);
        await tester.tap(find.byKey(const Key('invite_send')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_send_invitation')));
        await tester.pumpAndSettle();
        // Sheet closed, hub refreshed: new pending outgoing row visible.
        expect(find.byKey(const Key('invite_code_input')), findsNothing);
        final row = repo.invitations.firstWhere(
          (i) => i.inviteeId == 'u-alice',
        );
        expect(find.byKey(Key('outgoing_${row.id}')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('member / pending states disable Send with a label', (
      tester,
    ) async {
      final repo = _repo();
      final c = await pump(tester, repo);
      await tester.tap(find.byKey(const Key('invite_member_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite_code_input')),
        'MP-MEMBR',
      );
      await tester.tap(find.byKey(const Key('invite_search')));
      await tester.pumpAndSettle();
      expect(find.text('Already a member'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('invite_send')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('invite_code_input')),
        'MP-PENDG',
      );
      await tester.tap(find.byKey(const Key('invite_search')));
      await tester.pumpAndSettle();
      expect(find.text('Invitation pending'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('unknown code shows not-found in the sheet', (tester) async {
      final repo = _repo();
      final hub = _hub(repo);
      await hub.load();
      final c = InviteMemberController(
        groupId: 'g-1',
        currentUserId: 'u-me',
        members: hub.members,
        invitations: hub.outgoingInvitations,
        repository: repo,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InviteMemberSheet(hub: hub, controller: c),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('invite_code_input')),
        'MP-ZZZZZ',
      );
      await tester.tap(find.byKey(const Key('invite_search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('invite_error')), findsOneWidget);
      expect(find.textContaining('No user found'), findsOneWidget);
      expect(find.byKey(const Key('invite_match')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      hub.dispose();
    });
  });
}

class _SlowLookupRepository extends InMemoryGroupRepository {
  _SlowLookupRepository() : super(currentUser: 'u-me');
  @override
  Future<ProfileMatch?> findProfileByStudentCode(String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.findProfileByStudentCode(code);
  }
}

class _SlowSendRepository extends InMemoryGroupRepository {
  _SlowSendRepository() : super(currentUser: 'u-me');
  @override
  Future<void> sendInvitation({
    required String groupId,
    required String inviteeId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.sendInvitation(groupId: groupId, inviteeId: inviteeId);
  }
}
