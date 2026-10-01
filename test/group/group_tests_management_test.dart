// G10 — Group Test Management on the LIVE contract (audited 2026-09-19):
//   tests RLS: `member read tests` (member, not soft-deleted) + `creator sees
//   soft-deleted`; `group create test` INSERT (created_by = uid, test_mode =
//   'group', CREATE_TEST); `group edit test` UPDATE (EDIT_TEST).
//   RPCs: rpc_publish_test (creator + draft), rpc_update_test (creator +
//   draft/published, ends_at > starts_at), rpc_delete_test (creator + draft),
//   fn_soft_delete_test (creator OR owner OR EDIT_TEST; not live/scheduled;
//   → archived + soft-deleted, attempts kept).
// Leader holds CREATE/EDIT/PUBLISH/SCHEDULE_TEST by the live seeding; member
// and moderator hold nothing; the owner passes through the function bypass.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/core/models/test_syllabus.dart';
import 'package:my_praperation/features/group/domain/group_test_management.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/screens/group_tests_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/state/group_tests_controller.dart';
import 'package:my_praperation/features/test/data/test_repository.dart';
import 'package:my_praperation/features/test/state/test_creation_controller.dart';

import '../r4_restart/fakes.dart';
import 'fakes.dart';

final _now = DateTime(2026, 9, 19, 12);

Test _t(
  String id, {
  required String by,
  String? group = 'g-1',
  TestStatus status = TestStatus.draft,
  DateTime? startsAt,
  DateTime? endsAt,
  bool deleted = false,
}) => Test(
  id: id,
  createdBy: by,
  title: 'Test $id',
  status: status,
  testMode: group == null ? 'self' : 'group',
  groupId: group,
  durationSec: 600,
  marksPerQuestion: 1,
  negativeMarks: 0,
  startsAt: startsAt,
  endsAt: endsAt,
  isSoftDeleted: deleted,
);

/// g-1: owner u-owner, leader u-lead, moderator u-mod, member u-me.
/// g-2: owner u-other (nobody from g-1). Tests: t-1 draft (u-lead),
/// t-2 published+future (u-owner), t-3 published+active (u-lead),
/// t-4 ended (u-owner), t-5 archived/soft-deleted (u-lead),
/// t-6 scheduled (u-owner), t-9 draft in g-2 (u-other).
({InMemoryGroupRepository groups, FakeTestRepository tests}) _fixture(
  String user,
) {
  final groups = InMemoryGroupRepository(currentUser: user)
    ..seed(
      id: 'g-1',
      name: 'Physics',
      ownerId: 'u-owner',
      members: {'u-lead': 'leader', 'u-mod': 'moderator', 'u-me': 'member'},
    )
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  final tests = FakeTestRepository()
    ..currentUser = user
    ..groups = groups;
  for (final t in [
    _t('t-1', by: 'u-lead'),
    _t(
      't-2',
      by: 'u-owner',
      status: TestStatus.published,
      startsAt: _now.add(const Duration(days: 1)),
      endsAt: _now.add(const Duration(days: 2)),
    ),
    _t(
      't-3',
      by: 'u-lead',
      status: TestStatus.published,
      startsAt: _now.subtract(const Duration(hours: 1)),
      endsAt: _now.add(const Duration(hours: 1)),
    ),
    _t('t-4', by: 'u-owner', status: TestStatus.ended),
    _t('t-5', by: 'u-lead', status: TestStatus.archived, deleted: true),
    _t('t-6', by: 'u-owner', status: TestStatus.scheduled),
    _t('t-9', by: 'u-other', group: 'g-2'),
  ]) {
    tests.rows[t.id] = t;
  }
  return (groups: groups, tests: tests);
}

GroupTestsController _ctl(
  ({InMemoryGroupRepository groups, FakeTestRepository tests}) f,
  String user, {
  String groupId = 'g-1',
}) => GroupTestsController(
  groupId: groupId,
  tests: f.tests,
  groups: f.groups,
  currentUserId: user,
  now: () => _now,
);

void main() {
  group('1/2 — management list + group scoping', () {
    test('member lists only g-1 tests, in sections, never g-2 or deleted', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.accessDenied, isFalse);
      expect(c.error, isNull);
      expect(c.tests.every((t) => t.groupId == 'g-1'), isTrue);
      expect(c.tests.any((t) => t.id == 't-9'), isFalse);
      expect(c.tests.any((t) => t.id == 't-5'), isFalse, reason: 'soft-deleted hidden from members');
      final s = c.sections;
      expect(s[GroupTestSection.drafts]!.map((t) => t.id), ['t-1']);
      expect(s[GroupTestSection.upcoming]!.map((t) => t.id).toSet(), {'t-2', 't-6'});
      expect(s[GroupTestSection.live]!.map((t) => t.id), ['t-3']);
      expect(s[GroupTestSection.previous]!.map((t) => t.id), ['t-4']);
      expect(s[GroupTestSection.archived], isEmpty);
      expect(f.tests.calls.where((x) => x == 'listForGroup:g-1').length, 1);
    });

    test('creator sees their own archived test in the archived section', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(c.sections[GroupTestSection.archived]!.map((t) => t.id), ['t-5']);
    });

    test('non-member: access denied, nothing listed', () async {
      final f = _fixture('u-stranger');
      final c = _ctl(f, 'u-stranger');
      await c.load();
      expect(c.accessDenied, isTrue);
      expect(c.tests, isEmpty);
      expect(f.tests.calls.any((x) => x.startsWith('listForGroup')), isFalse);
    });

    test('a test of another group cannot be managed from this controller', () async {
      final f = _fixture('u-owner');
      final c = _ctl(f, 'u-owner');
      await c.load();
      final foreign = f.tests.rows['t-9']!;
      expect(await c.publish(foreign), isFalse);
      expect(c.error, contains('does not belong'));
      expect(f.tests.calls.any((x) => x.startsWith('publish')), isFalse);
    });

    test('sectionFor mirrors the live statuses', () {
      expect(
        GroupTestManagement.sectionFor(_t('x', by: 'u', status: TestStatus.cancelled), _now),
        GroupTestSection.archived,
      );
      expect(
        GroupTestManagement.sectionFor(_t('x', by: 'u', status: TestStatus.completed), _now),
        GroupTestSection.previous,
      );
      expect(
        GroupTestManagement.sectionFor(
          _t('x', by: 'u', status: TestStatus.published, endsAt: _now.subtract(const Duration(minutes: 1))),
          _now,
        ),
        GroupTestSection.previous,
      );
      expect(
        GroupTestManagement.sectionFor(_t('x', by: 'u', status: TestStatus.live), _now),
        GroupTestSection.live,
      );
    });
  });

  group('3–6 — draft creation through the R4 wizard, CREATE_TEST, forged group', () {
    TestCreationController wizard(
      ({InMemoryGroupRepository groups, FakeTestRepository tests}) f,
      String user,
    ) => TestCreationController(
      tests: f.tests,
      questions: FakeQuestionRepository(),
      groups: f.groups,
      currentUserId: () => user,
    );

    test('presetGroup opens the wizard as a Group Test for the group', () {
      final f = _fixture('u-lead');
      final c = wizard(f, 'u-lead');
      c.presetGroup('g-1');
      expect(c.kind.requiresGroup, isTrue);
      expect(c.groupId, 'g-1');
    });

    test('leader (CREATE_TEST) creates a group draft; created_by = caller', () async {
      final f = _fixture('u-lead');
      final c = wizard(f, 'u-lead');
      c.presetGroup('g-1');
      c.setTitle('Leader draft');
      c.setConfiguration(
        durationSec: 600,
        marksPerQuestion: 1,
        negativeMarks: 0,
        groupId: 'g-1',
        startsAt: null,
        endsAt: null,
        maxParticipants: null,
        allowLateJoin: false,
        accessCode: null,
        joinCode: null,
      );
      final id = await c.saveDraft();
      final created = f.tests.rows[id]!;
      expect(created.groupId, 'g-1');
      expect(created.testMode, 'group');
      expect(created.createdBy, 'u-lead');
      expect(created.status, TestStatus.draft);
    });

    test('member (no CREATE_TEST) is refused by the server policy', () async {
      final f = _fixture('u-me');
      await expectLater(
        f.tests.create(
          const TestWriteInput(title: 'Sneaky', testMode: 'group', groupId: 'g-1', durationSec: 600),
        ),
        throwsA(isA<DataError>()),
      );
      expect(f.tests.rows.values.any((t) => t.title == 'Sneaky'), isFalse);
    });

    test('forged group_id (a group the leader is not in) is refused', () async {
      final f = _fixture('u-lead');
      await expectLater(
        f.tests.create(
          const TestWriteInput(title: 'Forged', testMode: 'group', groupId: 'g-2', durationSec: 600),
        ),
        throwsA(isA<DataError>()),
      );
      expect(f.tests.rows.values.any((t) => t.groupId == 'g-2' && t.title == 'Forged'), isFalse);
    });

    test('controller exposes canCreateTest only with CREATE_TEST or owner', () async {
      for (final (user, expected) in [('u-owner', true), ('u-lead', true), ('u-mod', false), ('u-me', false)]) {
        final f = _fixture(user);
        final c = _ctl(f, user);
        await c.load();
        expect(c.canCreateTest, expected, reason: user);
      }
    });
  });

  group('7/8 — draft editing gate (EDIT_TEST + creator + draft)', () {
    test('creator leader may edit own draft; not published; owner not creator may not', () async {
      final lead = _fixture('u-lead');
      final cl = _ctl(lead, 'u-lead');
      await cl.load();
      expect(cl.canEdit(lead.tests.rows['t-1']!), isTrue);
      expect(cl.canEdit(lead.tests.rows['t-3']!), isFalse, reason: 'published');
      final owner = _fixture('u-owner');
      final co = _ctl(owner, 'u-owner');
      await co.load();
      expect(co.canEdit(owner.tests.rows['t-1']!), isFalse, reason: 'rpc_update_test is creator-only');
    });

    test('member without EDIT_TEST cannot edit anything', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.canEditTests, isFalse);
      expect(c.tests.any(c.canEdit), isFalse);
    });
  });

  group('9/10 — publish', () {
    test('creator leader publishes own draft; list re-read', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      final t1 = c.tests.firstWhere((t) => t.id == 't-1');
      expect(c.canPublish(t1), isTrue);
      expect(await c.publish(t1), isTrue);
      expect(c.tests.firstWhere((t) => t.id == 't-1').status, TestStatus.published);
      expect(f.tests.calls.where((x) => x == 'listForGroup:g-1').length, 2);
      expect(c.actingTestId, isNull);
      expect(c.isBusy, isFalse);
    });

    test('owner (PUBLISH_TEST via bypass) is not the creator → refused', () async {
      final f = _fixture('u-owner');
      final c = _ctl(f, 'u-owner');
      await c.load();
      final t1 = c.tests.firstWhere((t) => t.id == 't-1');
      expect(c.canPublish(t1), isFalse);
      expect(await c.publish(t1), isFalse);
      expect(c.error, contains('creator'));
      expect(f.tests.calls.any((x) => x.startsWith('publish')), isFalse);
    });

    test('invalid lifecycle: published / ended / scheduled cannot be published', () async {
      final f = _fixture('u-owner');
      final c = _ctl(f, 'u-owner');
      await c.load();
      for (final id in ['t-2', 't-4', 't-6']) {
        final t = c.tests.firstWhere((x) => x.id == id);
        expect(c.canPublish(t), isFalse, reason: id);
        expect(await c.publish(t), isFalse, reason: id);
      }
      expect(f.tests.calls.any((x) => x.startsWith('publish')), isFalse);
    });

    test('server rejection is surfaced and the list re-read', () async {
      final f = _fixture('u-lead');
      f.tests.rows['t-1'] = _t('t-1', by: 'u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      f.groups.failNextWith = null;
      final failing = _FailingPublishRepository(f.tests);
      final c2 = GroupTestsController(
        groupId: 'g-1',
        tests: failing,
        groups: f.groups,
        currentUserId: 'u-lead',
        now: () => _now,
      );
      await c2.load();
      expect(await c2.publish(c2.tests.firstWhere((t) => t.id == 't-1')), isFalse);
      expect(c2.error, contains('approved question'));
      expect(c2.tests.firstWhere((t) => t.id == 't-1').status, TestStatus.draft);
      expect(c.isBusy, isFalse);
    });
  });

  group('11/12 — schedule', () {
    test('creator leader with SCHEDULE_TEST sets a valid window on a draft', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      final t1 = c.tests.firstWhere((t) => t.id == 't-1');
      final start = _now.add(const Duration(days: 3));
      final end = start.add(const Duration(hours: 2));
      expect(c.canSchedule(t1), isTrue);
      expect(await c.schedule(t1, startsAt: start, endsAt: end), isTrue);
      final after = c.tests.firstWhere((t) => t.id == 't-1');
      expect(after.startsAt, start);
      expect(after.endsAt, end);
      expect(after.title, 'Test t-1', reason: 'other fields re-sent unchanged');
      expect(after.durationSec, 600);
    });

    test('invalid schedule (end before start / nothing set) never reaches the server', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      final t1 = c.tests.firstWhere((t) => t.id == 't-1');
      expect(
        await c.schedule(t1, startsAt: _now.add(const Duration(days: 1)), endsAt: _now),
        isFalse,
      );
      expect(c.error, GroupTestManagement.scheduleEndBeforeStart);
      expect(await c.schedule(t1, startsAt: null, endsAt: null), isFalse);
      expect(c.error, GroupTestManagement.scheduleNothingToSet);
      expect(f.tests.calls.any((x) => x.startsWith('update')), isFalse);
    });

    test('schedule refused for non-creator, no permission, or ended status', () async {
      final owner = _fixture('u-owner');
      final co = _ctl(owner, 'u-owner');
      await co.load();
      expect(co.canSchedule(owner.tests.rows['t-1']!), isFalse, reason: 'not creator');
      expect(co.canSchedule(owner.tests.rows['t-4']!), isFalse, reason: 'ended');
      expect(co.canSchedule(owner.tests.rows['t-2']!), isTrue, reason: 'own published');
      final member = _fixture('u-me');
      final cm = _ctl(member, 'u-me');
      await cm.load();
      expect(cm.canScheduleTests, isFalse);
      expect(
        await cm.schedule(member.tests.rows['t-1']!, startsAt: _now, endsAt: _now.add(const Duration(hours: 1))),
        isFalse,
      );
      expect(member.tests.calls.any((x) => x.startsWith('update')), isFalse);
    });
  });

  group('13/18 — archive / delete, participant preservation', () {
    test('owner archives a leader\'s ended test (EDIT_TEST or owner); attempts untouched', () async {
      final f = _fixture('u-owner');
      final c = _ctl(f, 'u-owner');
      await c.load();
      final t4 = c.tests.firstWhere((t) => t.id == 't-4');
      expect(c.canArchive(t4), isTrue);
      expect(await c.archive(t4), isTrue);
      final row = f.tests.rows['t-4']!;
      expect(row.status, TestStatus.archived);
      expect(row.isSoftDeleted, isTrue);
      expect(row.id, 't-4', reason: 'row still exists — attempts/answers/results keep their FK');
      expect(c.sections[GroupTestSection.archived]!.map((t) => t.id), ['t-4'],
          reason: 'owner is the creator of t-4 so still sees it');
    });

    test('live / scheduled tests cannot be archived; member cannot archive', () async {
      final f = _fixture('u-owner');
      final c = _ctl(f, 'u-owner');
      await c.load();
      expect(c.canArchive(c.tests.firstWhere((t) => t.id == 't-6')), isFalse, reason: 'scheduled');
      expect(await c.archive(c.tests.firstWhere((t) => t.id == 't-6')), isFalse);
      expect(f.tests.rows['t-6']!.isSoftDeleted, isFalse);
      final m = _fixture('u-me');
      final cm = _ctl(m, 'u-me');
      await cm.load();
      expect(cm.tests.any(cm.canArchive), isFalse);
      await expectLater(m.tests.archive('t-4'), throwsA(isA<DataError>()));
      expect(m.tests.rows['t-4']!.isSoftDeleted, isFalse);
    });

    test('creator deletes own draft; owner cannot delete another creator\'s draft', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(await c.deleteDraft(c.tests.firstWhere((t) => t.id == 't-1')), isTrue);
      expect(f.tests.rows['t-1']!.isSoftDeleted, isTrue);
      final o = _fixture('u-owner');
      final co = _ctl(o, 'u-owner');
      await co.load();
      expect(co.canDeleteDraft(o.tests.rows['t-1']!), isFalse);
    });
  });

  group('14/15 — member cannot manage; removed manager loses access', () {
    test('member: read-only list, every gate false', () async {
      final f = _fixture('u-me');
      final c = _ctl(f, 'u-me');
      await c.load();
      expect(c.canManage, isFalse);
      for (final t in c.tests) {
        expect(c.canEdit(t), isFalse);
        expect(c.canPublish(t), isFalse);
        expect(c.canSchedule(t), isFalse);
        expect(c.canArchive(t), isFalse);
        expect(c.canDeleteDraft(t), isFalse);
      }
    });

    test('leader removed from the group: refresh → access denied, mutation refused', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      expect(c.canCreateTest, isTrue);
      f.groups.groups['g-1']!.roles.remove('u-lead'); // removed server-side
      await c.refresh();
      expect(c.accessDenied, isTrue);
      expect(c.tests, isEmpty);
      // Even a stale Test object cannot be published now.
      expect(await c.publish(f.tests.rows['t-1']!), isFalse);
    });
  });

  group('16/17 — question security', () {
    test('management reads never touch questions or correct_option', () async {
      final f = _fixture('u-lead');
      final c = _ctl(f, 'u-lead');
      await c.load();
      await c.publish(c.tests.firstWhere((t) => t.id == 't-1'));
      expect(f.tests.calls.any((x) => x.contains('question')), isFalse);
      // The safe question RPC shape has no answer key.
      expect(FakeQuestionRepository().safeQuestions, isNotNull);
    });
  });

  group('19–22 — states and single-flight', () {
    test('loading → loaded; empty group', () async {
      final f = _fixture('u-owner');
      f.tests.rows.removeWhere((_, t) => t.groupId == 'g-1');
      final c = _ctl(f, 'u-owner');
      expect(c.hasLoaded, isFalse);
      final fut = c.load();
      expect(c.isLoading, isTrue);
      await fut;
      expect(c.hasLoaded, isTrue);
      expect(c.isEmpty, isTrue);
      expect(c.error, isNull);
    });

    test('error then retry', () async {
      final f = _fixture('u-owner');
      f.groups.failNextWith = const DataError(message: 'Network error.');
      final failing = _FailingListRepository(f.tests);
      final c = GroupTestsController(
        groupId: 'g-1',
        tests: failing,
        groups: f.groups,
        currentUserId: 'u-owner',
        now: () => _now,
      );
      await c.load();
      expect(c.group, isNotNull);
      expect(c.error, 'Network error.');
      failing.fail = false;
      await c.load();
      expect(c.error, isNull);
      expect(c.tests, isNotEmpty);
    });

    test('second mutation while one is in flight is dropped', () async {
      final f = _fixture('u-lead');
      final slow = _SlowPublishRepository(f.tests);
      final c = GroupTestsController(
        groupId: 'g-1',
        tests: slow,
        groups: f.groups,
        currentUserId: 'u-lead',
        now: () => _now,
      );
      await c.load();
      final t1 = c.tests.firstWhere((t) => t.id == 't-1');
      final first = c.publish(t1);
      expect(c.isBusy, isTrue);
      expect(c.actingTestId, 't-1');
      expect(await c.publish(t1), isFalse);
      expect(await c.archive(c.tests.firstWhere((t) => t.id == 't-4')), isFalse);
      expect(await first, isTrue);
      expect(f.tests.calls.where((x) => x == 'publish:t-1').length, 1);
    });
  });

  group('23/24 — screens and G8 regression', () {
    Future<GroupTestsController> pump(WidgetTester tester, String user) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = _fixture(user);
      final c = _ctl(f, user);
      await tester.pumpWidget(
        MaterialApp(home: GroupTestsScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('member: sections shown, no create button, read-only note', (tester) async {
      final c = await pump(tester, 'u-me');
      expect(find.byKey(const Key('create_group_test')), findsNothing);
      expect(find.byKey(const Key('group_tests_readonly_note')), findsOneWidget);
      expect(find.byKey(const Key('section_drafts')), findsOneWidget);
      expect(find.byKey(const Key('section_live')), findsOneWidget);
      expect(find.byKey(const Key('group_test_t-3')), findsOneWidget);
      expect(find.byKey(const Key('group_test_t-9')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('leader: create button; manage sheet offers publish/schedule/delete for own draft', (
      tester,
    ) async {
      final c = await pump(tester, 'u-lead');
      expect(find.byKey(const Key('create_group_test')), findsOneWidget);
      await tester.tap(find.byKey(const Key('manage_t-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group_test_manage_sheet')), findsOneWidget);
      expect(find.byKey(const Key('manage_publish')), findsOneWidget);
      expect(find.byKey(const Key('manage_schedule')), findsOneWidget);
      expect(find.byKey(const Key('manage_edit')), findsOneWidget);
      expect(find.byKey(const Key('manage_delete_draft')), findsOneWidget);
      expect(find.byKey(const Key('manage_archive')), findsOneWidget);
      expect(find.textContaining('correct'), findsNothing);
      await tester.tap(find.byKey(const Key('manage_publish')));
      await tester.pumpAndSettle();
      expect(c.tests.firstWhere((t) => t.id == 't-1').status, TestStatus.published);
      expect(find.byKey(const Key('manage_publish')), findsNothing, reason: 'sheet reconciled from server');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('non-member: access denied state', (tester) async {
      final c = await pump(tester, 'u-stranger');
      expect(find.byKey(const Key('group_tests_denied')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('G8 regression: hub still renders chat and the new tests entry', (tester) async {
      tester.view.physicalSize = const Size(800, 3400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = InMemoryGroupRepository(currentUser: 'u-me')
        ..seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-me');
      await tester.pumpWidget(MaterialApp(home: GroupHubScreen(groupId: 'g-1', controller: c)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group_chat_section')), findsOneWidget);
      expect(find.byKey(const Key('open_group_tests')), findsOneWidget);
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

/// Mirrors `rpc_publish_test` refusing a draft with no approved question.
class _FailingPublishRepository extends _Delegating {
  _FailingPublishRepository(super.inner);
  @override
  Future<void> publish(String testId) async =>
      throw const DataError(message: 'Test must have at least one approved question to publish.');
}

class _FailingListRepository extends _Delegating {
  _FailingListRepository(super.inner);
  bool fail = true;
  @override
  Future<List<Test>> listForGroup(String groupId, {int limit = 100}) {
    if (fail) throw const DataError(message: 'Network error.');
    return inner.listForGroup(groupId, limit: limit);
  }
}

class _SlowPublishRepository extends _Delegating {
  _SlowPublishRepository(super.inner);
  @override
  Future<void> publish(String testId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return inner.publish(testId);
  }
}

class _Delegating implements TestRepository {
  _Delegating(this.inner);
  final FakeTestRepository inner;
  @override
  Future<Test?> getById(String testId) => inner.getById(testId);
  @override
  Future<List<Test>> listAccessible({int limit = 100}) => inner.listAccessible(limit: limit);
  @override
  Future<List<Test>> listMyDrafts({int limit = 50}) => inner.listMyDrafts(limit: limit);
  @override
  Future<Set<String>> myAttemptedTestIds() => inner.myAttemptedTestIds();
  @override
  Future<List<Test>> listByGroup(String groupId, {int limit = 100}) =>
      inner.listByGroup(groupId, limit: limit);
  @override
  Future<Test> create(TestWriteInput input) => inner.create(input);
  @override
  Future<void> update(String testId, TestWriteInput input) => inner.update(testId, input);
  @override
  Future<void> publish(String testId) => inner.publish(testId);
  @override
  Future<void> setShuffleQuestions(String testId, bool shuffle) =>
      inner.setShuffleQuestions(testId, shuffle);
  @override
  Future<void> deleteDraft(String testId, {String? reason}) => inner.deleteDraft(testId, reason: reason);
  @override
  Future<List<TestSyllabus>> syllabusFor(String testId) => inner.syllabusFor(testId);
  @override
  Future<void> addSyllabus(String testId, String nodeId) => inner.addSyllabus(testId, nodeId);
  @override
  Future<void> removeSyllabus(String testId, String nodeId) => inner.removeSyllabus(testId, nodeId);
  @override
  Future<List<Test>> listForGroup(String groupId, {int limit = 100}) =>
      inner.listForGroup(groupId, limit: limit);
  @override
  Future<void> archive(String testId, {String? reason}) => inner.archive(testId, reason: reason);
}
