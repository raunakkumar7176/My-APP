// G5.1 — invite code management. The code is read only inside the
// permission-gated settings flow, displayed/copied/rotated there, and never
// appears in the list RPC row, the Group model, the hub, or the members hub.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/screens/group_list_screen.dart';
import 'package:my_praperation/features/group/screens/group_members_screen.dart';
import 'package:my_praperation/features/group/screens/group_settings_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_list_controller.dart';
import 'package:my_praperation/features/group/state/invite_code_controller.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

void main() {
  group('InviteCodeController', () {
    test('load → code; never in the group model or list row', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', inviteCode: 'ABCD1234');
      final c = InviteCodeController(groupId: 'g-1', repository: repo);
      expect(c.hasLoaded, isFalse);
      await c.load();
      expect(c.code, 'ABCD1234');
      expect(c.error, isNull);
      expect(repo.inviteCodeReads, ['g-1']);

      final list = await repo.myGroups();
      expect(list.single.toJson().containsKey('invite_code'), isFalse);
      final hub = await repo.groupForMember('g-1');
      expect(hub!.toJson().containsKey('invite_code'), isFalse);
      expect(
        Group.fromJson({
          'id': 'g-1',
          'name': 'x',
          'owner_id': 'u',
          'created_at': '2026-09-01T00:00:00Z',
          'invite_code': 'LEAK1234',
        }).toJson().containsKey('invite_code'),
        isFalse,
        reason: 'the model has no field for it',
      );
      c.dispose();
    });

    test('load failure → error + retry works', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', inviteCode: 'ABCD1234')
        ..failNextWith = const DataError(message: 'Network error.');
      final c = InviteCodeController(groupId: 'g-1', repository: repo);
      await c.load();
      expect(c.code, isNull);
      expect(c.error, 'Network error.');
      await c.retry();
      expect(c.code, 'ABCD1234');
      expect(c.error, isNull);
      c.dispose();
    });

    test('rotate calls fn_reset_group_invite with the exact id and shows the '
        'server value', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', inviteCode: 'ABCD1234');
      final c = InviteCodeController(groupId: 'g-1', repository: repo);
      await c.load();
      expect(await c.rotate(), isTrue);
      expect(repo.calls, contains('rotate:g-1'));
      expect(c.code, 'ROT00001', reason: 'server-returned, not client-made');
      expect(c.justRotated, isTrue);
      expect(repo.groups['g-1']!.inviteCode, 'ROT00001');
      c.dispose();
    });

    test('rotate is single-flight', () async {
      final repo = _SlowRotateRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', inviteCode: 'ABCD1234');
      final c = InviteCodeController(groupId: 'g-1', repository: repo);
      await c.load();
      final first = c.rotate();
      final second = c.rotate();
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(repo.rotations, 1);
      c.dispose();
    });

    test(
      'rotate failure keeps the previous (still valid) code, no stale success',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-me', inviteCode: 'ABCD1234');
        final c = InviteCodeController(groupId: 'g-1', repository: repo);
        await c.load();
        expect(await c.rotate(), isTrue);
        expect(c.justRotated, isTrue);
        repo.failNextWith = const DataError(message: 'Network error.');
        expect(await c.rotate(), isFalse);
        expect(c.code, 'ROT00001');
        expect(c.error, 'Network error.');
        expect(c.justRotated, isFalse, reason: 'cleared by the failed attempt');
        expect(c.isRotating, isFalse);
        c.dispose();
      },
    );

    test('server authorization error is mapped (non-owner leader)', () async {
      final repo = InMemoryGroupRepository()
        ..seed(
          id: 'g-1',
          ownerId: 'u-owner',
          inviteCode: 'ABCD1234',
          members: {'u-me': 'leader'},
        );
      final c = InviteCodeController(groupId: 'g-1', repository: repo);
      await c.load(); // readable by a member (live row-level policy)
      expect(await c.rotate(), isFalse);
      expect(c.error, contains('settings permission'));
      expect(repo.groups['g-1']!.inviteCode, 'ABCD1234');
      c.dispose();
    });
  });

  group('Where the code is (not) requested', () {
    Future<void> pumpTall(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: home));
      await tester.pumpAndSettle();
    }

    testWidgets('list, hub and members screens never read it', (tester) async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', inviteCode: 'ABCD1234');
      final list = GroupListController(repository: repo);
      await pumpTall(tester, GroupListScreen(controller: list));
      await tester.pumpWidget(const SizedBox());
      list.dispose();

      final hub = _hub(repo);
      await pumpTall(tester, GroupHubScreen(groupId: 'g-1', controller: hub));
      await tester.pumpWidget(const SizedBox());
      hub.dispose();

      final members = _hub(repo);
      await pumpTall(
        tester,
        GroupMembersScreen(groupId: 'g-1', controller: members),
      );
      await tester.pumpWidget(const SizedBox());
      members.dispose();

      expect(repo.inviteCodeReads, isEmpty);
      expect(find.text('ABCD1234'), findsNothing);
    });

    testWidgets('settings: unauthorized member never triggers the read', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository()
        ..seed(
          id: 'g-1',
          ownerId: 'u-owner',
          inviteCode: 'ABCD1234',
          members: {'u-me': 'member'},
        );
      final c = _hub(repo);
      await pumpTall(
        tester,
        GroupSettingsScreen(groupId: 'g-1', controller: c),
      );
      expect(find.byKey(const Key('settings_forbidden')), findsOneWidget);
      expect(find.byKey(const Key('invite_section')), findsNothing);
      expect(repo.inviteCodeReads, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('settings: owner sees, copies and rotates the code', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', inviteCode: 'ABCD1234');
      final c = _hub(repo);
      final invite = InviteCodeController(groupId: 'g-1', repository: repo);

      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpTall(
        tester,
        GroupSettingsScreen(
          groupId: 'g-1',
          controller: c,
          inviteCodeController: invite,
        ),
      );
      expect(find.byKey(const Key('invite_section')), findsOneWidget);
      expect(find.text('ABCD1234'), findsOneWidget);
      expect(repo.inviteCodeReads, ['g-1']);

      await tester.tap(find.byKey(const Key('invite_copy')));
      await tester.pumpAndSettle();
      expect(clipboard, ['ABCD1234'], reason: 'copies the loaded code');
      expect(find.text('Invite code copied.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('invite_rotate')));
      await tester.pumpAndSettle();
      expect(find.text('Rotate invite code?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm_rotate')));
      await tester.pumpAndSettle();
      expect(find.text('ROT00001'), findsOneWidget);
      expect(find.text('ABCD1234'), findsNothing);
      expect(find.byKey(const Key('invite_rotated')), findsOneWidget);
      expect(repo.calls, contains('rotate:g-1'));

      await tester.pumpWidget(const SizedBox());
      c.dispose();
      invite.dispose();
    });

    testWidgets(
      'settings: load failure shows retry; rotation failure shows error',
      (tester) async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-me', inviteCode: 'ABCD1234');
        final c = _hub(repo);
        final invite = InviteCodeController(groupId: 'g-1', repository: repo);
        repo.failNextWith = const DataError(message: 'Network error.');
        await pumpTall(
          tester,
          GroupSettingsScreen(
            groupId: 'g-1',
            controller: c,
            inviteCodeController: invite,
          ),
        );
        // The first failing call is the group load itself? No — the hub load
        // does not use failNextWith; the invite read consumed it.
        expect(find.byKey(const Key('invite_retry')), findsOneWidget);
        expect(find.byKey(const Key('invite_code_value')), findsNothing);
        await tester.tap(find.byKey(const Key('invite_retry')));
        await tester.pumpAndSettle();
        expect(find.text('ABCD1234'), findsOneWidget);

        repo.failNextWith = const DataError(message: 'Network error.');
        await tester.tap(find.byKey(const Key('invite_rotate')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm_rotate')));
        await tester.pumpAndSettle();
        expect(find.text('ABCD1234'), findsOneWidget, reason: 'old code kept');
        expect(find.byKey(const Key('invite_error')), findsOneWidget);
        expect(find.byKey(const Key('invite_rotated')), findsNothing);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
        invite.dispose();
      },
    );
  });
}

class _SlowRotateRepository extends InMemoryGroupRepository {
  @override
  Future<String> rotateInviteCode(String groupId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.rotateInviteCode(groupId);
  }
}
