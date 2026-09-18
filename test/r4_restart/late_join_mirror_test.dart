// Detail mirrors the server's LATE_JOIN_NOT_ALLOWED rule for Challenge with
// Friends now that the client can read its own attempts.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';

import 'fakes.dart';

void main() {
  final startsAt = DateTime.utc(2026, 9, 17, 9);
  Test live({bool lateJoin = false}) => Test(
    id: 't-1',
    createdBy: 'creator',
    title: 'C',
    status: TestStatus.published,
    testMode: 'live',
    durationSec: 600,
    startsAt: startsAt,
    endsAt: startsAt.add(const Duration(hours: 2)),
    allowLateJoin: lateJoin,
  );
  TestDetailController make(FakeTestRepository t, FakeAttemptRepository a) =>
      TestDetailController(
        testId: 't-1',
        tests: t,
        questions: FakeQuestionRepository(),
        attempts: a,
        results: FakeResultRepository(),
        currentUserId: () => 'u-1',
        clock: () => startsAt.add(const Duration(minutes: 5)),
      );

  test(
    'after starts_at without late join: blocked before calling the server',
    () async {
      final c = make(
        FakeTestRepository()..rows['t-1'] = live(),
        FakeAttemptRepository(),
      );
      await c.load();
      expect(
        c.startBlockReason(),
        'This challenge has already started and does not allow late joining.',
      );
    },
  );

  test('late join allowed, or Self mode: not blocked', () async {
    final c = make(
      FakeTestRepository()..rows['t-1'] = live(lateJoin: true),
      FakeAttemptRepository(),
    );
    await c.load();
    expect(c.startBlockReason(), isNull);
  });

  test('in_progress attempt keeps resume available', () async {
    final a = FakeAttemptRepository();
    await a.start('t-1');
    final c = make(FakeTestRepository()..rows['t-1'] = live(), a);
    await c.load();
    expect(c.startBlockReason(), isNull);
    expect(c.attemptState!.inProgress, isNotNull);
  });
}
