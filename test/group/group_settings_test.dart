// G2 — Group profile + basic settings + logo (display / remove).
// Logo upload/replace is intentionally absent: no group-scoped storage
// policy exists live (see the G2 report), so nothing here pretends one does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group_rule.dart';
import 'package:my_praperation/features/group/domain/group_privacy.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/screens/group_settings_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/widgets/group_avatar.dart';

import 'fakes.dart';

/// The settings form is longer than the default 600 px test surface; a lazy
/// ListView never builds the Save button there, so widget tests use a taller
/// phone-sized view.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
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
      expect(find.byKey(const Key('settings_save')), findsOneWidget);
      // Seeded from the loaded group.
      expect(find.text('Physics Group'), findsOneWidget);
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
      expect(
        find.textContaining('storage policy'),
        findsOneWidget,
        reason: 'upload is truthfully reported as unavailable',
      );

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
            builder: (_, _) => GroupHubScreen(groupId: 'g-1', controller: c),
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
      expect(find.byKey(const Key('group_settings_action')), findsOneWidget);
      expect(find.text('Physics Group'), findsWidgets);

      await tester.tap(find.byKey(const Key('group_settings_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('settings_name_field')),
        'Renamed',
      );
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
          home: GroupHubScreen(groupId: 'g-1', controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group_header_meta')), findsOneWidget);
      expect(find.text('2 members · Member · Public'), findsOneWidget);
      expect(find.byKey(const Key('group_settings_action')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
  group('G13 — Rules summary', () {
    testWidgets('shows rules count and first 3 rules', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await c.load();
      // Seed 5 rules
      for (var i = 1; i <= 5; i++) {
        repo.groups['g-1']!.rules.add(
          GroupRule(
            id: 'rule-$i',
            groupId: 'g-1',
            ruleText: 'Rule $i text',
            position: i,
            createdAt: DateTime(2026, 9, i),
            updatedAt: DateTime(2026, 9, i),
          ),
        );
      }
      await c.retryRules();

      await tester.pumpWidget(
        MaterialApp(home: GroupSettingsScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_rules_summary')), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Rule 1 text'), findsOneWidget);
      expect(find.text('Rule 2 text'), findsOneWidget);
      expect(find.text('Rule 3 text'), findsOneWidget);
      expect(find.text('+2 more'), findsOneWidget);
      expect(find.byKey(const Key('settings_manage_rules')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('empty rules shows no-rules message', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()..seed(id: 'g-1', ownerId: 'u-me');
      final c = _hub(repo);
      await c.load();

      await tester.pumpWidget(
        MaterialApp(home: GroupSettingsScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_rules_empty')), findsOneWidget);
      expect(find.text('No rules yet.'), findsOneWidget);
      expect(find.byKey(const Key('settings_manage_rules')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('G13 — Members summary', () {
    testWidgets('shows member count and role', (tester) async {
      _tallView(tester);
      final repo = InMemoryGroupRepository()..seed(
        id: 'g-1',
        ownerId: 'u-me',
        members: {'u-2': 'leader', 'u-3': 'member'},
      );
      final c = _hub(repo);
      await c.load();

      await tester.pumpWidget(
        MaterialApp(home: GroupSettingsScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_members_summary')), findsOneWidget);
      expect(find.byKey(const Key('settings_members_count')), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      expect(find.byKey(const Key('settings_my_role')), findsOneWidget);
      expect(find.textContaining('Your role:'), findsOneWidget);
      expect(find.byKey(const Key('settings_manage_members')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('G13 — Leave section', () {
    testWidgets('owner sees blocked message, not leave button', (tester) async {
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
      expect(find.byKey(const Key('settings_leave_blocked')), findsOneWidget);

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
