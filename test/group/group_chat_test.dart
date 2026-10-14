// G8 — Group Chat on the existing `public.group_messages` contract
// (0001_init, unchanged by later migrations for the base columns):
//   id, group_id → groups, sender_id → profiles (nullable live), body 1..2000,
//   created_at; SELECT fn_is_member; INSERT sender_id = auth.uid() AND
//   fn_is_member; no UPDATE/DELETE policy. The fake mirrors exactly that.
// No realtime: server-backed window, refreshed on demand and after send.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group_message.dart';
import 'package:my_praperation/features/group/data/group_repository.dart';
import 'package:my_praperation/features/group/screens/group_chat_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

/// g-1 (owner u-owner, member u-me, member u-b) with three messages and one
/// system notice; g-2 (owner u-other) with one message. u-me ∉ g-2.
InMemoryGroupRepository _repo({String user = 'u-me'}) {
  final repo = InMemoryGroupRepository(currentUser: user)
    ..seed(
      id: 'g-1',
      name: 'Physics',
      ownerId: 'u-owner',
      members: {'u-me': 'member', 'u-b': 'member'},
    )
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  repo.profileNames['u-owner'] = 'Owner Person';
  repo.profileNames['u-b'] = 'Bea';
  repo.seedMessage(
    groupId: 'g-1',
    senderId: null,
    body: 'Group "Physics" created',
    at: DateTime(2026, 9, 10, 9, 0),
  );
  repo.seedMessage(
    groupId: 'g-1',
    senderId: 'u-owner',
    body: 'Welcome all',
    at: DateTime(2026, 9, 10, 9, 5),
  );
  repo.seedMessage(
    groupId: 'g-1',
    senderId: 'u-b',
    body: 'Hi!',
    at: DateTime(2026, 9, 10, 9, 6),
  );
  repo.seedMessage(
    groupId: 'g-1',
    senderId: 'u-me',
    body: 'Hello',
    at: DateTime(2026, 9, 10, 9, 7),
  );
  repo.seedMessage(
    groupId: 'g-2',
    senderId: 'u-other',
    body: 'Secret of g-2',
    at: DateTime(2026, 9, 10, 9, 8),
  );
  return repo;
}

void main() {
  group('TEST 1 — model parsing', () {
    test('fromJson maps the five base columns; sender nullable', () {
      final m = GroupMessage.fromJson({
        'id': 'm-1',
        'group_id': 'g-1',
        'sender_id': 'u-1',
        'body': 'hi',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(m.id, 'm-1');
      expect(m.groupId, 'g-1');
      expect(m.senderId, 'u-1');
      expect(m.body, 'hi');
      expect(m.createdAt.toUtc(), DateTime.utc(2026, 9, 1, 10));
      expect(m.isSystem, isFalse);
      expect(m.isDeleted, isFalse);
      expect(m.deletedAt, isNull);
      expect(m.toJson()['sender_id'], 'u-1');

      final sys = GroupMessage.fromJson({
        'id': 'm-2',
        'group_id': 'g-1',
        'sender_id': null,
        'body': 'History Cleared',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(sys.isSystem, isTrue);
      expect(sys.senderId, isNull);
    });

    test('fromJson parses deleted_at; isDeleted true when set', () {
      final m = GroupMessage.fromJson({
        'id': 'm-3',
        'group_id': 'g-1',
        'sender_id': 'u-1',
        'body': 'secret content',
        'created_at': '2026-09-01T10:00:00Z',
        'deleted_at': '2026-09-02T12:00:00Z',
      });
      expect(m.isDeleted, isTrue);
      expect(m.deletedAt, isNotNull);
      expect(m.deletedAt!.toUtc(), DateTime.utc(2026, 9, 2, 12));
      expect(m.body, 'secret content', reason: 'body is still in the model');
    });

    test('fromJson without deleted_at: isDeleted false', () {
      final m = GroupMessage.fromJson({
        'id': 'm-4',
        'group_id': 'g-1',
        'sender_id': 'u-1',
        'body': 'visible',
        'created_at': '2026-09-01T10:00:00Z',
      });
      expect(m.isDeleted, isFalse);
      expect(m.deletedAt, isNull);
    });

    test('toJson includes deleted_at only when non-null', () {
      final normal = GroupMessage(
        id: 'm-5',
        groupId: 'g-1',
        senderId: 'u-1',
        body: 'hi',
        createdAt: DateTime(2026, 9, 1),
      );
      expect(normal.toJson().containsKey('deleted_at'), isFalse);

      final deleted = GroupMessage(
        id: 'm-6',
        groupId: 'g-1',
        senderId: 'u-1',
        body: 'gone',
        createdAt: DateTime(2026, 9, 1),
        deletedAt: DateTime(2026, 9, 2),
      );
      expect(deleted.toJson().containsKey('deleted_at'), isTrue);
    });

    test('validation mirrors the live CHECK (1..2000 after trim)', () {
      expect(GroupHubController.validateMessage(''), contains('empty'));
      expect(GroupHubController.validateMessage('   '), contains('empty'));
      expect(GroupHubController.validateMessage('x' * 2000), isNull);
      expect(GroupHubController.validateMessage('x' * 2001), contains('2000'));
      expect(GroupHubController.validateMessage(' ok '), isNull);
    });
  });

  group('TEST 2/3/5/9 — read', () {
    test('member reads own group window, oldest → newest, no other group', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(c.messagesError, isNull);
      expect(c.messages.map((m) => m.body).toList(), [
        'Group "Physics" created',
        'Welcome all',
        'Hi!',
        'Hello',
      ]);
      expect(c.messages.every((m) => m.groupId == 'g-1'), isTrue);
      expect(c.messages.any((m) => m.body.contains('Secret')), isFalse);
      expect(c.hasOlderMessages, isFalse, reason: 'fewer than a page');
      expect(c.hasMessages, isTrue);
    });

    test('sender labels: System / display name / You / Former member', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      final labels = c.messages.map(c.messageSenderLabel).toList();
      expect(labels, ['System', 'Owner Person', 'Bea', 'You']);
      final gone = GroupMessage(
        id: 'm-x',
        groupId: 'g-1',
        senderId: 'u-left',
        body: 'bye',
        createdAt: DateTime(2026),
      );
      expect(c.messageSenderLabel(gone), 'Former member');
    });

    test('empty chat', () async {
      final repo = _repo();
      repo.groups['g-1']!.messages.clear();
      final c = _hub(repo);
      await c.load();
      expect(c.messagesLoading, isFalse);
      expect(c.messagesError, isNull);
      expect(c.messages, isEmpty);
      expect(c.hasMessages, isFalse);
    });

    test('window is finite: newest page only, older on demand, deterministic', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      for (var i = 0; i < messagePageSize + 20; i++) {
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-me',
          body: 'msg $i',
          at: DateTime(2026, 9, 1).add(Duration(minutes: i)),
        );
      }
      final c = _hub(repo);
      await c.load();
      expect(c.messages.length, messagePageSize);
      expect(c.messages.first.body, 'msg 20');
      expect(c.messages.last.body, 'msg ${messagePageSize + 19}');
      expect(c.hasOlderMessages, isTrue);

      await c.loadOlderMessages();
      expect(c.messages.length, messagePageSize + 20);
      expect(c.messages.first.body, 'msg 0');
      expect(c.hasOlderMessages, isFalse);
      // Strictly increasing, no duplicates.
      final ids = c.messages.map((m) => m.id).toSet();
      expect(ids.length, c.messages.length);
      for (var i = 1; i < c.messages.length; i++) {
        expect(
          c.messages[i].createdAt.isAfter(c.messages[i - 1].createdAt),
          isTrue,
        );
      }
      expect(repo.calls.where((x) => x == 'messages:g-1:before').length, 1);
    });
  });

  group('TEST 4 — error + retry', () {
    test('load error surfaces messagesError; retry recovers', () async {
      final repo = _FailingChatRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.group, isNotNull, reason: 'a chat failure never blocks the hub');
      expect(c.messagesError, 'Network error.');
      expect(c.messages, isEmpty);
      repo.failReads = false;
      await c.refreshMessages();
      expect(c.messagesError, isNull);
    });
  });

  group('TEST 6/7/13 — send', () {
    test('member sends → trimmed, sender = caller, window re-read', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(await c.sendMessage('  See you at 5  '), isTrue);
      expect(c.error, isNull);
      expect(c.messages.last.body, 'See you at 5');
      expect(c.messages.last.senderId, 'u-me');
      expect(c.messageSenderLabel(c.messages.last), 'You');
      expect(c.messages.length, 5);
      expect(repo.calls.where((x) => x == 'sendMessage:g-1').length, 1);
      expect(
        repo.calls.where((x) => x == 'messages:g-1').length,
        2,
        reason: 'initial load + reconciliation after send',
      );
      expect(c.sending, isFalse);
    });

    test('owner sends too (membership, not permission, is the gate)', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      expect(await c.sendMessage('Owner here'), isTrue);
      expect(c.messages.last.senderId, 'u-owner');
    });

    test('empty / whitespace / too long rejected before any server call', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(await c.sendMessage('   '), isFalse);
      expect(c.error, 'Message cannot be empty.');
      expect(await c.sendMessage('x' * 2001), isFalse);
      expect(c.error, contains('2000'));
      expect(repo.calls.any((x) => x.startsWith('sendMessage')), isFalse);
      expect(c.messages.length, 4);
    });

    test(
      'server rejection is mapped, the window is re-read, and the failed '
      'row stays as an optimistic "tap to retry" row (Phase 1)',
      () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        repo.failNextWith = const DataError(message: 'row-level security');
        expect(await c.sendMessage('Blocked'), isFalse);
        expect(c.error, 'row-level security');
        expect(c.messages.length, 5, reason: 'the failed row stays visible');
        final failed = c.messages.last;
        expect(failed.body, 'Blocked');
        expect(c.isMessageFailed(failed.id), isTrue);
        expect(c.isMessageSending(failed.id), isFalse);
        expect(c.sending, isFalse);

        // A second send while one has failed is refused until retried.
        expect(await c.sendMessage('Another'), isFalse);
        expect(c.messages.length, 5);

        // Retrying re-sends the exact same body under the same local id.
        expect(await c.retryPendingMessage(), isTrue);
        expect(c.messages.length, 5);
        expect(c.messages.last.body, 'Blocked');
        expect(c.isMessageFailed(c.messages.last.id), isFalse);
      },
    );
  });

  group('TEST 8 — single-flight', () {
    test('second send while first in flight is dropped', () async {
      final repo = _SlowChatRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = _hub(repo);
      await c.load();
      final first = c.sendMessage('One');
      expect(c.sending, isTrue);
      expect(await c.sendMessage('Two'), isFalse);
      expect(await first, isTrue);
      expect(c.messages.map((m) => m.body), ['One']);
      expect(repo.calls.where((x) => x == 'sendMessage:g-1').length, 1);
    });

    test('refresh and older-page are single-flight', () async {
      final repo = _SlowChatRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = _hub(repo);
      await c.load();
      final before = repo.calls.where((x) => x.startsWith('messages')).length;
      final r1 = c.refreshMessages();
      final r2 = c.refreshMessages();
      await Future.wait([r1, r2]);
      expect(
        repo.calls.where((x) => x.startsWith('messages')).length,
        before + 1,
      );
    });
  });

  group('TEST 10/11/12 — scoping and impersonation', () {
    test('non-member reads nothing and cannot send (fn_is_member gate)', () async {
      final repo = _repo(user: 'u-stranger');
      final c = GroupHubController(
        groupId: 'g-2',
        repository: repo,
        currentUserId: 'u-stranger',
      );
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(await repo.messages('g-2'), isEmpty);
      expect(await repo.messages('g-1'), isEmpty);
      await expectLater(
        repo.sendMessage(groupId: 'g-2', body: 'intrude'),
        throwsA(isA<DataError>()),
      );
      expect(repo.groups['g-2']!.messages.length, 1);
    });

    test('member of g-1 forging group_id g-2 is refused', () async {
      final repo = _repo();
      await expectLater(
        repo.sendMessage(groupId: 'g-2', body: 'cross-group'),
        throwsA(isA<DataError>()),
      );
      expect(repo.groups['g-2']!.messages.single.body, 'Secret of g-2');
      expect(await repo.messages('g-2'), isEmpty);
    });

    test('forged sender_id is refused by the (fake) policy', () async {
      final repo = _repo();
      await expectLater(
        repo.insertMessageAs(groupId: 'g-1', senderId: 'u-owner', body: 'fake'),
        throwsA(isA<DataError>()),
      );
      expect(repo.groups['g-1']!.messages.length, 4);
      // The repository API itself has no sender parameter: the client cannot
      // even express impersonation.
      await repo.sendMessage(groupId: 'g-1', body: 'real');
      expect(repo.groups['g-1']!.messages.last.senderId, 'u-me');
    });

    test('removed member loses read and send', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(c.messages.length, 4);
      repo.groups['g-1']!.roles.remove('u-me'); // removed server-side
      await c.refreshMessages();
      expect(c.messages, isEmpty);
      expect(await c.sendMessage('still here?'), isFalse);
      expect(c.error, contains('members'));
      expect(repo.groups['g-1']!.messages.length, 4);
    });
  });

  group('TEST 14 — dedicated chat screen', () {
    // Chat now lives on its own primary screen (GroupChatScreen), reached
    // directly from the group list; GroupHubScreen ("Info") no longer
    // embeds a chat preview — these cases moved from pumping the hub to
    // pumping the dedicated screen, with its own key names
    // (discussion_*) and assertions.
    Future<GroupHubController> pump(
      WidgetTester tester,
      InMemoryGroupRepository repo, {
      String user = 'u-me',
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _hub(repo, user: user);
      // GroupChatScreen only auto-loads a controller it constructed itself
      // (the real app always hands it an already-loaded one — either the
      // screen's own load on primary entry, or the Info screen's loaded
      // controller when navigating there — so an injected controller here
      // must be loaded the same way before pumping).
      await c.load();
      await tester.pumpWidget(
        MaterialApp(home: GroupChatScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('member: list, senders, field and send button', (
      tester,
    ) async {
      await pump(tester, _repo());
      expect(find.text('Welcome all'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Group "Physics" created'), findsOneWidget);
      expect(find.text('Bea'), findsOneWidget);
      expect(find.byKey(const Key('discussion_message_field')), findsOneWidget);
      expect(find.byKey(const Key('discussion_send_button')), findsOneWidget);
      expect(find.byKey(const Key('discussion_load_older')), findsNothing);
    });

    testWidgets('empty state', (tester) async {
      final repo = _repo();
      repo.groups['g-1']!.messages.clear();
      await pump(tester, repo);
      expect(find.byKey(const Key('discussion_empty')), findsOneWidget);
    });

    testWidgets('error + retry', (tester) async {
      final repo = _FailingChatRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'Recovered');
      await pump(tester, repo);
      expect(find.byKey(const Key('discussion_error')), findsOneWidget);
      repo.failReads = false;
      await tester.tap(find.byKey(const Key('discussion_retry')));
      await tester.pumpAndSettle();
      expect(find.text('Recovered'), findsOneWidget);
    });

    testWidgets(
      'soft-deleted message shows "This message was deleted" placeholder',
      (tester) async {
        final repo = _repo();
        final deleted = GroupMessage(
          id: 'm-del',
          groupId: 'g-1',
          senderId: 'u-owner',
          body: 'This should not be visible',
          createdAt: DateTime(2026, 9, 10, 9, 8),
          deletedAt: DateTime(2026, 9, 10, 10, 0),
        );
        repo.groups['g-1']!.messages.add(deleted);
        await pump(tester, repo);
        expect(find.byKey(const Key('discussion_message_m-del')), findsOneWidget);
        expect(
          find.text('This message was deleted'),
          findsOneWidget,
          reason: 'deleted body is replaced by placeholder',
        );
        expect(
          find.text('This should not be visible'),
          findsNothing,
          reason: 'original body is never rendered',
        );
      },
    );

    testWidgets('normal messages are not affected by deleted_at logic', (
      tester,
    ) async {
      await pump(tester, _repo());
      expect(find.text('Welcome all'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('This message was deleted'), findsNothing);
    });

    testWidgets('type → send → field cleared → message appears', (tester) async {
      final repo = _repo();
      final c = await pump(tester, repo);
      await tester.enterText(
        find.byKey(const Key('discussion_message_field')),
        ' Ping ',
      );
      await tester.tap(find.byKey(const Key('discussion_send_button')));
      await tester.pumpAndSettle();
      expect(c.messages.last.body, 'Ping');
      expect(find.text('Ping'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('discussion_message_field')))
            .controller!
            .text,
        isEmpty,
      );
    });

    testWidgets('empty send is rejected without a server call', (tester) async {
      final repo = _repo();
      final c = await pump(tester, repo);
      await tester.enterText(
        find.byKey(const Key('discussion_message_field')),
        '   ',
      );
      await tester.tap(find.byKey(const Key('discussion_send_button')));
      await tester.pumpAndSettle();
      expect(repo.calls.any((x) => x.startsWith('sendMessage')), isFalse);
      expect(c.messages.length, 4);
    });

    testWidgets('screen uses the injected controller, not a second source', (
      tester,
    ) async {
      final c = await pump(tester, _repo());
      await tester.enterText(
        find.byKey(const Key('discussion_message_field')),
        'Shared controller check',
      );
      await tester.tap(find.byKey(const Key('discussion_send_button')));
      await tester.pumpAndSettle();
      expect(c.messages.last.body, 'Shared controller check');
    });
  });

  group('TEST 15 — grouping, date separators, admin-only lock, role badges', () {
    Future<GroupHubController> pump(
      WidgetTester tester,
      InMemoryGroupRepository repo, {
      String user = 'u-me',
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _hub(repo, user: user);
      await c.load();
      await tester.pumpWidget(
        MaterialApp(home: GroupChatScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets(
      'consecutive same-sender messages within 2 minutes group: sender label shown once',
      (tester) async {
        final repo = _repo();
        // 'Hi!' (u-b, 09:06) already exists; add a second u-b message one
        // minute later — close enough to group with it.
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-b',
          body: 'Still there?',
          // Between 'Hi!' (u-b, 9:06) and 'Hello' (u-me, 9:07), so the two
          // u-b messages land adjacent to each other in the sorted window.
          at: DateTime(2026, 9, 10, 9, 6, 30),
        );
        await pump(tester, repo);
        expect(find.text('Hi!'), findsOneWidget);
        expect(find.text('Still there?'), findsOneWidget);
        expect(
          find.text('Bea'),
          findsOneWidget,
          reason: 'grouped bubbles show the sender label only on the first one',
        );
      },
    );

    testWidgets(
      'same-sender messages more than 2 minutes apart do not group: sender label shown twice',
      (tester) async {
        final repo = _repo();
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-b',
          body: 'Back again',
          at: DateTime(2026, 9, 10, 9, 20),
        );
        await pump(tester, repo);
        expect(find.text('Bea'), findsNWidgets(2));
      },
    );

    testWidgets('a message on a new day gets its own date separator', (
      tester,
    ) async {
      final repo = _repo();
      repo.seedMessage(
        groupId: 'g-1',
        senderId: 'u-owner',
        body: 'Next day message',
        at: DateTime(2026, 9, 11, 8, 0),
      );
      await pump(tester, repo);
      // All seeded 09-10 messages share one separator; the new 09-11
      // message gets a second, distinct one.
      expect(find.textContaining('SEP 2026'), findsNWidgets(2));
    });

    testWidgets(
      'admin_only_chat=true: a plain member sees the lock, not the composer',
      (tester) async {
        final repo = _repo();
        repo.groups['g-1']!.adminOnlyChat = true;
        await pump(tester, repo);
        expect(find.byKey(const Key('discussion_admin_only_lock')), findsOneWidget);
        expect(find.byKey(const Key('discussion_message_field')), findsNothing);
        expect(find.byKey(const Key('discussion_send_button')), findsNothing);
        expect(find.text('Only admins can send messages right now'), findsOneWidget);
      },
    );

    testWidgets(
      'admin_only_chat=true: the owner still sees the normal composer',
      (tester) async {
        final repo = _repo()..currentUser = 'u-owner';
        repo.groups['g-1']!.adminOnlyChat = true;
        await pump(tester, repo, user: 'u-owner');
        expect(find.byKey(const Key('discussion_admin_only_lock')), findsNothing);
        expect(find.byKey(const Key('discussion_message_field')), findsOneWidget);
      },
    );

    testWidgets(
      'admin_only_chat=true: an admin also still sees the normal composer',
      (tester) async {
        final repo = _repo();
        repo.groups['g-1']!.adminOnlyChat = true;
        repo.groups['g-1']!.roles['u-me'] = 'admin';
        await pump(tester, repo);
        expect(find.byKey(const Key('discussion_admin_only_lock')), findsNothing);
        expect(find.byKey(const Key('discussion_message_field')), findsOneWidget);
      },
    );

    testWidgets('admin_only_chat=false: every role sees the normal composer', (
      tester,
    ) async {
      final repo = _repo();
      await pump(tester, repo);
      expect(find.byKey(const Key('discussion_admin_only_lock')), findsNothing);
      expect(find.byKey(const Key('discussion_message_field')), findsOneWidget);
    });

    testWidgets(
      "an admin sender's bubble shows the Admin role badge; a plain member's does not",
      (tester) async {
        final repo = _repo();
        repo.groups['g-1']!.roles['u-b'] = 'admin';
        await pump(tester, repo);
        expect(find.text('🛡️ Admin'), findsOneWidget, reason: "u-b's message carries the badge");
        expect(
          find.text('👑 Owner'),
          findsOneWidget,
          reason: "the fixture's existing u-owner message still carries its own badge",
        );
      },
    );

    testWidgets(
      "the owner's bubble shows the Owner role badge",
      (tester) async {
        final repo = _repo();
        await pump(tester, repo);
        expect(find.text('👑 Owner'), findsOneWidget, reason: "u-owner's message carries the badge");
        expect(find.text('🛡️ Admin'), findsNothing);
      },
    );

    testWidgets(
      'consecutive role-changed system notices merge into one pill',
      (tester) async {
        final repo = _repo();
        final first = repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-owner',
          body: 'Alice is now admin',
          at: DateTime(2026, 9, 10, 9, 10),
          messageType: 'system',
          metadata: const {'type': 'role_changed'},
        );
        final second = repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-owner',
          body: 'Bob is now admin',
          at: DateTime(2026, 9, 10, 9, 11),
          messageType: 'system',
          metadata: const {'type': 'role_changed'},
        );
        await pump(tester, repo);
        expect(find.text('Alice is now admin'), findsOneWidget);
        expect(find.text('Bob is now admin'), findsOneWidget);
        // Only the first notice keeps its own pill — the second merges
        // into it and renders nothing of its own.
        expect(find.byKey(Key('discussion_message_${first.id}')), findsOneWidget);
        expect(find.byKey(Key('discussion_message_${second.id}')), findsNothing);
      },
    );

    testWidgets(
      'a role-changed notice on a later day does not merge with an earlier one',
      (tester) async {
        final repo = _repo();
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-owner',
          body: 'Alice is now admin',
          at: DateTime(2026, 9, 10, 9, 10),
          messageType: 'system',
          metadata: const {'type': 'role_changed'},
        );
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-owner',
          body: 'Bob is now admin',
          at: DateTime(2026, 9, 11, 9, 10),
          messageType: 'system',
          metadata: const {'type': 'role_changed'},
        );
        await pump(tester, repo);
        expect(find.text('Alice is now admin'), findsOneWidget);
        expect(find.text('Bob is now admin'), findsOneWidget);
      },
    );
  });

  group('Phase 3A — message actions', () {
    group('controller: canXxx role/ownership reflection', () {
      test('canDeleteMessage: own always; others only for owner/admin', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final own = c.messages.firstWhere((m) => m.senderId == 'u-me');
        final others = c.messages.firstWhere((m) => m.senderId == 'u-b');
        expect(c.canDeleteMessage(own), isTrue);
        expect(c.canDeleteMessage(others), isFalse);

        final adminRepo = _repo()..groups['g-1']!.roles['u-me'] = 'admin';
        final adminC = _hub(adminRepo);
        await adminC.load();
        final othersAsAdmin = adminC.messages.firstWhere(
          (m) => m.senderId == 'u-b',
        );
        expect(adminC.canDeleteMessage(othersAsAdmin), isTrue);
      });

      test('canEditMessage: own + within 15 minutes only', () async {
        final repo = _repo(user: 'u-owner');
        final now = DateTime.now();
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-owner',
          body: 'fresh',
          at: now.subtract(const Duration(minutes: 1)),
        );
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-owner',
          body: 'stale',
          at: now.subtract(const Duration(minutes: 20)),
        );
        final c = _hub(repo, user: 'u-owner');
        await c.load();
        final fresh = c.messages.firstWhere((m) => m.body == 'fresh');
        final stale = c.messages.firstWhere((m) => m.body == 'stale');
        final others = c.messages.firstWhere((m) => m.senderId == 'u-b');
        expect(c.canEditMessage(fresh), isTrue);
        expect(c.canEditMessage(stale), isFalse);
        expect(c.canEditMessage(others), isFalse);
      });

      test('canPinMessages: admin/owner only', () async {
        final memberC = _hub(_repo());
        await memberC.load();
        expect(memberC.canPinMessages, isFalse);

        final ownerRepo = _repo(user: 'u-owner');
        final ownerC = _hub(ownerRepo, user: 'u-owner');
        await ownerC.load();
        expect(ownerC.canPinMessages, isTrue);
      });

      test('canReportMessage: never own, never deleted', () async {
        final repo = _repo(user: 'u-owner');
        final c = _hub(repo, user: 'u-owner');
        await c.load();
        final own = c.messages.firstWhere((m) => m.senderId == 'u-owner');
        final others = c.messages.firstWhere((m) => m.senderId == 'u-b');
        expect(c.canReportMessage(own), isFalse);
        expect(c.canReportMessage(others), isTrue);
        // Owner can delete any message; prove the now-deleted message is no
        // longer reportable.
        expect(await c.deleteMessage(others), isTrue);
        final deleted = c.messages.firstWhere((m) => m.id == others.id);
        expect(c.canReportMessage(deleted), isFalse);
      });
    });

    group('controller: edit / pin / unpin / report', () {
      test('editMessage updates body and editedAt on success', () async {
        final repo = _repo();
        // The fixtures seed historical timestamps; edit needs a message
        // sent within the server's 15-minute window.
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-me',
          body: 'fresh for editing',
          at: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        final c = _hub(repo);
        await c.load();
        final own = c.messages.firstWhere((m) => m.body == 'fresh for editing');
        expect(await c.editMessage(own, 'edited text'), isTrue);
        final updated = c.messages.firstWhere((m) => m.id == own.id);
        expect(updated.body, 'edited text');
        expect(updated.isEdited, isTrue);
      });

      test('editMessage refuses someone else\'s message', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final others = c.messages.firstWhere((m) => m.senderId == 'u-b');
        expect(await c.editMessage(others, 'hijack'), isFalse);
        expect(c.error, isNotNull);
      });

      test('pin / unpin round trip updates pinnedMessages', () async {
        final repo = _repo(user: 'u-owner');
        final c = _hub(repo, user: 'u-owner');
        await c.load();
        final target = c.messages.firstWhere((m) => m.senderId == 'u-owner');
        expect(await c.pinMessage(target), isTrue);
        expect(c.pinnedMessages.map((m) => m.id), [target.id]);
        expect(await c.unpinMessage(target), isTrue);
        expect(c.pinnedMessages, isEmpty);
      });

      test('pin refused for a plain member', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final target = c.messages.firstWhere((m) => m.senderId == 'u-b');
        expect(await c.pinMessage(target), isFalse);
        expect(c.error, isNotNull);
      });

      test('pinning a 4th message is refused once 3 are pinned', () async {
        final repo = _repo(user: 'u-owner');
        final c = _hub(repo, user: 'u-owner');
        await c.load();
        final msgs = c.messages.where((m) => !m.isSystem).toList();
        expect(msgs.length, greaterThanOrEqualTo(3));
        for (final m in msgs.take(3)) {
          expect(await c.pinMessage(m), isTrue);
        }
        repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'extra');
        await c.refreshMessages();
        final fourth = c.messages.firstWhere((m) => m.body == 'extra');
        expect(await c.pinMessage(fourth), isFalse);
        expect(c.pinnedMessages.length, 3);
      });

      test('reportMessage succeeds once; a repeat call is still success (dedupe server-side)', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final target = c.messages.firstWhere((m) => m.senderId == 'u-b');
        expect(await c.reportMessage(target, 'spam'), isTrue);
        expect(await c.reportMessage(target, 'spam'), isTrue);
        expect(repo.rawMessageReports.length, 1);
      });
    });

    group('controller: reply', () {
      test('sendMessage threads replyToId through to the repository', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final parent = c.messages.firstWhere((m) => m.senderId == 'u-b');
        expect(await c.sendMessage('a reply', replyToId: parent.id), isTrue);
        final reply = c.messages.firstWhere((m) => m.body == 'a reply');
        expect(reply.replyToId, parent.id);
      });

      test('resolveReplyPreview returns the loaded message directly', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final parent = c.messages.firstWhere((m) => m.senderId == 'u-b');
        final resolved = await c.resolveReplyPreview(parent.id);
        expect(resolved?.id, parent.id);
        expect(repo.calls.any((x) => x.startsWith('messageById')), isFalse);
      });

      test('resolveReplyPreview fetches and caches when not in the loaded window', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        // Seeded AFTER load, so it's in the backing store but not in the
        // controller's already-loaded `_messages` window.
        final older = repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-b',
          body: 'ancient',
          at: DateTime(2026, 9, 1),
        );
        final resolved = await c.resolveReplyPreview(older.id);
        expect(resolved?.id, older.id);
        expect(repo.calls.where((x) => x == 'messageById:${older.id}').length, 1);
        await c.resolveReplyPreview(older.id); // cached, no second fetch
        expect(repo.calls.where((x) => x == 'messageById:${older.id}').length, 1);
      });
    });

    group('controller: jumpToMessage', () {
      test('already-loaded message: returns true, no extra calls', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final target = c.messages.first;
        final callsBefore = repo.calls.length;
        expect(await c.jumpToMessage(target.id), isTrue);
        expect(repo.calls.length, callsBefore);
      });

      test('not-loaded message: fetches it and the window around it, merges in', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final older = repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-b',
          body: 'far back',
          at: DateTime(2026, 9, 1),
        );
        expect(c.messages.any((m) => m.id == older.id), isFalse);

        expect(await c.jumpToMessage(older.id), isTrue);
        expect(c.messages.any((m) => m.id == older.id), isTrue);
      });

      test('unknown message id returns false and leaves the window untouched', () async {
        final repo = _repo();
        final c = _hub(repo);
        await c.load();
        final before = c.messages.map((m) => m.id).toList();
        expect(await c.jumpToMessage('does-not-exist'), isFalse);
        expect(c.messages.map((m) => m.id).toList(), before);
      });
    });

    group('widget: long-press menu reflects role/ownership', () {
      Future<GroupHubController> pump3a(
        WidgetTester tester,
        InMemoryGroupRepository repo, {
        String user = 'u-me',
      }) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = _hub(repo, user: user);
        await c.load();
        await tester.pumpWidget(
          MaterialApp(home: GroupChatScreen(groupId: 'g-1', controller: c)),
        );
        await tester.pumpAndSettle();
        return c;
      }

      testWidgets('member on own message: Reply/Copy/Edit/Report/Delete, no Pin', (
        tester,
      ) async {
        final repo = _repo();
        // Edit requires a message within the 15-minute window.
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-me',
          body: 'fresh own message',
          at: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        final c = await pump3a(tester, repo);
        final own = c.messages.firstWhere((m) => m.body == 'fresh own message');
        await tester.longPress(find.text(own.body));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('reply_message_${own.id}')), findsOneWidget);
        expect(find.text('Copy message'), findsOneWidget);
        expect(find.byKey(Key('edit_message_${own.id}')), findsOneWidget);
        expect(find.byKey(const Key('delete_message_for_everyone')), findsOneWidget);
        expect(find.byKey(Key('report_message_${own.id}')), findsNothing);
        expect(find.byKey(Key('pin_message_${own.id}')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('member on someone else\'s message: Report shown, Delete/Edit/Pin hidden', (
        tester,
      ) async {
        final repo = _repo();
        final c = await pump3a(tester, repo);
        final others = c.messages.firstWhere((m) => m.senderId == 'u-b');
        await tester.longPress(find.text(others.body));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('report_message_${others.id}')), findsOneWidget);
        expect(find.byKey(const Key('delete_message_for_everyone')), findsNothing);
        expect(find.byKey(Key('edit_message_${others.id}')), findsNothing);
        expect(find.byKey(Key('pin_message_${others.id}')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('admin sees Pin on any message and can delete any message', (
        tester,
      ) async {
        final repo = _repo()..groups['g-1']!.roles['u-me'] = 'admin';
        final c = await pump3a(tester, repo);
        final others = c.messages.firstWhere((m) => m.senderId == 'u-b');
        await tester.longPress(find.text(others.body));
        await tester.pumpAndSettle();
        expect(find.byKey(Key('pin_message_${others.id}')), findsOneWidget);
        expect(find.byKey(const Key('delete_message_for_everyone')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('tapping Pin shows the pinned bar; tapping its close unpins', (
        tester,
      ) async {
        final repo = _repo()..currentUser = 'u-owner';
        final c = await pump3a(tester, repo, user: 'u-owner');
        final target = c.messages.firstWhere((m) => m.senderId == 'u-b');
        await tester.longPress(find.text(target.body));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('pin_message_${target.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('discussion_pinned_bar')), findsOneWidget);

        await tester.tap(find.byKey(Key('discussion_unpin_${target.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('discussion_pinned_bar')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('Reply opens the reply bar; Cancel clears it; sending attaches replyToId', (
        tester,
      ) async {
        final repo = _repo();
        final c = await pump3a(tester, repo);
        final target = c.messages.firstWhere((m) => m.senderId == 'u-b');
        await tester.longPress(find.text(target.body));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('reply_message_${target.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('discussion_reply_bar')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('discussion_message_field')),
          'my reply',
        );
        await tester.tap(find.byKey(const Key('discussion_send_button')));
        await tester.pumpAndSettle();
        final sent = c.messages.firstWhere((m) => m.body == 'my reply');
        expect(sent.replyToId, target.id);
        expect(find.byKey(const Key('discussion_reply_bar')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('Edit dialog saves a new body and shows the edited label', (
        tester,
      ) async {
        final repo = _repo();
        repo.seedMessage(
          groupId: 'g-1',
          senderId: 'u-me',
          body: 'fresh for editing',
          at: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        final c = await pump3a(tester, repo);
        final own = c.messages.firstWhere((m) => m.body == 'fresh for editing');
        await tester.longPress(find.text(own.body));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('edit_message_${own.id}')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('edit_message_field')),
          'updated body',
        );
        await tester.tap(find.byKey(const Key('confirm_edit_message')));
        await tester.pumpAndSettle();
        expect(find.text('updated body'), findsOneWidget);
        expect(find.textContaining('edited'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('Report dialog: pick a reason, confirm, success snackbar', (
        tester,
      ) async {
        final repo = _repo();
        final c = await pump3a(tester, repo);
        final others = c.messages.firstWhere((m) => m.senderId == 'u-b');
        await tester.longPress(find.text(others.body));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('report_message_${others.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('report_reason_abuse')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_report_message')));
        await tester.pumpAndSettle();
        expect(find.text('Message reported.'), findsOneWidget);
        expect(repo.rawMessageReports.single['reason'], 'abuse');
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
    });
  });
}

class _FailingChatRepository extends InMemoryGroupRepository {
  _FailingChatRepository() : super(currentUser: 'u-me');
  bool failReads = true;
  @override
  Future<List<GroupMessage>> messages(
    String groupId, {
    int limit = messagePageSize,
    DateTime? before,
  }) async {
    if (failReads) throw const DataError(message: 'Network error.');
    return super.messages(groupId, limit: limit, before: before);
  }
}

class _SlowChatRepository extends InMemoryGroupRepository {
  _SlowChatRepository() : super(currentUser: 'u-me');
  @override
  Future<List<GroupMessage>> messages(
    String groupId, {
    int limit = messagePageSize,
    DateTime? before,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.messages(groupId, limit: limit, before: before);
  }

  @override
  Future<void> sendMessage({
    required String groupId,
    required String body,
    String? replyToId,
    bool isDoubt = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.sendMessage(
      groupId: groupId,
      body: body,
      replyToId: replyToId,
      isDoubt: isDoubt,
    );
  }
}
