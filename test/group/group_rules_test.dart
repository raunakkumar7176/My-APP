// G6 — Group Rules on the proposed contract (migrations/G6_GROUP_RULES.sql):
//   group_rules(id, group_id → groups, rule_text 1..2000, position,
//   created_at, updated_at); SELECT fn_is_member; INSERT/UPDATE/DELETE
//   GROUP_SETTINGS OR owner (= the live groups UPDATE gate, `canEditBasics`).
// The fake mirrors those policies; no role name is ever consulted in the UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group_rule.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/widgets/group_rules_section.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

/// g-1 owned by u-owner with leader u-lead, moderator u-mod, member u-me;
/// two rules. g-2 owned by u-other (u-me is not a member) with one rule.
InMemoryGroupRepository _repo({String user = 'u-me'}) {
  final repo = InMemoryGroupRepository(currentUser: user)
    ..seed(
      id: 'g-1',
      name: 'Physics',
      ownerId: 'u-owner',
      members: {'u-lead': 'leader', 'u-mod': 'moderator', 'u-me': 'member'},
    )
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  final t = DateTime(2026, 9, 1, 10);
  repo.groups['g-1']!.rules.addAll([
    GroupRule(
      id: 'r-2',
      groupId: 'g-1',
      ruleText: 'Second rule',
      position: 1,
      createdAt: t,
      updatedAt: t,
    ),
    GroupRule(
      id: 'r-1',
      groupId: 'g-1',
      ruleText: 'First rule',
      position: 0,
      createdAt: t,
      updatedAt: t,
    ),
  ]);
  repo.groups['g-2']!.rules.add(
    GroupRule(
      id: 'r-g2',
      groupId: 'g-2',
      ruleText: 'Foreign rule',
      position: 0,
      createdAt: t,
      updatedAt: t,
    ),
  );
  return repo;
}

void main() {
  group('TEST 1 — model parsing', () {
    test('fromJson maps the six live columns; position null-safe', () {
      final r = GroupRule.fromJson({
        'id': 'r-1',
        'group_id': 'g-1',
        'rule_text': 'Be kind',
        'position': 3,
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-02T10:00:00Z',
      });
      expect(r.id, 'r-1');
      expect(r.groupId, 'g-1');
      expect(r.ruleText, 'Be kind');
      expect(r.position, 3);
      expect(r.createdAt.toUtc(), DateTime.utc(2026, 9, 1, 10));
      expect(r.updatedAt.toUtc(), DateTime.utc(2026, 9, 2, 10));
      final noPos = GroupRule.fromJson({
        'id': 'r-2',
        'group_id': 'g-1',
        'rule_text': 'x',
        'position': null,
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-01T10:00:00Z',
      });
      expect(noPos.position, 0);
      expect(r.toJson()['rule_text'], 'Be kind');
      expect(r.copyWith(ruleText: 'New').ruleText, 'New');
      expect(r.copyWith(ruleText: 'New').id, r.id);
    });
  });

  group('TEST 2/3 — read', () {
    test('member reads only this group, ordered by position', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(c.rulesError, isNull);
      expect(c.rules.map((r) => r.id).toList(), ['r-1', 'r-2']);
      expect(c.rules.every((r) => r.groupId == 'g-1'), isTrue);
      expect(c.hasRules, isTrue);
    });

    test('non-member gets no rows (fn_is_member gate)', () async {
      final repo = _repo(user: 'u-stranger');
      final c = GroupHubController(
        groupId: 'g-2',
        repository: repo,
        currentUserId: 'u-stranger',
      );
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(await repo.groupRules('g-2'), isEmpty);
      expect(await repo.groupRules('g-1'), isEmpty);
    });

    test('empty state: loaded, no error, no rules', () async {
      final repo = _repo();
      repo.groups['g-1']!.rules.clear();
      final c = _hub(repo);
      await c.load();
      expect(c.rulesLoading, isFalse);
      expect(c.rulesError, isNull);
      expect(c.rules, isEmpty);
      expect(c.hasRules, isFalse);
    });
  });

  group('TEST 4 — error + retry', () {
    test('load error surfaces rulesError; retry recovers', () async {
      final repo = _FailingRulesRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.group, isNotNull, reason: 'a rules failure never blocks the hub');
      expect(c.rulesError, 'Network error.');
      expect(c.rules, isEmpty);
      repo.failReads = false;
      await c.retryRules();
      expect(c.rulesError, isNull);
    });
  });

  group('TEST 5/6/7 — owner and GROUP_SETTINGS holder mutate', () {
    test('owner create → trimmed, appended, re-read', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      expect(c.canEditBasics, isTrue);
      expect(await c.createRule('  Third rule  '), isTrue);
      expect(c.rules.length, 3);
      expect(c.rules.last.ruleText, 'Third rule');
      expect(c.rules.last.position, 2);
      expect(c.error, isNull);
      expect(repo.calls.where((x) => x == 'createRule:g-1').length, 1);
    });

    test('owner update → text changed, re-read', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      final r = c.rules.first;
      expect(await c.updateRule(r, ' Updated '), isTrue);
      expect(c.rules.firstWhere((x) => x.id == r.id).ruleText, 'Updated');
      expect(c.actingRuleId, isNull);
      expect(c.rulesSaving, isFalse);
    });

    test('owner delete → row gone, re-read', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      expect(await c.deleteRule(c.rules.first), isTrue);
      expect(c.rules.map((r) => r.id), ['r-2']);
      expect(repo.groups['g-1']!.rules.length, 1);
    });

    test('explicit GROUP_SETTINGS grant (non-owner) may mutate', () async {
      final repo = _repo(user: 'u-mod');
      repo.settingsGrant.add('g-1:u-mod');
      final c = _hub(repo, user: 'u-mod');
      await c.load();
      expect(c.isOwner, isFalse);
      expect(c.canEditBasics, isTrue);
      expect(await c.createRule('Mod rule'), isTrue);
      expect(c.rules.length, 3);
    });

    test('create/update reject empty or whitespace text', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      expect(await c.createRule('   '), isFalse);
      expect(c.error, 'Rule text cannot be empty.');
      expect(await c.updateRule(c.rules.first, ''), isFalse);
      expect(c.error, 'Rule text cannot be empty.');
      expect(repo.calls.any((x) => x.startsWith('createRule')), isFalse);
      expect(repo.calls.any((x) => x.startsWith('updateRule')), isFalse);
      expect(c.rules.length, 2);
    });
  });

  group('TEST 8/9 — unauthorized mutation (member, leader, moderator)', () {
    for (final user in ['u-me', 'u-lead', 'u-mod']) {
      test('$user: controller refuses and server refuses; nothing changes', () async {
        final repo = _repo(user: user);
        final c = _hub(repo, user: user);
        await c.load();
        expect(
          c.canEditBasics,
          isFalse,
          reason: 'GROUP_SETTINGS is seeded for no role',
        );
        final before = List.of(repo.groups['g-1']!.rules);

        expect(await c.createRule('Sneaky'), isFalse);
        expect(c.error, contains('permission'));
        expect(await c.updateRule(c.rules.first, 'Sneaky'), isFalse);
        expect(await c.deleteRule(c.rules.first), isFalse);
        expect(repo.groups['g-1']!.rules, before);

        // Bypass the UI guard: the (fake) server policy still refuses.
        await expectLater(
          repo.createRule(groupId: 'g-1', ruleText: 'Direct'),
          throwsA(isA<DataError>()),
        );
        await expectLater(
          repo.updateRule(ruleId: 'r-1', ruleText: 'Direct'),
          throwsA(isA<DataError>()),
        );
        await expectLater(repo.deleteRule('r-1'), throwsA(isA<DataError>()));
        expect(repo.groups['g-1']!.rules, before);
      });
    }

    test('owner of g-1 cannot touch a forged rule id from g-2', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      final foreign = repo.groups['g-2']!.rules.first;
      expect(await c.updateRule(foreign, 'Hijack'), isFalse);
      expect(c.error, contains('could not be updated'));
      expect(await c.deleteRule(foreign), isFalse);
      expect(c.error, contains('could not be deleted'));
      expect(repo.groups['g-2']!.rules.single.ruleText, 'Foreign rule');
      expect(c.rules.length, 2, reason: 're-read after failure keeps own list');
    });

    test('server rejection is mapped and the list is re-read', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      repo.failNextWith = const DataError(message: 'row-level security');
      expect(await c.createRule('Blocked'), isFalse);
      expect(c.error, 'row-level security');
      expect(c.rules.length, 2);
      expect(c.rulesSaving, isFalse);
    });
  });

  group('TEST 10 — single-flight', () {
    test('second create while first in flight is dropped', () async {
      final repo = _SlowRulesRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      final first = c.createRule('One');
      expect(c.rulesSaving, isTrue);
      expect(await c.createRule('Two'), isFalse);
      expect(await first, isTrue);
      expect(c.rules.map((r) => r.ruleText), ['One']);
      expect(repo.calls.where((x) => x == 'createRule:g-1').length, 1);
    });

    test('delete twice on the same rule runs once', () async {
      final repo = _SlowRulesRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      await c.createRule('One');
      final r = c.rules.single;
      final first = c.deleteRule(r);
      expect(c.actingRuleId, r.id);
      expect(await c.deleteRule(r), isFalse);
      expect(await first, isTrue);
      expect(c.rules, isEmpty);
      expect(repo.calls.where((x) => x.startsWith('deleteRule')).length, 1);
    });
  });

  group('TEST 11/12 — hub widget', () {
    Future<GroupHubController> pump(
      WidgetTester tester,
      InMemoryGroupRepository repo, {
      String user = 'u-me',
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _hub(repo, user: user);
      await tester.pumpWidget(
        MaterialApp(home: GroupHubScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('member: read-only — rules shown, no controls', (tester) async {
      final c = await pump(tester, _repo());
      expect(find.byKey(const Key('group_rules_section')), findsOneWidget);
      expect(find.byKey(const Key('rule_r-1')), findsOneWidget);
      expect(find.byKey(const Key('rule_r-2')), findsOneWidget);
      expect(find.text('First rule'), findsOneWidget);
      expect(find.byKey(const Key('add_rule_button')), findsNothing);
      expect(find.byKey(const Key('edit_rule_r-1')), findsNothing);
      expect(find.byKey(const Key('delete_rule_r-1')), findsNothing);
      // Hub regression: roster and leave still render around the section.
      expect(find.byKey(const Key('hub_members_heading')), findsOneWidget);
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('leader (MANAGE_MEMBERS, no GROUP_SETTINGS): read-only', (
      tester,
    ) async {
      final c = await pump(tester, _repo(user: 'u-lead'), user: 'u-lead');
      expect(c.canManageMembers, isTrue);
      expect(find.byKey(const Key('add_rule_button')), findsNothing);
      expect(find.byKey(const Key('edit_rule_r-1')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('empty state for member', (tester) async {
      final repo = _repo();
      repo.groups['g-1']!.rules.clear();
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('rules_empty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('error + retry', (tester) async {
      final repo = _FailingRulesRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final t = DateTime(2026, 9, 1);
      repo.groups['g-1']!.rules.add(
        GroupRule(
          id: 'r-x',
          groupId: 'g-1',
          ruleText: 'Recovered',
          position: 0,
          createdAt: t,
          updatedAt: t,
        ),
      );
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('rules_error')), findsOneWidget);
      repo.failReads = false;
      await tester.tap(find.byKey(const Key('rules_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rule_r-x')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('owner: add → edit → delete with confirmation, list refreshes', (
      tester,
    ) async {
      final repo = _repo(user: 'u-owner');
      final c = await pump(tester, repo, user: 'u-owner');
      expect(find.byKey(const Key('add_rule_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_rule_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new_rule_field')), ' Third ');
      await tester.tap(find.byKey(const Key('confirm_add_rule')));
      await tester.pumpAndSettle();
      expect(c.rules.length, 3);
      expect(find.text('Third'), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit_rule_r-1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('edit_rule_field')), 'Edited');
      await tester.tap(find.byKey(const Key('confirm_edit_rule')));
      await tester.pumpAndSettle();
      expect(find.text('Edited'), findsOneWidget);
      expect(find.text('First rule'), findsNothing);

      await tester.tap(find.byKey(const Key('delete_rule_r-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm_delete_rule')), findsOneWidget);
      expect(c.rules.length, 3, reason: 'nothing deleted before confirmation');
      await tester.tap(find.byKey(const Key('confirm_delete_rule')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rule_r-2')), findsNothing);
      expect(c.rules.length, 2);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('owner: empty add is rejected without a server call', (
      tester,
    ) async {
      final repo = _repo(user: 'u-owner');
      final c = await pump(tester, repo, user: 'u-owner');
      await tester.tap(find.byKey(const Key('add_rule_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new_rule_field')), '   ');
      await tester.tap(find.byKey(const Key('confirm_add_rule')));
      await tester.pumpAndSettle();
      expect(c.rules.length, 2);
      expect(repo.calls.any((x) => x.startsWith('createRule')), isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('section uses the hub controller, not a second source', (
      tester,
    ) async {
      final c = await pump(tester, _repo());
      final section = tester.widget<GroupRulesSection>(
        find.byType(GroupRulesSection),
      );
      expect(identical(section.controller, c), isTrue);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

class _FailingRulesRepository extends InMemoryGroupRepository {
  _FailingRulesRepository() : super(currentUser: 'u-me');
  bool failReads = true;
  @override
  Future<List<GroupRule>> groupRules(String groupId) async {
    if (failReads) throw const DataError(message: 'Network error.');
    return super.groupRules(groupId);
  }
}

class _SlowRulesRepository extends InMemoryGroupRepository {
  _SlowRulesRepository() : super(currentUser: 'u-owner');
  @override
  Future<void> createRule({
    required String groupId,
    required String ruleText,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.createRule(groupId: groupId, ruleText: ruleText);
  }

  @override
  Future<void> deleteRule(String ruleId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.deleteRule(ruleId);
  }
}
