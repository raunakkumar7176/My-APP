// Sub-phase 3B — Doubts, on migration 0122's live contract:
// group_messages.is_doubt/doubt_solved/solved_by/solved_reply_id/solved_at;
// fn_mark_message_as_doubt (sender marks own top-level message; sender or
// admin/owner unmarks); fn_mark_doubt_solved/fn_unmark_doubt_solved (asker
// or admin/owner); fn_list_group_doubts/fn_get_group_doubt_counts (member
// read). The fake mirrors those rules; no role name is ever consulted in
// the UI beyond what the controller's permission getters already expose.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/group_message.dart';
import 'package:my_praperation/features/group/screens/group_chat_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/widgets/group_doubts_section.dart';

import 'fakes.dart';

// `InMemoryGroupRepository.currentUser` is shared mutable state representing
// "who's acting right now" — every multi-actor test in this file switches
// it alongside the controller's own `currentUserId`, same as the existing
// `..currentUser = 'u-owner'` pattern in group_chat_test.dart.
GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) {
  repo.currentUser = user;
  return GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);
}

/// g-1: owner u-owner, admin u-admin, member u-me (and u-other, a second
/// plain member, for "unrelated member" checks).
InMemoryGroupRepository _repo({String user = 'u-me'}) {
  return InMemoryGroupRepository(currentUser: user)
    ..seed(
      id: 'g-1',
      name: 'Physics',
      ownerId: 'u-owner',
      members: {'u-admin': 'admin', 'u-me': 'member', 'u-other': 'member'},
    );
}

void main() {
  group('TEST 1 — model: is_doubt/doubt_solved parsing + invariants', () {
    test('fromJson/toJson round-trip all five doubt columns', () {
      final m = GroupMessage.fromJson({
        'id': 'm-1',
        'group_id': 'g-1',
        'sender_id': 'u-me',
        'body': 'how do I solve this?',
        'created_at': '2026-09-01T10:00:00Z',
        'is_doubt': true,
        'doubt_solved': true,
        'solved_by': 'u-admin',
        'solved_reply_id': 'm-2',
        'solved_at': '2026-09-01T10:05:00Z',
      });
      expect(m.isDoubt, isTrue);
      expect(m.doubtSolved, isTrue);
      expect(m.solvedBy, 'u-admin');
      expect(m.solvedReplyId, 'm-2');
      expect(m.isSolvedDoubt, isTrue);
      expect(m.isOpenDoubt, isFalse);
      final json = m.toJson();
      expect(json['is_doubt'], true);
      expect(json['solved_reply_id'], 'm-2');
    });

    test('defaults to not-a-doubt when columns are absent', () {
      final m = GroupMessage.fromJson({
        'id': 'm-1',
        'group_id': 'g-1',
        'sender_id': 'u-me',
        'body': 'hi',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(m.isDoubt, isFalse);
      expect(m.doubtSolved, isFalse);
      expect(m.isOpenDoubt, isFalse);
    });

    test('clearDoubtState clears solved fields; optionally is_doubt too', () {
      final solved = GroupMessage.fromJson({
        'id': 'm-1',
        'group_id': 'g-1',
        'sender_id': 'u-me',
        'body': 'x',
        'created_at': '2026-09-01T10:00:00Z',
        'is_doubt': true,
        'doubt_solved': true,
        'solved_by': 'u-admin',
        'solved_reply_id': 'm-2',
        'solved_at': '2026-09-01T10:05:00Z',
      });
      final reopened = solved.clearDoubtState();
      expect(reopened.isDoubt, isTrue);
      expect(reopened.doubtSolved, isFalse);
      expect(reopened.solvedBy, isNull);
      final unmarked = solved.clearDoubtState(clearIsDoubt: true);
      expect(unmarked.isDoubt, isFalse);
      expect(unmarked.doubtSolved, isFalse);
    });
  });

  group('TEST 2 — controller: mark/unmark permissions', () {
    test('sender marks own top-level message; cannot mark a reply', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(groupId: 'g-1', senderId: 'u-me', body: 'q');
      final reply = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'r',
        replyToId: doubt.id,
      );
      final c = _hub(repo);
      await c.load();

      expect(c.canMarkAsDoubt(doubt), isTrue);
      expect(c.canMarkAsDoubt(reply), isFalse); // isReply guard

      final ok = await c.markAsDoubt(doubt, true);
      expect(ok, isTrue);
      expect(c.messages.firstWhere((m) => m.id == doubt.id).isDoubt, isTrue);
    });

    test('a different member cannot mark ANOTHER member''s message', () async {
      final repo = _repo();
      final other = repo.seedMessage(groupId: 'g-1', senderId: 'u-other', body: 'q');
      final c = _hub(repo); // acting as u-me
      await c.load();

      expect(c.canMarkAsDoubt(other), isFalse);
      final ok = await c.markAsDoubt(other, true);
      expect(ok, isFalse);
      expect(c.error, isNotNull);
    });

    test('sender can unmark own doubt; admin can unmark anyone''s', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'q',
        isDoubt: true,
      );
      final cMine = _hub(repo);
      await cMine.load();
      expect(cMine.canUnmarkAsDoubt(doubt), isTrue);
      expect(await cMine.markAsDoubt(doubt, false), isTrue);

      // Re-mark, then prove admin can unmark it too.
      await cMine.markAsDoubt(doubt, true);
      final cAdmin = _hub(repo, user: 'u-admin');
      await cAdmin.load();
      final asAdminSees = cAdmin.messages.firstWhere((m) => m.id == doubt.id);
      expect(cAdmin.canUnmarkAsDoubt(asAdminSees), isTrue);
      expect(await cAdmin.markAsDoubt(asAdminSees, false), isTrue);
    });

    test('an unrelated plain member cannot unmark someone else''s doubt', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'q',
        isDoubt: true,
      );
      final cOther = _hub(repo, user: 'u-other');
      await cOther.load();
      final seen = cOther.messages.firstWhere((m) => m.id == doubt.id);
      expect(cOther.canUnmarkAsDoubt(seen), isFalse);
      final ok = await cOther.markAsDoubt(seen, false);
      expect(ok, isFalse);
    });
  });

  group('TEST 3 — controller: solved-flow permissions', () {
    test('asker marks own doubt solved with someone else''s reply', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'q',
        isDoubt: true,
      );
      final reply = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-admin',
        body: 'a',
        replyToId: doubt.id,
      );
      final c = _hub(repo);
      await c.load();

      expect(c.canSolveDoubt(doubt, reply), isTrue);
      final ok = await c.markDoubtSolved(doubt, reply);
      expect(ok, isTrue);
      final updated = c.messages.firstWhere((m) => m.id == doubt.id);
      expect(updated.doubtSolved, isTrue);
      expect(updated.solvedReplyId, reply.id);
      expect(updated.solvedBy, 'u-me');
    });

    test('admin marks a different member''s doubt solved', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-other',
        body: 'q',
        isDoubt: true,
      );
      final reply = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-owner',
        body: 'a',
        replyToId: doubt.id,
      );
      final c = _hub(repo, user: 'u-admin');
      await c.load();
      final seenDoubt = c.messages.firstWhere((m) => m.id == doubt.id);
      final seenReply = c.messages.firstWhere((m) => m.id == reply.id);
      expect(c.canSolveDoubt(seenDoubt, seenReply), isTrue);
      expect(await c.markDoubtSolved(seenDoubt, seenReply), isTrue);
    });

    test('an unrelated plain member cannot mark it solved', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'q',
        isDoubt: true,
      );
      final reply = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-admin',
        body: 'a',
        replyToId: doubt.id,
      );
      final c = _hub(repo, user: 'u-other');
      await c.load();
      final seenDoubt = c.messages.firstWhere((m) => m.id == doubt.id);
      final seenReply = c.messages.firstWhere((m) => m.id == reply.id);
      expect(c.canSolveDoubt(seenDoubt, seenReply), isFalse);
      expect(await c.markDoubtSolved(seenDoubt, seenReply), isFalse);
    });

    test('a reply belonging to a DIFFERENT doubt is refused', () async {
      final repo = _repo();
      final doubt1 = repo.seedMessage(groupId: 'g-1', senderId: 'u-me', body: 'q1', isDoubt: true);
      final doubt2 = repo.seedMessage(groupId: 'g-1', senderId: 'u-me', body: 'q2', isDoubt: true);
      final replyToDoubt2 = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-admin',
        body: 'a2',
        replyToId: doubt2.id,
      );
      final c = _hub(repo);
      await c.load();
      final seenDoubt1 = c.messages.firstWhere((m) => m.id == doubt1.id);
      final seenReply = c.messages.firstWhere((m) => m.id == replyToDoubt2.id);
      // canSolveDoubt's own reply.replyToId == doubt.id check already
      // reflects this server-side refusal.
      expect(c.canSolveDoubt(seenDoubt1, seenReply), isFalse);
      final ok = await c.markDoubtSolved(seenDoubt1, seenReply);
      expect(ok, isFalse);
    });

    test('deleting the accepted reply reopens the doubt', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'q',
        isDoubt: true,
      );
      final reply = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-admin',
        body: 'a',
        replyToId: doubt.id,
      );
      final c = _hub(repo);
      await c.load();
      final seenDoubt = c.messages.firstWhere((m) => m.id == doubt.id);
      final seenReply = c.messages.firstWhere((m) => m.id == reply.id);
      await c.markDoubtSolved(seenDoubt, seenReply);
      expect(
        c.messages.firstWhere((m) => m.id == doubt.id).doubtSolved,
        isTrue,
      );

      // Deleted by its own sender (u-admin) — 'u-me' (the asker, a plain
      // member here) has no delete permission over someone else's reply.
      final cAdmin = _hub(repo, user: 'u-admin');
      await cAdmin.load();
      final adminView = cAdmin.messages.firstWhere((m) => m.id == reply.id);
      final deleted = await cAdmin.deleteMessage(adminView);
      expect(deleted, isTrue);

      final reopened =
          (await repo.messages('g-1')).firstWhere((m) => m.id == doubt.id);
      expect(reopened.doubtSolved, isFalse);
      expect(reopened.solvedReplyId, isNull);
    });
  });

  group('TEST 4 — controller: Open/Solved counts, listing, "My doubts"', () {
    test('counts and per-tab listings match seeded state', () async {
      final repo = _repo();
      final open1 = repo.seedMessage(groupId: 'g-1', senderId: 'u-me', body: 'o1', isDoubt: true);
      repo.seedMessage(groupId: 'g-1', senderId: 'u-admin', body: 'o2', isDoubt: true);
      final solved = repo.seedMessage(groupId: 'g-1', senderId: 'u-me', body: 's1', isDoubt: true);
      final reply = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-admin',
        body: 'a',
        replyToId: solved.id,
      );
      final c = _hub(repo);
      await c.load();
      await c.markDoubtSolved(
        c.messages.firstWhere((m) => m.id == solved.id),
        c.messages.firstWhere((m) => m.id == reply.id),
      );

      await c.loadDoubtsPage(solved: false, reset: true);
      await c.loadDoubtsPage(solved: true, reset: true);

      expect(c.doubtCounts.open, 2);
      expect(c.doubtCounts.solved, 1);
      expect(c.openDoubts.map((d) => d.id), contains(open1.id));
      expect(c.solvedDoubts.single.id, solved.id);
      expect(c.solvedDoubts.single.replyCount, 1);
      expect(c.hasMoreDoubts(false), isFalse); // fewer than a full page
    });

    test('"My doubts" filter scopes both tabs to the caller''s own', () async {
      final repo = _repo();
      final mine = repo.seedMessage(groupId: 'g-1', senderId: 'u-me', body: 'mine', isDoubt: true);
      repo.seedMessage(groupId: 'g-1', senderId: 'u-other', body: 'theirs', isDoubt: true);
      final c = _hub(repo);
      await c.load();
      await c.loadDoubtsPage(solved: false, reset: true);
      expect(c.openDoubts.length, 2);

      await c.setDoubtsMineOnly(true);
      expect(c.doubtsMineOnly, isTrue);
      expect(c.openDoubts.single.id, mine.id);
    });
  });

  group('TEST 4b — realtime: Doubts section reflects ANOTHER client''s change', () {
    test('counts update when another client solves a doubt', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(groupId: 'g-1', senderId: 'u-me', body: 'q', isDoubt: true);
      final reply = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-admin',
        body: 'a',
        replyToId: doubt.id,
      );
      final c = _hub(repo);
      await c.load(); // subscribes to realtime
      expect(c.doubtCounts.open, 1);
      expect(c.doubtCounts.solved, 0);

      // Another client (acting as u-admin) solves it directly against the
      // repo, then the server's realtime echo arrives as an UPDATE —
      // this controller never called markDoubtSolved itself.
      final solvedRow = repo.groups['g-1']!.messages
          .firstWhere((m) => m.id == doubt.id)
          .copyWith(
            doubtSolved: true,
            solvedBy: 'u-admin',
            solvedReplyId: reply.id,
            solvedAt: DateTime.now(),
          );
      repo.groups['g-1']!.messages[repo.groups['g-1']!.messages.indexWhere((m) => m.id == doubt.id)] = solvedRow;
      repo.simulateRealtimeUpdate('g-1', solvedRow);
      await Future<void>.delayed(Duration.zero); // let the async refresh settle

      expect(c.doubtCounts.open, 0);
      expect(c.doubtCounts.solved, 1);
    });

    test('an already-open Solved tab re-fetches when a doubt is unsolved remotely', () async {
      final repo = _repo();
      final doubt = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'q',
        isDoubt: true,
      );
      final reply = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-admin',
        body: 'a',
        replyToId: doubt.id,
      );
      final c = _hub(repo);
      await c.markDoubtSolved(doubt, reply);
      await c.load();
      await c.loadDoubtsPage(solved: true, reset: true);
      expect(c.solvedDoubts, isNotEmpty);

      final unsolvedRow = repo.groups['g-1']!.messages
          .firstWhere((m) => m.id == doubt.id)
          .clearDoubtState(); // still a doubt, just reopened
      repo.groups['g-1']!.messages[repo.groups['g-1']!.messages.indexWhere((m) => m.id == doubt.id)] = unsolvedRow;
      repo.simulateRealtimeUpdate('g-1', unsolvedRow);
      await Future<void>.delayed(Duration.zero);

      expect(c.solvedDoubts, isEmpty);
      expect(c.doubtCounts.open, 1);
    });
  });

  group('TEST 5 — widget: composer "Doubt" toggle, doubt chip, Doubts section', () {
    testWidgets('doubt toggle sends is_doubt=true; chip shows on the bubble', (
      tester,
    ) async {
      final repo = _repo();
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(home: GroupChatScreen(groupId: 'g-1', controller: c)),
      );
      await c.load();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('discussion_message_field')),
        'why does this fail?',
      );
      await tester.tap(find.byKey(const Key('discussion_doubt_toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('discussion_send_button')));
      await tester.pumpAndSettle();

      expect(repo.groups['g-1']!.messages.last.isDoubt, isTrue);
      expect(find.textContaining('Doubt'), findsWidgets);
    });

    testWidgets('Doubts section: tabs show counts; tap jumps to the message', (
      tester,
    ) async {
      final repo = _repo();
      final doubt = repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'a real doubt',
        isDoubt: true,
      );
      final c = _hub(repo);
      await c.load();
      String? jumped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupDoubtsSection(
              controller: c,
              onJumpToMessage: (id) => jumped = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('doubts_tab_open')), findsOneWidget);
      expect(find.textContaining('Open (1)'), findsOneWidget);
      expect(find.byKey(Key('doubt_${doubt.id}')), findsOneWidget);

      await tester.tap(find.byKey(Key('doubt_${doubt.id}')));
      await tester.pumpAndSettle();
      expect(jumped, doubt.id);
    });
  });
}
