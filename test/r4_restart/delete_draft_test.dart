// Delete Test (V1, draft-only). Domain gate, controller flow, response
// parsing, the confirmation dialog, navigation and list refresh — all with
// fake repositories that mirror rpc_delete_test's server rules.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/test_repository.dart';
import 'package:my_praperation/features/test/domain/test_errors.dart';
import 'package:my_praperation/features/test/domain/test_lifecycle.dart';
import 'package:my_praperation/features/test/screens/test_detail_screen.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';
import 'package:my_praperation/features/test/state/test_listing_controller.dart';

import 'fakes.dart';

Test _t({
  String id = 'd-1',
  String owner = 'u-1',
  TestStatus status = TestStatus.draft,
  bool deleted = false,
}) =>
    Test(
      id: id, createdBy: owner, title: 'Draft $id', status: status, testMode: 'self',
      durationSec: 600, isSoftDeleted: deleted, settings: const {'test_kind': 'practice'},
    );

TestDetailController _controller(FakeTestRepository repo, {String user = 'u-1', String id = 'd-1'}) =>
    TestDetailController(
      testId: id,
      tests: repo,
      questions: FakeQuestionRepository(),
      attempts: FakeAttemptRepository(),
      results: FakeResultRepository(),
      currentUserId: () => user,
      clock: () => DateTime(2026, 9, 16, 12),
    );

void main() {
  group('TestLifecycle.canDelete (mirrors rpc_delete_test)', () {
    bool can(TestStatus s, {bool owner = true, bool deleted = false}) =>
        TestLifecycle.canDelete(isOwner: owner, status: s, isSoftDeleted: deleted);

    test('1. owner + draft -> allowed', () => expect(can(TestStatus.draft), isTrue));
    test('2. non-owner + draft -> blocked', () => expect(can(TestStatus.draft, owner: false), isFalse));
    test('3. owner + published -> blocked', () => expect(can(TestStatus.published), isFalse));
    test('4. owner + scheduled -> blocked', () => expect(can(TestStatus.scheduled), isFalse));
    test('5. owner + live -> blocked', () => expect(can(TestStatus.live), isFalse));
    test('6. owner + completed -> blocked', () => expect(can(TestStatus.completed), isFalse));
    test('7. already soft-deleted -> blocked', () => expect(can(TestStatus.draft, deleted: true), isFalse));
    test('every non-draft status is blocked', () {
      for (final s in TestStatus.values.where((s) => s != TestStatus.draft)) {
        expect(can(s), isFalse, reason: '$s must not be deletable');
      }
    });
  });

  group('TestDetailController.deleteDraft', () {
    test('owner + draft: repository called once, test cleared, isDeleted', () async {
      final repo = FakeTestRepository()..rows['d-1'] = _t();
      final c = _controller(repo);
      await c.load();
      expect(c.canDelete, isTrue);
      await c.deleteDraft();
      expect(repo.calls.where((x) => x == 'delete:d-1').length, 1);
      expect(repo.rows['d-1']!.isSoftDeleted, isTrue);
      expect(c.isDeleted, isTrue);
      expect(c.test, isNull);
      expect(c.canDelete, isFalse);
    });

    test('non-owner: gate false and RPC never fired', () async {
      final repo = FakeTestRepository()..rows['d-1'] = _t(owner: 'someone-else');
      final c = _controller(repo);
      await c.load();
      expect(c.canDelete, isFalse);
      await expectLater(c.deleteDraft(), throwsA(isA<ValidationError>()));
      expect(repo.calls.where((x) => x.startsWith('delete:')), isEmpty);
      expect(c.test, isNotNull);
    });

    for (final s in [TestStatus.published, TestStatus.scheduled, TestStatus.live, TestStatus.completed]) {
      test('owner + $s: blocked client-side, RPC never fired', () async {
        final repo = FakeTestRepository()..rows['d-1'] = _t(status: s);
        final c = _controller(repo);
        await c.load();
        expect(c.canDelete, isFalse);
        await expectLater(c.deleteDraft(), throwsA(isA<AppError>()));
        expect(repo.calls.where((x) => x.startsWith('delete:')), isEmpty);
      });
    }

    test('server rejection (stale client: published meanwhile) surfaces mapped error, test remains',
        () async {
      final repo = FakeTestRepository()..rows['d-1'] = _t();
      final c = _controller(repo);
      await c.load();
      // Status changed on the server after load; the RPC rejects.
      repo.rows['d-1'] = _t(status: TestStatus.published);
      await expectLater(
          c.deleteDraft(), throwsA(predicate((e) => e is AppError && e.message == 'Only draft tests can be deleted.')));
      expect(c.isDeleted, isFalse);
      expect(c.test, isNotNull); // still visible
      expect(c.isBusy, isFalse);
    });

    test('already deleted on server -> idempotent rejection, no success state', () async {
      final repo = FakeTestRepository()..rows['d-1'] = _t();
      final c = _controller(repo);
      await c.load();
      repo.rows['d-1'] = _t(deleted: true);
      await expectLater(c.deleteDraft(),
          throwsA(predicate((e) => e is AppError && e.message == 'This test has already been deleted.')));
      expect(c.isDeleted, isFalse);
    });

    test('network failure -> mapped error, nothing deleted', () async {
      final repo = FakeTestRepository()
        ..rows['d-1'] = _t()
        ..failDeleteWith = const NetworkError(message: 'Network error. Please check your connection and try again.');
      final c = _controller(repo);
      await c.load();
      await expectLater(c.deleteDraft(), throwsA(isA<NetworkError>()));
      expect(repo.rows['d-1']!.isSoftDeleted, isFalse);
      expect(c.isDeleted, isFalse);
    });

    test('13. dispose while delete is in flight does not throw', () async {
      final repo = FakeTestRepository()..rows['d-1'] = _t();
      final c = _controller(repo);
      await c.load();
      final pending = c.deleteDraft();
      c.dispose(); // screen popped before the RPC returned
      await expectLater(pending, completes);
      expect(repo.rows['d-1']!.isSoftDeleted, isTrue);
    });
  });

  group('rpc_delete_test response + error mapping', () {
    test('only {deleted: true} counts as success', () {
      expect(SupabaseTestRepository.deletedFromResponse({'test_id': 'x', 'deleted': true}), isTrue);
      expect(SupabaseTestRepository.deletedFromResponse([{'test_id': 'x', 'deleted': true}]), isTrue);
      expect(SupabaseTestRepository.deletedFromResponse({'test_id': 'x', 'deleted': false}), isFalse);
      expect(SupabaseTestRepository.deletedFromResponse({'test_id': 'x'}), isFalse);
      expect(SupabaseTestRepository.deletedFromResponse(null), isFalse);
      expect(SupabaseTestRepository.deletedFromResponse('ok'), isFalse);
    });

    test('server codes map to specific messages', () {
      expect(TestErrors.map('TEST_NOT_DRAFT: only draft tests can be deleted'), 'Only draft tests can be deleted.');
      expect(TestErrors.map('TEST_ALREADY_DELETED'), 'This test has already been deleted.');
      expect(TestErrors.map('TEST_NOT_FOUND'), 'Test not found.');
      expect(TestErrors.map('AUTH_REQUIRED'), 'Your session has expired. Please log in again.');
      expect(TestErrors.map('PERMISSION_DENIED: only the creator can delete this test'),
          'You do not have permission to perform this action.');
      expect(TestErrors.map('boom {"x":1}', context: TestErrorContext.delete),
          'Failed to delete test. Please try again.');
    });
  });

  group('8. My Drafts after delete', () {
    test('deleted draft no longer appears in drafts or any listing tab', () async {
      final repo = FakeTestRepository()
        ..rows['d-1'] = _t()
        ..rows['d-2'] = _t(id: 'd-2');
      final listing = TestListingController(repository: repo, clock: () => DateTime(2026, 9, 16, 12));
      await listing.load();
      expect(listing.drafts.map((t) => t.id), containsAll(['d-1', 'd-2']));

      final detail = _controller(repo);
      await detail.load();
      await detail.deleteDraft();

      await listing.refresh();
      expect(listing.drafts.map((t) => t.id), ['d-2']);
      for (final cat in ListingCategory.values) {
        expect(listing.testsFor(cat).any((t) => t.id == 'd-1'), isFalse, reason: '$cat');
      }
      // Detail by id is gone too (query filters is_soft_deleted = false).
      expect(await repo.getById('d-1'), isNull);
    });
  });

  group('Detail screen delete flow', () {
    Future<(GoRouter, FakeTestRepository, TestDetailController, List<String>)> pump(
      WidgetTester tester, {
      Test? row,
      Object? fail,
    }) async {
      final repo = FakeTestRepository()..rows['d-1'] = row ?? _t();
      if (fail != null) repo.failDeleteWith = fail;
      final c = _controller(repo);
      final visited = <String>[];
      final router = GoRouter(
        initialLocation: '/tests/drafts',
        routes: [
          GoRoute(
            path: '/tests/drafts',
            builder: (_, _) => Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => ctx.push('/tests/d-1'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/tests/:id',
            builder: (_, s) => TestDetailScreen(testId: s.pathParameters['id']!, controller: c),
          ),
        ],
      );
      router.routerDelegate.addListener(() {
        visited.add(router.routerDelegate.currentConfiguration.uri.toString());
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (router, repo, c, visited);
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Test'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Test?'), findsOneWidget);
    }

    testWidgets('Delete Test entry only for a draft; owner of a published test sees no delete',
        (tester) async {
      final (_, _, c, _) = await pump(tester, row: _t(status: TestStatus.published));
      // Owner still gets the More menu (question paper), but no Delete Test.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Test'), findsNothing);
      expect(find.text('Download question paper'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // dismiss menu
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('9. Cancel -> no deletion', (tester) async {
      final (_, repo, c, _) = await pump(tester);
      await openMenu(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.calls.where((x) => x.startsWith('delete:')), isEmpty);
      expect(find.text('Draft d-1'), findsOneWidget); // still on detail
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('10/11. Delete -> RPC called, "Test deleted." shown, back to drafts', (tester) async {
      final (_, repo, c, _) = await pump(tester);
      await openMenu(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete Test'));
      await tester.pumpAndSettle();
      expect(repo.calls.where((x) => x == 'delete:d-1').length, 1);
      expect(repo.rows['d-1']!.isSoftDeleted, isTrue);
      expect(find.text('Test deleted.'), findsWidgets);
      expect(find.text('open'), findsOneWidget); // back on the drafts route
      expect(find.text('Draft d-1'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('12. Backend rejection -> error shown, test remains visible, no navigation',
        (tester) async {
      final (_, _, c, _) = await pump(
        tester,
        fail: const DataError(message: 'Only draft tests can be deleted.'),
      );
      await openMenu(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete Test'));
      await tester.pumpAndSettle();
      expect(find.text('Only draft tests can be deleted.'), findsOneWidget);
      expect(find.text('Test deleted.'), findsNothing);
      expect(find.text('Draft d-1'), findsOneWidget);
      expect(find.text('open'), findsNothing); // still on the detail route
      expect(c.isDeleted, isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
