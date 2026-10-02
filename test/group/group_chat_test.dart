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

    test('server rejection is mapped and the window is re-read', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      repo.failNextWith = const DataError(message: 'row-level security');
      expect(await c.sendMessage('Blocked'), isFalse);
      expect(c.error, 'row-level security');
      expect(c.messages.length, 4, reason: 'no optimistic row survives');
      expect(c.sending, isFalse);
    });
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
  Future<void> sendMessage({required String groupId, required String body}) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.sendMessage(groupId: groupId, body: body);
  }
}
