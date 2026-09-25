// Group Hub redesign — realtime chat. Client-side subscription wiring
// (Supabase Realtime already publishes `group_messages` server-side, per
// migrations 0037/0049 — these tests exercise the NEW client code that
// consumes it, using InMemoryGroupRepository's simulate* helpers to stand
// in for the real Supabase channel).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/group_message.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

InMemoryGroupRepository _repo({String user = 'u-me'}) {
  final repo = InMemoryGroupRepository(currentUser: user)
    ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-me': 'member', 'u-b': 'member'})
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'Welcome', at: DateTime(2026, 1, 1, 9, 0));
  return repo;
}

void main() {
  group('Realtime subscription lifecycle', () {
    test('load() subscribes exactly once, even across repeated refresh() calls', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      await c.refresh();
      await c.refresh();
      expect(repo.calls.where((x) => x.startsWith('subscribeToMessages')).length, 1);
      c.dispose();
    });

    test('dispose() cancels the subscription', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(repo.activeSubscriptionCount, 1);
      c.dispose();
      // dispose() fires the cancel asynchronously (fire-and-forget); give
      // the microtask queue a turn.
      await Future<void>.delayed(Duration.zero);
      expect(repo.activeSubscriptionCount, 0);
    });

    test('a group the caller cannot access never subscribes', () async {
      final repo = _repo();
      final c = GroupHubController(groupId: 'g-2', repository: repo, currentUserId: 'u-me');
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(repo.calls.where((x) => x.startsWith('subscribeToMessages')).length, 0);
      c.dispose();
    });
  });

  group('Realtime INSERT merges into the loaded window', () {
    test('a message from another member appears without any reload call', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      final callsBefore = repo.calls.where((x) => x.startsWith('messages:')).length;

      repo.simulateRealtimeInsert(
        'g-1',
        GroupMessage(
          id: 'm-realtime-1',
          groupId: 'g-1',
          senderId: 'u-b',
          body: 'Hi from realtime',
          createdAt: DateTime(2026, 1, 1, 9, 5),
        ),
      );

      expect(c.messages.any((m) => m.id == 'm-realtime-1'), isTrue);
      expect(c.messages.last.body, 'Hi from realtime');
      // No extra server fetch was needed to show it.
      expect(repo.calls.where((x) => x.startsWith('messages:')).length, callsBefore);
      c.dispose();
    });

    test('the SAME message arriving twice (own send + realtime echo) is never duplicated', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();

      final dup = GroupMessage(
        id: 'm-dup',
        groupId: 'g-1',
        senderId: 'u-me',
        body: 'Ping',
        createdAt: DateTime(2026, 1, 1, 9, 6),
      );
      repo.simulateRealtimeInsert('g-1', dup);
      repo.simulateRealtimeInsert('g-1', dup); // the "echo"

      expect(c.messages.where((m) => m.id == 'm-dup').length, 1);
      c.dispose();
    });

    test('an insert for a DIFFERENT group is ignored', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      final before = c.messages.length;

      repo.simulateRealtimeInsert(
        'g-2',
        GroupMessage(id: 'm-other', groupId: 'g-2', senderId: 'u-other', body: 'noise', createdAt: DateTime.now()),
      );

      expect(c.messages.length, before);
      c.dispose();
    });

    test('messages stay ordered oldest -> newest after a realtime insert lands out of order', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();

      // Arrives "late" with an earlier timestamp than the last loaded one.
      repo.simulateRealtimeInsert(
        'g-1',
        GroupMessage(
          id: 'm-early',
          groupId: 'g-1',
          senderId: 'u-b',
          body: 'earlier',
          createdAt: DateTime(2026, 1, 1, 8, 59),
        ),
      );

      final times = c.messages.map((m) => m.createdAt).toList();
      final sorted = [...times]..sort();
      expect(times, sorted);
      c.dispose();
    });
  });

  group('Realtime UPDATE applies soft-delete in place', () {
    test('an UPDATE with deleted_at set replaces the message in the loaded window', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      final original = c.messages.first;

      repo.simulateRealtimeUpdate(
        'g-1',
        GroupMessage(
          id: original.id,
          groupId: original.groupId,
          senderId: original.senderId,
          body: original.body,
          createdAt: original.createdAt,
          deletedAt: DateTime(2026, 1, 1, 10, 0),
        ),
      );

      expect(c.messages.firstWhere((m) => m.id == original.id).isDeleted, isTrue);
      c.dispose();
    });

    test('an UPDATE for a message not in the loaded window is safely ignored', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      final before = c.messages.length;

      repo.simulateRealtimeUpdate(
        'g-1',
        GroupMessage(
          id: 'm-not-loaded',
          groupId: 'g-1',
          senderId: 'u-b',
          body: 'x',
          createdAt: DateTime.now(),
          deletedAt: DateTime.now(),
        ),
      );

      expect(c.messages.length, before);
      c.dispose();
    });
  });

  group('Connection status (Phase 14: "Reconnecting…")', () {
    test('starts connected once subscribed (fake channels join immediately)', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(c.isRealtimeConnected, isTrue);
      c.dispose();
    });

    test('a simulated disconnect flips the flag, a reconnect flips it back', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();

      repo.simulateConnectionChange('g-1', false);
      expect(c.isRealtimeConnected, isFalse);

      repo.simulateConnectionChange('g-1', true);
      expect(c.isRealtimeConnected, isTrue);
      c.dispose();
    });
  });
}
