// G2 — Group profile + basic settings + logo (display / remove).
// Logo upload/replace is intentionally absent: no group-scoped storage
// policy exists live (see the G2 report), so nothing here pretends one does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/features/group/domain/group_privacy.dart';
import 'package:my_praperation/features/group/screens/group_info_screen.dart';
import 'package:my_praperation/features/group/screens/group_settings_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/widgets/group_avatar.dart';

import 'fakes.dart';

/// The settings form is longer than the default 600 px test surface; a lazy
/// ListView never builds the Save button there, so widget tests use a taller
/// phone-sized view.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

void main() {
  group('Settings permission (server probe)', () {
    test('owner may edit (fn_has_permission owner branch)', () async {
      final repo = InMemoryGroupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await c.load();
      expect(c.canEditBasics, isTrue);
      c.dispose();
    });

    test('leader may NOT edit unless GROUP_SETTINGS was granted', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'leader'});
      final c = _hub(repo);
      await c.load();
      expect(c.canEditBasics, isFalse, reason: 'GROUP_SETTINGS is not seeded');
      c.dispose();

      repo.settingsGrant.add('g-1:u-me');
      final c2 = _hub(repo);
      await c2.load();
      expect(c2.canEditBasics, isTrue, reason: 'explicit role_permissions row');
      c2.dispose();
    });

    test('member may not edit; public readability grants nothing', () async {
      final repo = InMemoryGroupRepository()
        ..seed(
          id: 'g-1',
          ownerId: 'u-owner',
          privacy: 'public',
          members: {'u-me': 'member'},
        );
      final c = _hub(repo);
      await c.load();
      expect(c.canEditBasics, isFalse);
      expect(await c.updateBasics(name: 'Hijack'), isFalse);
      expect(c.error, contains('permission'));
      expect(repo.groups['g-1']!.name, 'Physics Group');
      c.dispose();
    });
  });

  group('Basic update', () {
    test(
      'validation: empty / whitespace / >80 rejected before the server',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-me');
        final c = _hub(repo);
        await c.load();
        expect(await c.updateBasics(name: ''), isFalse);
        expect(await c.updateBasics(name: '   '), isFalse);
        expect(await c.updateBasics(name: 'x' * 81), isFalse);
        expect(repo.calls.where((x) => x.startsWith('updateBasics')), isEmpty);
        c.dispose();
      },
    );

    test(
      'successful update trims, sets privacy, and reloads the hub',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-me');
        final c = _hub(repo);
        await c.load();
        final ok = await c.updateBasics(
          name: '  Chemistry  ',
          description: '  Class 11  ',
          privacy: GroupPrivacy.restricted,
        );
        expect(ok, isTrue);
        expect(c.group!.name, 'Chemistry');
        expect(c.group!.description, 'Class 11');
        expect(c.privacy, GroupPrivacy.restricted);
        expect(c.error, isNull);
        c.dispose();
      },
    );

    test('privacy omitted → unchanged; every live value round-trips', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', privacy: 'private');
      final c = _hub(repo);
      await c.load();
      expect(await c.updateBasics(name: 'A'), isTrue);
      expect(c.privacy, GroupPrivacy.private);
      for (final p in GroupPrivacy.values) {
        expect(await c.updateBasics(name: 'A', privacy: p), isTrue);
        expect(c.privacy, p);
        expect(GroupPrivacy.fromDb(p.db), p);
      }
      c.dispose();
    });

    test(
      'backend failure surfaces the message and keeps the old values',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-me');
        final c = _hub(repo);
        await c.load();
        repo.failNextWith = const DataError(message: 'Network error.');
        expect(await c.updateBasics(name: 'New'), isFalse);
        expect(c.error, 'Network error.');
        expect(c.group!.name, 'Physics Group');
        expect(c.isBusy, isFalse);
        c.dispose();
      },
    );

    test('a second save while one is in flight is dropped', () async {
      final repo = _SlowUpdateRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await c.load();
      final first = c.updateBasics(name: 'One');
      final second = c.updateBasics(name: 'Two');
      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(repo.updateCalls, 1);
      expect(c.group!.name, 'One');
      c.dispose();
    });
  });

  group('Logo', () {
    test(
      'clearLogo nulls logo_url and refreshes; refused without permission',
      () async {
        final repo = InMemoryGroupRepository()
          ..seed(id: 'g-1', ownerId: 'u-me', logoUrl: 'https://x/logo.png');
        final c = _hub(repo);
        await c.load();
        expect(c.group!.logoUrl, isNotNull);
        expect(await c.clearLogo(), isTrue);
        expect(c.group!.logoUrl, isNull);
        c.dispose();

        final repo2 = InMemoryGroupRepository()
          ..seed(
            id: 'g-1',
            ownerId: 'u-owner',
            logoUrl: 'https://x/logo.png',
            members: {'u-me': 'member'},
          );
        final c2 = _hub(repo2);
        await c2.load();
        expect(await c2.clearLogo(), isFalse);
        expect(c2.error, contains('permission'));
        expect(repo2.groups['g-1']!.logoUrl, isNotNull);
        c2.dispose();
      },
    );

    test('clearLogo failure is surfaced and recoverable', () async {
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', logoUrl: 'https://x/logo.png');
      final c = _hub(repo);
      await c.load();
      repo.failNextWith = const DataError(message: 'Network error.');
      expect(await c.clearLogo(), isFalse);
      expect(c.error, 'Network error.');
      expect(c.group!.logoUrl, isNotNull, reason: 'nothing changed');
      expect(await c.clearLogo(), isTrue, reason: 'retry works');
      c.dispose();
    });

    testWidgets('GroupAvatar: no url → initial; invalid url → initial', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GroupAvatar(name: 'physics')),
        ),
      );
      expect(find.byKey(const Key('group_avatar_initial')), findsOneWidget);
      expect(find.text('P'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GroupAvatar(
              name: 'physics',
              logoUrl: 'https://invalid.local/x.png',
            ),
          ),
        ),
      );
      // Network images fail in tests; the error builder must fall back.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('group_avatar_logo')), findsOneWidget);
      expect(find.text('P'), findsOneWidget);
    });
  });

  group('Screens', () {
    testWidgets('settings: forbidden for a member, editable for the owner', (
      tester,
    ) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final member = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupSettingsScreen(groupId: 'g-1', controller: member),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_forbidden')), findsOneWidget);
      expect(find.byKey(const Key('settings_save')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      member.dispose();

      repo.currentUser = 'u-owner';
      final owner = _hub(repo, user: 'u-owner');
      await tester.pumpWidget(
        MaterialApp(
          home: GroupSettingsScreen(groupId: 'g-1', controller: owner),
        ),
      );
      await tester.pumpAndSettle();
      // The sticky save bar only appears once there's something to save.
      expect(find.byKey(const Key('settings_save')), findsNothing);
      expect(find.byKey(const Key('settings_name_field')), findsOneWidget);
      // Seeded from the loaded group.
      expect(find.text('Physics Group'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('settings_name_field')),
        'Physics Group Renamed',
      );
      await tester.pump();
      expect(find.byKey(const Key('settings_save')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
    });

    testWidgets('settings: validation, save, success state, no double submit', (
      tester,
    ) async {
      _tallView(tester);
      final repo = _SlowUpdateRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupSettingsScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('settings_name_field')),
        '  ',
      );
      await tester.pump(); // sticky save bar appears once dirty
      await tester.tap(find.byKey(const Key('settings_save')));
      await tester.pumpAndSettle();
      expect(find.text('Group name is required.'), findsOneWidget);
      expect(repo.updateCalls, 0);

      await tester.enterText(
        find.byKey(const Key('settings_name_field')),
        'Renamed',
      );
      await tester.tap(find.byKey(const Key('settings_privacy_restricted')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_save')));
      await tester.pump(); // in flight
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('settings_save')),
        warnIfMissed: false,
      ); // disabled
      await tester.pumpAndSettle();
      expect(repo.updateCalls, 1);
      expect(find.byKey(const Key('settings_saved')), findsOneWidget);
      expect(repo.groups['g-1']!.name, 'Renamed');
      expect(repo.groups['g-1']!.privacy, 'restricted');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('settings: backend error shown; remove logo flow', (
      tester,
    ) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-me', logoUrl: 'https://x/logo.png');
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupSettingsScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('remove_logo_button')), findsOneWidget);

      repo.failNextWith = const DataError(message: 'Network error.');
      await tester.enterText(
        find.byKey(const Key('settings_name_field')),
        'Renamed',
      );
      await tester.pump(); // sticky save bar appears once dirty
      await tester.tap(find.byKey(const Key('settings_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_error')), findsOneWidget);
      expect(find.text('Network error.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove_logo_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_remove_logo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('remove_logo_button')), findsNothing);
      expect(repo.groups['g-1']!.logoUrl, isNull);
      // Stale: this used to assert a "no storage policy" disclaimer from
      // before logo upload existed. Upload is implemented now (camera/
      // gallery via _pickAndUploadAvatar, group-avatars bucket with a
      // fallback to avatars) — there is no such disclaimer to show.
      expect(find.byKey(const Key('logo_status')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('hub: settings entry only when authorised; refresh on return', (
      tester,
    ) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      final router = GoRouter(
        initialLocation: '/groups/g-1',
        routes: [
          GoRoute(
            path: '/groups/:groupId',
            builder: (_, _) => GroupInfoScreen(groupId: 'g-1', controller: c),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, _) =>
                    GroupSettingsScreen(groupId: 'g-1', controller: c),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group_info_settings_action_row')), findsOneWidget);
      expect(find.text('Physics Group'), findsWidgets);

      await tester.tap(find.byKey(const Key('group_info_settings_action_row')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('settings_name_field')),
        'Renamed',
      );
      await tester.pump(); // sticky save bar appears once dirty
      await tester.tap(find.byKey(const Key('settings_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to group'));
      await tester.pumpAndSettle();

      expect(find.text('Renamed'), findsWidgets, reason: 'no stale header');
      expect(find.text('Physics Group'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('hub: member sees profile but no settings entry', (
      tester,
    ) async {
      final repo = InMemoryGroupRepository()
        ..seed(
          id: 'g-1',
          ownerId: 'u-owner',
          privacy: 'public',
          members: {'u-me': 'member'},
        );
      final c = _hub(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group_header_meta')), findsOneWidget);
      expect(find.text('2 members · Member · Public'), findsOneWidget);
      expect(find.byKey(const Key('group_info_settings_action_row')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
  // G13's old "Rules summary" (3-line condensed preview linking to the
  // hub) and "Members summary" cards no longer exist on Settings — Phase 2
  // replaced the rules preview with the full GroupRulesSection editor
  // (already covered by test/group/group_rules_test.dart) and moved
  // member management entirely onto the Info screen's Members section.
  group('G13 — Leave section (now in the Danger Zone)', () {
    testWidgets('owner sees Transfer/Delete, never a Leave button or blocked text', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await c.load();

      await tester.pumpWidget(
        MaterialApp(home: GroupSettingsScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_leave_section')), findsOneWidget);
      expect(find.byKey(const Key('settings_leave_button')), findsNothing);
      expect(find.byKey(const Key('settings_leave_blocked')), findsNothing);
      expect(find.byKey(const Key('settings_transfer_ownership_button')), findsOneWidget);
      expect(find.byKey(const Key('delete_group_button')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('non-owner sees leave button and can leave', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.settingsGrant.add('g-1:u-me');
      final c = _hub(repo, user: 'u-me');
      await c.load();

      final router = GoRouter(
        initialLocation: '/groups/g-1/settings',
        routes: [
          GoRoute(
            path: '/groups',
            builder: (_, _) => const Scaffold(body: Text('Groups list')),
          ),
          GoRoute(
            path: '/groups/:groupId/settings',
            builder: (_, _) =>
                GroupSettingsScreen(groupId: 'g-1', controller: c),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_leave_button')), findsOneWidget);
      expect(find.byKey(const Key('settings_leave_blocked')), findsNothing);

      await tester.tap(find.byKey(const Key('settings_leave_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm_leave')), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_leave')));
      await tester.pumpAndSettle();

      expect(find.text('Groups list'), findsOneWidget);

      router.dispose();
      c.dispose();
    });

    testWidgets('leave cancelled does nothing', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.settingsGrant.add('g-1:u-me');
      final c = _hub(repo, user: 'u-me');
      await c.load();

      await tester.pumpWidget(
        MaterialApp(home: GroupSettingsScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_leave_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Still on settings screen
      expect(find.byKey(const Key('settings_leave_button')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('Phase 3A finish-up — report moderation (0120)', () {
    InMemoryGroupRepository repoWith({
      Map<String, String> members = const {},
      String user = 'u-me',
    }) => InMemoryGroupRepository(currentUser: user)
      ..seed(id: 'g-1', ownerId: 'u-owner', members: members);

    group('controller', () {
      test('canModerateReports: owner/admin only', () async {
        final memberRepo = repoWith(members: {'u-me': 'member'});
        final memberC = _hub(memberRepo);
        await memberC.load();
        expect(memberC.canModerateReports, isFalse);

        final adminRepo = repoWith(members: {'u-me': 'admin'});
        final adminC = _hub(adminRepo);
        await adminC.load();
        expect(adminC.canModerateReports, isTrue);

        final ownerRepo = repoWith(user: 'u-owner');
        final ownerC = _hub(ownerRepo, user: 'u-owner');
        await ownerC.load();
        expect(ownerC.canModerateReports, isTrue);
      });

      test('a plain member never loads reports; admin does', () async {
        final repo = repoWith(members: {'u-me': 'member', 'u-reporter': 'member'});
        final msg = repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'reportable');
        repo.currentUser = 'u-reporter';
        await repo.reportMessage(messageId: msg.id, reason: 'spam');

        repo.currentUser = 'u-me';
        final memberC = _hub(repo);
        await memberC.load();
        expect(memberC.messageReports, isEmpty);
        expect(memberC.pendingReportCount, 0);
        expect(repo.calls.any((x) => x.startsWith('messageReports')), isFalse);

        final adminRepo = repoWith(members: {'u-me': 'admin', 'u-reporter': 'member'});
        final msg2 = adminRepo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'reportable 2');
        adminRepo.currentUser = 'u-reporter';
        await adminRepo.reportMessage(messageId: msg2.id, reason: 'abuse');
        adminRepo.currentUser = 'u-me';
        final adminC = _hub(adminRepo);
        await adminC.load();
        expect(adminC.pendingReportCount, 1);
        expect(adminC.messageReports.single.messageId, msg2.id);
        expect(adminC.messageReports.single.topReason, 'abuse');
      });

      test('dismissReports clears the report and removes it from the list', () async {
        final repo = repoWith(members: {'u-admin': 'admin', 'u-reporter': 'member'});
        final msg = repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'reportable');
        repo.currentUser = 'u-reporter';
        await repo.reportMessage(messageId: msg.id, reason: 'spam');
        repo.currentUser = 'u-admin';
        final c = _hub(repo, user: 'u-admin');
        await c.load();
        expect(c.pendingReportCount, 1);

        expect(await c.dismissReports(c.messageReports.single), isTrue);
        expect(c.messageReports, isEmpty);
        expect(repo.rawMessageReports, isEmpty);
      });

      test('deleteReportedMessage deletes the message and dismisses its reports', () async {
        final repo = repoWith(members: {'u-admin': 'admin', 'u-reporter': 'member'});
        final msg = repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'reportable');
        repo.currentUser = 'u-reporter';
        await repo.reportMessage(messageId: msg.id, reason: 'spam');
        repo.currentUser = 'u-admin';
        final c = _hub(repo, user: 'u-admin');
        await c.load();

        expect(await c.deleteReportedMessage(c.messageReports.single), isTrue);
        expect(c.messageReports, isEmpty);
        expect(
          repo.groups['g-1']!.messages.firstWhere((m) => m.id == msg.id).isDeleted,
          isTrue,
        );
      });
    });

    group('widget', () {
      Future<GroupHubController> pumpSettings(
        WidgetTester tester,
        InMemoryGroupRepository repo, {
        String user = 'u-me',
      }) async {
        _tallView(tester);
        final c = _hub(repo, user: user);
        await tester.pumpWidget(
          MaterialApp(home: GroupSettingsScreen(groupId: 'g-1', controller: c)),
        );
        await tester.pumpAndSettle();
        return c;
      }

      testWidgets('member never sees the reports card', (tester) async {
        final repo = repoWith(members: {'u-me': 'member'});
        final c = await pumpSettings(tester, repo);
        expect(find.byKey(const Key('settings_reports_card')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets('admin sees the empty state when there are no reports', (
        tester,
      ) async {
        final repo = repoWith(members: {'u-me': 'admin'});
        final c = await pumpSettings(tester, repo);
        expect(find.byKey(const Key('settings_reports_card')), findsOneWidget);
        expect(find.byKey(const Key('reports_empty')), findsOneWidget);
        expect(find.byKey(const Key('reports_pending_badge')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });

      testWidgets(
        'admin sees a grouped report tile; Dismiss removes it',
        (tester) async {
          final repo = repoWith(members: {'u-me': 'admin', 'u-reporter': 'member'});
          final msg = repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'be nice');
          repo.currentUser = 'u-reporter';
          await repo.reportMessage(messageId: msg.id, reason: 'spam');
          repo.currentUser = 'u-me';

          final c = await pumpSettings(tester, repo);
          expect(find.byKey(const Key('reports_pending_badge')), findsOneWidget);
          expect(find.text('be nice'), findsOneWidget);
          expect(find.textContaining('Spam'), findsOneWidget);

          await tester.tap(find.byKey(Key('dismiss_reports_${msg.id}')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(Key('confirm_dismiss_${msg.id}')));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('reports_empty')), findsOneWidget);
          expect(c.pendingReportCount, 0);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );

      testWidgets(
        'Delete message removes the message and clears the report tile',
        (tester) async {
          final repo = repoWith(members: {'u-me': 'admin', 'u-reporter': 'member'});
          final msg = repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'spam content');
          repo.currentUser = 'u-reporter';
          await repo.reportMessage(messageId: msg.id, reason: 'spam');
          repo.currentUser = 'u-me';

          await pumpSettings(tester, repo);
          await tester.tap(find.byKey(Key('delete_reported_message_${msg.id}')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(Key('confirm_delete_reported_${msg.id}')));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('reports_empty')), findsOneWidget);
          expect(
            repo.groups['g-1']!.messages.firstWhere((m) => m.id == msg.id).isDeleted,
            isTrue,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        'Remove member removes the sender from the group',
        (tester) async {
          final repo = repoWith(
            members: {'u-me': 'admin', 'u-sender': 'member', 'u-reporter': 'member'},
          );
          final msg = repo.seedMessage(groupId: 'g-1', senderId: 'u-sender', body: 'offensive');
          repo.currentUser = 'u-reporter';
          await repo.reportMessage(messageId: msg.id, reason: 'abuse');
          repo.currentUser = 'u-me';

          await pumpSettings(tester, repo);
          await tester.tap(find.byKey(Key('remove_reported_member_${msg.id}')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(Key('confirm_remove_reported_${msg.id}')));
          await tester.pumpAndSettle();

          expect(repo.groups['g-1']!.roles.containsKey('u-sender'), isFalse);
          await tester.pumpWidget(const SizedBox());
        },
      );
    });
  });
}

class _SlowUpdateRepository extends InMemoryGroupRepository {
  int updateCalls = 0;

  @override
  Future<void> updateBasics({
    required String groupId,
    required String name,
    required String description,
    String? privacy,
  }) async {
    updateCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.updateBasics(
      groupId: groupId,
      name: name,
      description: description,
      privacy: privacy,
    );
  }
}
