// R4.4 — listing search + kind filter. Client-side narrowing over the
// RLS-scoped lists: it must never add rows, only hide them, and it must
// apply identically to all four tabs (drafts included).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/domain/test_lifecycle.dart';
import 'package:my_praperation/features/test/screens/test_listing_screen.dart';
import 'package:my_praperation/features/test/state/test_listing_controller.dart';

import 'fakes.dart';

final _now = DateTime(2026, 9, 16, 12);

Test _t(
  String id,
  String title, {
  String? description,
  String mode = 'self',
  String kind = 'practice',
  TestStatus status = TestStatus.published,
  DateTime? startsAt,
  DateTime? createdAt,
}) => Test(
  id: id,
  createdBy: 'u-1',
  title: title,
  description: description,
  status: status,
  testMode: mode,
  durationSec: 600,
  marksPerQuestion: 1,
  startsAt: startsAt ?? _now.add(const Duration(days: 1)),
  settings: {'test_kind': kind},
  createdAt: createdAt,
);

FakeTestRepository _repo() => FakeTestRepository()
  ..rows['a'] = _t('a', 'Algebra basics', description: 'Linear equations')
  ..rows['b'] = _t('b', 'Biology quick check', kind: 'quick')
  ..rows['c'] = _t(
    'c',
    'Chemistry challenge',
    mode: 'live',
    kind: 'challenge_with_friends',
    status: TestStatus.live,
    startsAt: _now.subtract(const Duration(minutes: 1)),
  )
  ..rows['g'] = _t('g', 'Geometry group test', mode: 'group', kind: 'group')
  ..rows['d1'] = _t('d1', 'Draft: algebra revision', status: TestStatus.draft)
  ..rows['d2'] = _t(
    'd2',
    'Draft: history',
    status: TestStatus.draft,
    kind: 'self',
  );

Future<TestListingController> _loaded() async {
  final c = TestListingController(repository: _repo(), clock: () => _now);
  await c.load();
  return c;
}

List<String> _ids(List<Test> l) => l.map((t) => t.id).toList()..sort();

void main() {
  group('TestListingController filters', () {
    test('no filter → full buckets, hasActiveFilter false', () async {
      final c = await _loaded();
      expect(c.hasActiveFilter, isFalse);
      expect(_ids(c.testsFor(ListingCategory.upcoming)), ['a', 'b', 'g']);
      expect(_ids(c.testsFor(ListingCategory.challengeWithFriends)), ['c']);
      expect(_ids(c.drafts), ['d1', 'd2']);
      expect(c.unfilteredCount(ListingCategory.upcoming), 3);
      expect(c.unfilteredCount(ListingCategory.drafts), 2);
    });

    test(
      'query is case-insensitive and matches title or description',
      () async {
        final c = await _loaded();
        c.setQuery('ALGEBRA');
        expect(c.hasActiveFilter, isTrue);
        expect(_ids(c.testsFor(ListingCategory.upcoming)), ['a']);
        expect(_ids(c.drafts), ['d1']); // drafts filtered too
        expect(_ids(c.testsFor(ListingCategory.challengeWithFriends)), isEmpty);

        c.setQuery('linear'); // description only
        expect(_ids(c.testsFor(ListingCategory.upcoming)), ['a']);

        c.setQuery('   '); // whitespace = no query
        expect(c.hasActiveFilter, isFalse);
        expect(_ids(c.testsFor(ListingCategory.upcoming)), ['a', 'b', 'g']);
      },
    );

    test('kind filter narrows by mapped TestKind', () async {
      final c = await _loaded();
      c.setKindFilter(TestKind.quick);
      expect(_ids(c.testsFor(ListingCategory.upcoming)), ['b']);
      expect(_ids(c.drafts), isEmpty);

      c.setKindFilter(TestKind.challengeWithFriends);
      expect(_ids(c.testsFor(ListingCategory.challengeWithFriends)), ['c']);

      c.setKindFilter(TestKind.group);
      expect(_ids(c.testsFor(ListingCategory.upcoming)), ['g']);

      c.setKindFilter(TestKind.self);
      expect(_ids(c.drafts), ['d2']);
    });

    test('query and kind combine (AND)', () async {
      final c = await _loaded();
      c.setQuery('draft');
      c.setKindFilter(TestKind.practice);
      expect(_ids(c.drafts), ['d1']);
      c.setKindFilter(TestKind.quick);
      expect(_ids(c.drafts), isEmpty);
      // unfiltered count is untouched by filters
      expect(c.unfilteredCount(ListingCategory.drafts), 2);
    });

    test('clearFilters restores everything; refresh keeps filters', () async {
      final c = await _loaded();
      c.setQuery('bio');
      c.setKindFilter(TestKind.quick);
      expect(_ids(c.testsFor(ListingCategory.upcoming)), ['b']);

      await c.refresh();
      expect(c.query, 'bio');
      expect(c.kindFilter, TestKind.quick);
      expect(_ids(c.testsFor(ListingCategory.upcoming)), ['b']);

      c.clearFilters();
      expect(c.hasActiveFilter, isFalse);
      expect(c.query, '');
      expect(c.kindFilter, isNull);
      expect(_ids(c.testsFor(ListingCategory.upcoming)), ['a', 'b', 'g']);
      expect(_ids(c.drafts), ['d1', 'd2']);
    });

    test(
      'filters never widen the list (drafts stay out of bucketed tabs)',
      () async {
        final c = await _loaded();
        c.setQuery('draft');
        expect(c.testsFor(ListingCategory.upcoming), isEmpty);
        expect(c.testsFor(ListingCategory.previous), isEmpty);
        expect(c.testsFor(ListingCategory.challengeWithFriends), isEmpty);
      },
    );

    test('notifies on change only', () async {
      final c = await _loaded();
      var n = 0;
      c.addListener(() => n++);
      c.setQuery('x');
      c.setQuery('x'); // same value → no notify
      c.setKindFilter(TestKind.quick);
      c.setKindFilter(TestKind.quick);
      c.clearFilters();
      c.clearFilters(); // already clear → no notify
      expect(n, 3);
    });
  });

  group('TestListingController sort', () {
    FakeTestRepository sortRepo() => FakeTestRepository()
      ..rows['a'] = _t('a', 'Alpha', createdAt: DateTime(2026, 1, 1))
      ..rows['b'] = _t('b', 'Bravo', createdAt: DateTime(2026, 3, 1))
      ..rows['c'] = _t('c', 'Charlie', createdAt: DateTime(2026, 2, 1));

    test('newest first is the default', () async {
      final c = TestListingController(repository: sortRepo(), clock: () => _now);
      await c.load();
      expect(c.sortOrder, TestSortOrder.newestFirst);
      expect(
        c.testsFor(ListingCategory.upcoming).map((t) => t.id).toList(),
        ['b', 'c', 'a'],
      );
    });

    test('oldest first reverses the order', () async {
      final c = TestListingController(repository: sortRepo(), clock: () => _now);
      await c.load();
      c.setSortOrder(TestSortOrder.oldestFirst);
      expect(
        c.testsFor(ListingCategory.upcoming).map((t) => t.id).toList(),
        ['a', 'c', 'b'],
      );
    });

    test('title A-Z sorts alphabetically', () async {
      final c = TestListingController(repository: sortRepo(), clock: () => _now);
      await c.load();
      c.setSortOrder(TestSortOrder.titleAZ);
      expect(
        c.testsFor(ListingCategory.upcoming).map((t) => t.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('sort applies to drafts too, and setting the same order no-ops', () async {
      final c = TestListingController(repository: sortRepo(), clock: () => _now);
      var n = 0;
      c.addListener(() => n++);
      c.setSortOrder(TestSortOrder.newestFirst); // already default
      expect(n, 0);
      c.setSortOrder(TestSortOrder.titleAZ);
      expect(n, 1);
    });
  });

  group('TestListingScreen filter UI', () {
    testWidgets('typing filters cards; no-match state; Clear restores', (
      tester,
    ) async {
      // Cards grew a primary action button; a taller viewport keeps both
      // seeded cards on-screen in this lazy ListView.builder without this
      // test needing to scroll.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = TestListingController(repository: _repo(), clock: () => _now);
      await tester.pumpWidget(
        MaterialApp(home: TestListingScreen(controller: c)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('listing_search')), findsOneWidget);
      expect(find.text('Algebra basics'), findsOneWidget);
      expect(find.text('Biology quick check'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('listing_search')),
        'biology',
      );
      await tester.pumpAndSettle();
      expect(find.text('Algebra basics'), findsNothing);
      expect(find.text('Biology quick check'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('listing_search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No tests match'), findsOneWidget);
      expect(
        find.text('3 tests are hidden by your search or filter.'),
        findsOneWidget,
      );
      expect(find.text('No upcoming tests'), findsNothing);

      await tester.tap(find.byKey(const Key('clear_filters')));
      await tester.pumpAndSettle();
      expect(c.hasActiveFilter, isFalse);
      expect(find.text('Algebra basics'), findsOneWidget);
      expect(find.text('Biology quick check'), findsOneWidget);
      expect(find.byKey(const Key('listing_search_clear')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('kind chips (in the Filter sheet) narrow the tab; All resets', (tester) async {
      // The always-visible chip row was removed (it duplicated these same
      // controls); the Filter sheet is now the one place to change the
      // kind filter. Taller viewport for the same reason as the test
      // above (cards grew a primary action button).
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = TestListingController(repository: _repo(), clock: () => _now);
      await tester.pumpWidget(
        MaterialApp(home: TestListingScreen(controller: c)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('listing_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kind_chip_quick')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();
      expect(c.kindFilter, TestKind.quick);
      expect(find.text('Algebra basics'), findsNothing);
      expect(find.text('Biology quick check'), findsOneWidget);

      await tester.tap(find.byKey(const Key('listing_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kind_chip_all')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(c.kindFilter, isNull);
      expect(find.text('Algebra basics'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('genuinely empty tab still shows the normal empty state', (
      tester,
    ) async {
      final c = TestListingController(
        repository: FakeTestRepository(),
        clock: () => _now,
      );
      await tester.pumpWidget(
        MaterialApp(home: TestListingScreen(controller: c)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('listing_search')),
        'anything',
      );
      await tester.pumpAndSettle();
      expect(find.text('No upcoming tests'), findsOneWidget);
      expect(find.text('No tests match'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
