// G7 — Group Announcements on the existing `public.group_announcements`
// contract (legacy migrations 0020 → 0033 repair → 0040):
//   base columns id, group_id, author_id, title 1..120, body 1..2000,
//   created_at, updated_at; SELECT fn_is_member; INSERT / manage (ALL)
//   SEND_ANNOUNCEMENT or owner. Leader holds SEND_ANNOUNCEMENT by the live
//   seeding (G3 audit); moderator and member do not.
// The fake mirrors those policies; no role name is consulted in the UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/group_announcement.dart';
import 'package:my_praperation/features/group/screens/group_hub_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';
import 'package:my_praperation/features/group/widgets/group_announcements_section.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

GroupAnnouncement _a(
  String id,
  String groupId, {
  String author = 'u-owner',
  String title = 'Title',
  String body = 'Body',
  required DateTime at,
  DateTime? updated,
}) => GroupAnnouncement(
  id: id,
  groupId: groupId,
  authorId: author,
  title: title,
  body: body,
  createdAt: at,
  updatedAt: updated ?? at,
);

/// g-1 owned by u-owner with leader u-lead, moderator u-mod, member u-me and
/// two announcements (older one by the owner, newer by the leader);
/// g-2 owned by u-other with one announcement (u-me is not a member).
InMemoryGroupRepository _repo({String user = 'u-me'}) {
  final repo = InMemoryGroupRepository(currentUser: user)
    ..seed(
      id: 'g-1',
      name: 'Physics',
      ownerId: 'u-owner',
      members: {'u-lead': 'leader', 'u-mod': 'moderator', 'u-me': 'member'},
    )
    ..seed(id: 'g-2', name: 'Other', ownerId: 'u-other');
  repo.profileNames['u-owner'] = 'Owner Person';
  repo.profileNames['u-lead'] = 'Lead Person';
  repo.groups['g-1']!.announcements.addAll([
    _a(
      'a-old',
      'g-1',
      title: 'Welcome',
      body: 'First post',
      at: DateTime(2026, 9, 1, 10),
    ),
    _a(
      'a-new',
      'g-1',
      author: 'u-lead',
      title: 'Test on Friday',
      body: 'Chapter 3',
      at: DateTime(2026, 9, 5, 10),
    ),
  ]);
  repo.groups['g-2']!.announcements.add(
    _a('a-g2', 'g-2', author: 'u-other', at: DateTime(2026, 9, 3)),
  );
  return repo;
}

void main() {
  group('TEST 1 — model parsing', () {
    test('fromJson maps the base columns; updated_at falls back', () {
      final a = GroupAnnouncement.fromJson({
        'id': 'a-1',
        'group_id': 'g-1',
        'author_id': 'u-1',
        'title': 'Hello',
        'body': 'World',
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': '2026-09-02T10:00:00Z',
      });
      expect(a.id, 'a-1');
      expect(a.groupId, 'g-1');
      expect(a.authorId, 'u-1');
      expect(a.title, 'Hello');
      expect(a.body, 'World');
      expect(a.createdAt.toUtc(), DateTime.utc(2026, 9, 1, 10));
      expect(a.updatedAt.toUtc(), DateTime.utc(2026, 9, 2, 10));
      expect(a.wasEdited, isTrue);
      expect(a.toJson()['author_id'], 'u-1');

      final noUpdated = GroupAnnouncement.fromJson({
        'id': 'a-2',
        'group_id': 'g-1',
        'author_id': 'u-1',
        'title': 'x',
        'body': 'y',
        'created_at': '2026-09-01T10:00:00Z',
        'updated_at': null,
      });
      expect(noUpdated.updatedAt, noUpdated.createdAt);
      expect(noUpdated.wasEdited, isFalse);
      expect(a.copyWith(title: 'New').title, 'New');
      expect(a.copyWith(title: 'New').id, a.id);
    });

    test('validation mirrors the live CHECKs (title 1..120, body 1..2000)', () {
      String? v(String t, String b) =>
          GroupHubController.validateAnnouncement(title: t, body: b);
      expect(v('', 'b'), contains('title'));
      expect(v('   ', 'b'), contains('title'));
      expect(v('t', ''), contains('text'));
      expect(v('t', '   '), contains('text'));
      expect(v('x' * 120, 'b'), isNull);
      expect(v('x' * 121, 'b'), contains('120'));
      expect(v('t', 'y' * 2000), isNull);
      expect(v('t', 'y' * 2001), contains('2000'));
      expect(v(' ok ', ' fine '), isNull);
    });
  });

  group('TEST 2/3 — read', () {
    test('member reads only this group, newest first', () async {
      final repo = _repo();
      final c = _hub(repo);
      await c.load();
      expect(c.announcementsError, isNull);
      expect(c.announcements.map((a) => a.id).toList(), ['a-new', 'a-old']);
      expect(c.announcements.every((a) => a.groupId == 'g-1'), isTrue);
      expect(c.hasAnnouncements, isTrue);
      expect(c.canSendAnnouncement, isFalse);
    });

    test('author label comes from the roster; "You" for own posts', () async {
      final repo = _repo(user: 'u-lead');
      final c = _hub(repo, user: 'u-lead');
      await c.load();
      final byLead = c.announcements.firstWhere((a) => a.id == 'a-new');
      final byOwner = c.announcements.firstWhere((a) => a.id == 'a-old');
      expect(c.announcementAuthorLabel(byLead), 'You');
      expect(c.announcementAuthorLabel(byOwner), 'Owner Person');
      final gone = _a('a-x', 'g-1', author: 'u-left', at: DateTime(2026));
      expect(c.announcementAuthorLabel(gone), isNull);
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
      expect(await repo.announcements('g-2'), isEmpty);
      expect(await repo.announcements('g-1'), isEmpty);
    });

    test('empty state: loaded, no error, no rows', () async {
      final repo = _repo();
      repo.groups['g-1']!.announcements.clear();
      final c = _hub(repo);
      await c.load();
      expect(c.announcementsLoading, isFalse);
      expect(c.announcementsError, isNull);
      expect(c.announcements, isEmpty);
      expect(c.hasAnnouncements, isFalse);
    });
  });

  group('TEST 4 — error + retry', () {
    test('load error surfaces announcementsError; retry recovers', () async {
      final repo = _FailingAnnouncementsRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      final c = _hub(repo);
      await c.load();
      expect(c.group, isNotNull, reason: 'a section failure never blocks the hub');
      expect(c.announcementsError, 'Network error.');
      expect(c.announcements, isEmpty);
      repo.failReads = false;
      await c.retryAnnouncements();
      expect(c.announcementsError, isNull);
    });
  });

  group('TEST 6 — authorized creation / edit / delete', () {
    for (final user in ['u-owner', 'u-lead']) {
      test('$user: create → trimmed, author = caller, newest first, re-read', () async {
        final repo = _repo(user: user);
        final c = _hub(repo, user: user);
        await c.load();
        expect(c.canSendAnnouncement, isTrue);
        expect(
          await c.createAnnouncement(title: '  Holiday  ', body: ' Monday off '),
          isTrue,
        );
        expect(c.error, isNull);
        expect(c.announcements.length, 3);
        expect(c.announcements.first.title, 'Holiday');
        expect(c.announcements.first.body, 'Monday off');
        expect(c.announcements.first.authorId, user);
        expect(c.announcementAuthorLabel(c.announcements.first), 'You');
        expect(repo.calls.where((x) => x == 'createAnnouncement:g-1').length, 1);
        expect(c.announcementSaving, isFalse);
      });
    }

    test('leader edits another author\'s announcement (manage = ALL)', () async {
      final repo = _repo(user: 'u-lead');
      final c = _hub(repo, user: 'u-lead');
      await c.load();
      final byOwner = c.announcements.firstWhere((a) => a.id == 'a-old');
      expect(
        await c.updateAnnouncement(byOwner, title: ' Updated ', body: 'New body'),
        isTrue,
      );
      final after = c.announcements.firstWhere((a) => a.id == 'a-old');
      expect(after.title, 'Updated');
      expect(after.body, 'New body');
      expect(after.wasEdited, isTrue);
      expect(c.actingAnnouncementId, isNull);
    });

    test('owner deletes → row gone, re-read', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      final target = c.announcements.firstWhere((a) => a.id == 'a-new');
      expect(await c.deleteAnnouncement(target), isTrue);
      expect(c.announcements.map((a) => a.id), ['a-old']);
      expect(repo.groups['g-1']!.announcements.length, 1);
    });

    test('explicit SEND_ANNOUNCEMENT grant for a moderator role works', () async {
      final repo = _repo(user: 'u-mod');
      repo.roleGrants.add('g-1:moderator:SEND_ANNOUNCEMENT');
      final c = _hub(repo, user: 'u-mod');
      await c.load();
      expect(c.isOwner, isFalse);
      expect(c.canSendAnnouncement, isTrue);
      expect(await c.createAnnouncement(title: 'Mod', body: 'post'), isTrue);
      expect(c.announcements.length, 3);
    });
  });

  group('TEST 9 — input validation', () {
    test('create/update reject empty title or body before any server call', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      expect(await c.createAnnouncement(title: '   ', body: 'x'), isFalse);
      expect(c.error, 'Announcement title cannot be empty.');
      expect(await c.createAnnouncement(title: 'x', body: '  '), isFalse);
      expect(c.error, 'Announcement text cannot be empty.');
      expect(
        await c.createAnnouncement(title: 'x' * 121, body: 'b'),
        isFalse,
      );
      expect(c.error, contains('120'));
      expect(
        await c.updateAnnouncement(c.announcements.first, title: '', body: 'b'),
        isFalse,
      );
      expect(repo.calls.any((x) => x.startsWith('createAnnouncement')), isFalse);
      expect(repo.calls.any((x) => x.startsWith('updateAnnouncement')), isFalse);
      expect(c.announcements.length, 2);
    });
  });

  group('TEST 7/8 — unauthorized and cross-group', () {
    for (final user in ['u-me', 'u-mod']) {
      test('$user: controller refuses and server refuses; nothing changes', () async {
        final repo = _repo(user: user);
        final c = _hub(repo, user: user);
        await c.load();
        expect(c.canSendAnnouncement, isFalse);
        final before = List.of(repo.groups['g-1']!.announcements);

        expect(await c.createAnnouncement(title: 'Sneaky', body: 'x'), isFalse);
        expect(c.error, contains('announcement permission'));
        expect(
          await c.updateAnnouncement(c.announcements.first, title: 'S', body: 'x'),
          isFalse,
        );
        expect(await c.deleteAnnouncement(c.announcements.first), isFalse);
        expect(repo.groups['g-1']!.announcements, before);

        // Bypass the UI guard: the (fake) server policy still refuses.
        await expectLater(
          repo.createAnnouncement(groupId: 'g-1', title: 'D', body: 'x'),
          throwsA(isA<DataError>()),
        );
        await expectLater(
          repo.updateAnnouncement(announcementId: 'a-old', title: 'D', body: 'x'),
          throwsA(isA<DataError>()),
        );
        await expectLater(
          repo.deleteAnnouncement('a-old'),
          throwsA(isA<DataError>()),
        );
        expect(repo.groups['g-1']!.announcements, before);
      });
    }

    test('owner of g-1 cannot touch a forged id from g-2', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      final foreign = repo.groups['g-2']!.announcements.first;
      expect(
        await c.updateAnnouncement(foreign, title: 'Hijack', body: 'x'),
        isFalse,
      );
      expect(c.error, contains('could not be updated'));
      expect(await c.deleteAnnouncement(foreign), isFalse);
      expect(c.error, contains('could not be deleted'));
      expect(repo.groups['g-2']!.announcements.single.title, 'Title');
      expect(c.announcements.length, 2, reason: 're-read keeps own list');
    });

    test('server rejection is mapped and the list is re-read', () async {
      final repo = _repo(user: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      repo.failNextWith = const DataError(message: 'row-level security');
      expect(await c.createAnnouncement(title: 'Blocked', body: 'x'), isFalse);
      expect(c.error, 'row-level security');
      expect(c.announcements.length, 2);
      expect(c.announcementSaving, isFalse);
    });
  });

  group('TEST 10 — single-flight', () {
    test('second create while first in flight is dropped', () async {
      final repo = _SlowAnnouncementsRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      final first = c.createAnnouncement(title: 'One', body: 'x');
      expect(c.announcementSaving, isTrue);
      expect(await c.createAnnouncement(title: 'Two', body: 'x'), isFalse);
      expect(await first, isTrue);
      expect(c.announcements.map((a) => a.title), ['One']);
      expect(
        repo.calls.where((x) => x == 'createAnnouncement:g-1').length,
        1,
      );
    });

    test('delete twice on the same announcement runs once', () async {
      final repo = _SlowAnnouncementsRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner');
      final c = _hub(repo, user: 'u-owner');
      await c.load();
      await c.createAnnouncement(title: 'One', body: 'x');
      final a = c.announcements.single;
      final first = c.deleteAnnouncement(a);
      expect(c.actingAnnouncementId, a.id);
      expect(await c.deleteAnnouncement(a), isFalse);
      expect(await first, isTrue);
      expect(c.announcements, isEmpty);
      expect(
        repo.calls.where((x) => x.startsWith('deleteAnnouncement')).length,
        1,
      );
    });
  });

  group('TEST 5/11/12 — hub widget', () {
    Future<GroupHubController> pump(
      WidgetTester tester,
      InMemoryGroupRepository repo, {
      String user = 'u-me',
    }) async {
      tester.view.physicalSize = const Size(800, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = _hub(repo, user: user);
      await tester.pumpWidget(
        MaterialApp(home: GroupHubScreen(groupId: 'g-1', controller: c)),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('member: read-only — list shown, no controls', (tester) async {
      final c = await pump(tester, _repo());
      expect(find.byKey(const Key('group_announcements_section')), findsOneWidget);
      expect(find.byKey(const Key('announcement_a-new')), findsOneWidget);
      expect(find.byKey(const Key('announcement_a-old')), findsOneWidget);
      expect(find.text('Test on Friday'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('announcement_meta_a-new'))).data,
        startsWith('Lead Person · '),
      );
      expect(find.byKey(const Key('add_announcement_button')), findsNothing);
      expect(find.byKey(const Key('edit_announcement_a-new')), findsNothing);
      expect(find.byKey(const Key('delete_announcement_a-new')), findsNothing);
      // Hub regression: rules, roster and leave still render around it.
      expect(find.byKey(const Key('group_rules_section')), findsOneWidget);
      expect(find.byKey(const Key('hub_members_heading')), findsOneWidget);
      expect(find.byKey(const Key('leave_group_button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('moderator (no SEND_ANNOUNCEMENT): read-only', (tester) async {
      final c = await pump(tester, _repo(user: 'u-mod'), user: 'u-mod');
      expect(find.byKey(const Key('add_announcement_button')), findsNothing);
      expect(find.byKey(const Key('edit_announcement_a-old')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('empty state for member', (tester) async {
      final repo = _repo();
      repo.groups['g-1']!.announcements.clear();
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('announcements_empty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('error + retry', (tester) async {
      final repo = _FailingAnnouncementsRepository();
      repo.seed(id: 'g-1', ownerId: 'u-owner', members: {'u-me': 'member'});
      repo.groups['g-1']!.announcements.add(
        _a('a-x', 'g-1', title: 'Recovered', at: DateTime(2026, 9, 1)),
      );
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('announcements_error')), findsOneWidget);
      repo.failReads = false;
      await tester.tap(find.byKey(const Key('announcements_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('announcement_a-x')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('leader: post → edit → delete with confirmation, list refreshes', (
      tester,
    ) async {
      final repo = _repo(user: 'u-lead');
      final c = await pump(tester, repo, user: 'u-lead');
      expect(find.byKey(const Key('add_announcement_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_announcement_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('announcement_title_field')),
        ' Holiday ',
      );
      await tester.enterText(
        find.byKey(const Key('announcement_body_field')),
        'Monday off',
      );
      await tester.tap(find.byKey(const Key('confirm_post_announcement')));
      await tester.pumpAndSettle();
      expect(c.announcements.length, 3);
      expect(c.announcements.first.title, 'Holiday');
      expect(find.text('Holiday'), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit_announcement_a-old')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('announcement_title_field')),
        'Edited',
      );
      await tester.tap(find.byKey(const Key('confirm_edit_announcement')));
      await tester.pumpAndSettle();
      expect(find.text('Edited'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);

      await tester.tap(find.byKey(const Key('delete_announcement_a-new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm_delete_announcement')), findsOneWidget);
      expect(c.announcements.length, 3, reason: 'nothing deleted before confirm');
      await tester.tap(find.byKey(const Key('confirm_delete_announcement')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('announcement_a-new')), findsNothing);
      expect(c.announcements.length, 2);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('leader: empty post is rejected without a server call', (
      tester,
    ) async {
      final repo = _repo(user: 'u-lead');
      final c = await pump(tester, repo, user: 'u-lead');
      await tester.tap(find.byKey(const Key('add_announcement_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('announcement_title_field')),
        '   ',
      );
      await tester.tap(find.byKey(const Key('confirm_post_announcement')));
      await tester.pumpAndSettle();
      expect(c.announcements.length, 2);
      expect(repo.calls.any((x) => x.startsWith('createAnnouncement')), isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('section uses the hub controller, not a second source', (
      tester,
    ) async {
      final c = await pump(tester, _repo());
      final section = tester.widget<GroupAnnouncementsSection>(
        find.byType(GroupAnnouncementsSection),
      );
      expect(identical(section.controller, c), isTrue);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

class _FailingAnnouncementsRepository extends InMemoryGroupRepository {
  _FailingAnnouncementsRepository() : super(currentUser: 'u-me');
  bool failReads = true;
  @override
  Future<List<GroupAnnouncement>> announcements(String groupId) async {
    if (failReads) throw const DataError(message: 'Network error.');
    return super.announcements(groupId);
  }
}

class _SlowAnnouncementsRepository extends InMemoryGroupRepository {
  _SlowAnnouncementsRepository() : super(currentUser: 'u-owner');
  @override
  Future<void> createAnnouncement({
    required String groupId,
    required String title,
    required String body,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.createAnnouncement(groupId: groupId, title: title, body: body);
  }

  @override
  Future<void> deleteAnnouncement(String announcementId) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.deleteAnnouncement(announcementId);
  }
}
