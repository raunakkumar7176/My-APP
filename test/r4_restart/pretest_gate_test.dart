// Instructions/disclaimer gate before a NEW attempt, copy join code for the
// owner of a Challenge with Friends, optional deletion reason.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/screens/test_detail_screen.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';

import 'fakes.dart';

Test _t({String mode = 'self', String? join, TestStatus status = TestStatus.published,
    String owner = 'creator'}) =>
    Test(
      id: 't-1', createdBy: owner, title: 'Gate', status: status, testMode: mode,
      durationSec: 600, negativeMarks: 0.25, instructions: 'No calculators.',
      joinCode: join, accessCode: null,
    );

({TestDetailController c, FakeAttemptRepository a, FakeTestRepository t}) _make({
  Test? row,
  String user = 'u-1',
}) {
  final t = FakeTestRepository()..rows['t-1'] = row ?? _t();
  final a = FakeAttemptRepository()..currentUser = user;
  final c = TestDetailController(
    testId: 't-1', tests: t, questions: FakeQuestionRepository(), attempts: a,
    results: FakeResultRepository(), currentUserId: () => user,
    clock: () => DateTime(2026, 9, 17, 12),
  );
  return (c: c, a: a, t: t);
}

Widget _app(TestDetailController c) => MaterialApp.router(
      routerConfig: GoRouter(initialLocation: '/tests/t-1', routes: [
        GoRoute(path: '/tests/:id', builder: (_, _) => TestDetailScreen(testId: 't-1', controller: c)),
        GoRoute(path: '/attempts/:id/take', builder: (_, _) => const Scaffold(body: Text('TAKING'))),
      ]),
    );

void main() {
  testWidgets('Start Test shows the instructions gate; Cancel starts nothing', (tester) async {
    final d = _make();
    await tester.pumpWidget(_app(d.c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Test'));
    await tester.pumpAndSettle();
    expect(find.text('Before you start'), findsOneWidget);
    expect(find.textContaining('No calculators.'), findsWidgets); // pre-test row + dialog
    expect(find.textContaining('Negative marking: 0.25'), findsOneWidget);
    expect(find.text('• Attempts: Single attempt.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(d.a.calls.where((x) => x.startsWith('start:')), isEmpty);
    expect(find.text('TAKING'), findsNothing);
  });

  testWidgets('confirming the gate starts attempt 1 and navigates to taking', (tester) async {
    final d = _make();
    await tester.pumpWidget(_app(d.c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Start Test')));
    await tester.pumpAndSettle();
    expect(d.a.calls, contains('start:t-1'));
    expect(find.text('TAKING'), findsOneWidget);
  });

  testWidgets('Continue Test (in_progress) skips the gate and resumes', (tester) async {
    final d = _make();
    await d.a.start('t-1'); // in_progress exists
    await tester.pumpWidget(_app(d.c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue Test'));
    await tester.pumpAndSettle();
    expect(find.text('Before you start'), findsNothing);
    expect(find.text('TAKING'), findsOneWidget);
    expect(d.a.rows.length, 1);
  });

  testWidgets('owner of a Challenge with Friends can copy the join code', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final d = _make(row: _t(mode: 'live', join: 'ABCD', owner: 'u-1'));
    await tester.pumpWidget(_app(d.c));
    await tester.pumpAndSettle();
    expect(find.text('ABCD'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy join code'));
    await tester.pumpAndSettle();
    expect(copied, ['ABCD']);
    expect(find.text('Join code copied'), findsOneWidget);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('delete dialog passes an optional reason to the RPC', (tester) async {
    final d = _make(row: _t(status: TestStatus.draft, owner: 'u-1'));
    await tester.pumpWidget(_app(d.c));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Test'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('delete_reason')), 'duplicate draft');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete Test'));
    await tester.pumpAndSettle();
    expect(d.t.lastDeleteReason, 'duplicate draft');
    expect(d.t.rows['t-1']!.isSoftDeleted, isTrue);
  });
}
