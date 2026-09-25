// Group Hub redesign — single-member group deletion (Phase 22). Server
// authorization mirrors `migrations/GROUP_HUB_rpc_delete_group.sql`:
// caller must be the owner AND no other members may remain. These tests
// exercise the client-side gate (`canDeleteGroup`) plus the
// `deleteGroup()` flow via InMemoryGroupRepository's fake, which encodes
// the same two checks the real RPC performs.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

void main() {
  group('canDeleteGroup', () {
    test('true for the owner of a solo group (owner is the only member)', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', name: 'Solo', ownerId: 'u-owner');
      final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-owner');
      await c.load();

      expect(c.canDeleteGroup, isTrue);
      c.dispose();
    });

    test('false for the owner when other members remain', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', name: 'Team', ownerId: 'u-owner', members: {'u-b': 'member'});
      final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-owner');
      await c.load();

      expect(c.canDeleteGroup, isFalse);
      c.dispose();
    });

    test('false for a non-owner member, even in a solo-looking view', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-b')
        ..seed(id: 'g-1', name: 'Team', ownerId: 'u-owner', members: {'u-b': 'member'});
      final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-b');
      await c.load();

      expect(c.canDeleteGroup, isFalse);
      c.dispose();
    });
  });

  group('deleteGroup()', () {
    test('succeeds for a solo owner and clears local group state', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', name: 'Solo', ownerId: 'u-owner');
      final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-owner');
      await c.load();

      final ok = await c.deleteGroup();

      expect(ok, isTrue);
      expect(repo.groups.containsKey('g-1'), isFalse);
      expect(c.group, isNull);
      c.dispose();
    });

    test('is refused client-side (no server call) when other members remain', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', name: 'Team', ownerId: 'u-owner', members: {'u-b': 'member'});
      final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-owner');
      await c.load();

      final ok = await c.deleteGroup();

      expect(ok, isFalse);
      expect(repo.calls.where((x) => x.startsWith('deleteGroup:')).length, 0);
      expect(repo.groups.containsKey('g-1'), isTrue);
      expect(c.error, isNotNull);
      c.dispose();
    });

    test('a non-owner cannot delete even if the server were somehow called', () async {
      final repo = InMemoryGroupRepository(currentUser: 'u-b')
        ..seed(id: 'g-1', name: 'Team', ownerId: 'u-owner', members: {'u-b': 'member'});
      final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-b');
      await c.load();

      final ok = await c.deleteGroup();

      expect(ok, isFalse);
      expect(repo.groups.containsKey('g-1'), isTrue);
      c.dispose();
    });

    test('server-side authorization is the real guard: forging the RPC call directly is still refused', () async {
      // Proves the fake's deleteGroup() itself enforces owner+solo, not just
      // the controller's canDeleteGroup gate (mirrors what the live RPC does
      // independent of any client check).
      final repo = InMemoryGroupRepository(currentUser: 'u-owner')
        ..seed(id: 'g-1', name: 'Team', ownerId: 'u-owner', members: {'u-b': 'member'});

      await expectLater(repo.deleteGroup('g-1'), throwsA(anything));
      expect(repo.groups.containsKey('g-1'), isTrue);
    });
  });
}
