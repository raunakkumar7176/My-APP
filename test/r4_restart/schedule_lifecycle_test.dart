// Schedule/lifecycle audit (2026-09-16): a published Self test showed
// "not started" while the device clock was inside its window. Root cause was
// timezone handling on the write path + local-time display; these tests pin
// the whole chain: parse -> phase -> block reason -> write payload -> resume.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/test_repository.dart';
import 'package:my_praperation/features/test/domain/test_lifecycle.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';
import 'package:my_praperation/features/test/widgets/test_formatters.dart';

import 'fakes.dart';

void main() {
  // Window: 17:04Z .. 18:04Z (= 22:34 .. 23:34 IST, the screenshot case).
  final startsAt = DateTime.utc(2026, 9, 16, 17, 4);
  final endsAt = DateTime.utc(2026, 9, 16, 18, 4);
  const minute = Duration(minutes: 1);

  String? reason(TestStatus status, DateTime now, {bool lateJoin = false}) =>
      TestLifecycle.startBlockReason(
        status: status,
        startsAt: startsAt,
        endsAt: endsAt,
        now: now,
        allowLateJoin: lateJoin,
      );

  group('SchedulePhase boundaries (mirror _fn_start_attempt_core)', () {
    test('1 minute before starts_at -> notStarted', () {
      expect(TestLifecycle.phase(startsAt: startsAt, endsAt: endsAt, now: startsAt.subtract(minute)),
          SchedulePhase.notStarted);
    });
    test('exactly at starts_at -> active (server: now() < starts_at blocks)', () {
      expect(TestLifecycle.phase(startsAt: startsAt, endsAt: endsAt, now: startsAt),
          SchedulePhase.active);
    });
    test('1 minute after starts_at -> active', () {
      expect(TestLifecycle.phase(startsAt: startsAt, endsAt: endsAt, now: startsAt.add(minute)),
          SchedulePhase.active);
    });
    test('exactly at ends_at -> active (server: now() > ends_at ends)', () {
      expect(TestLifecycle.phase(startsAt: startsAt, endsAt: endsAt, now: endsAt),
          SchedulePhase.active);
    });
    test('1 minute after ends_at -> ended', () {
      expect(TestLifecycle.phase(startsAt: startsAt, endsAt: endsAt, now: endsAt.add(minute)),
          SchedulePhase.ended);
    });
    test('no window -> always active', () {
      expect(TestLifecycle.phase(startsAt: null, endsAt: null, now: startsAt),
          SchedulePhase.active);
    });
    test('phase compares instants: a local-zone "now" gives the same answer', () {
      final localNow = startsAt.add(minute).toLocal();
      expect(localNow.isUtc, isFalse);
      expect(TestLifecycle.phase(startsAt: startsAt, endsAt: endsAt, now: localNow),
          SchedulePhase.active);
    });
  });

  group('startBlockReason by status x window', () {
    test('published + future start -> "Test starts at", Start disabled', () {
      final r = reason(TestStatus.published, startsAt.subtract(minute));
      expect(r, startsWith('Test starts at'));
    });
    test('published + active window -> startable', () {
      expect(reason(TestStatus.published, startsAt.add(minute)), isNull);
      expect(reason(TestStatus.published, startsAt), isNull);
      expect(reason(TestStatus.published, endsAt), isNull);
    });
    test('published + expired window -> "Test ended."', () {
      expect(reason(TestStatus.published, endsAt.add(minute)), 'Test ended.');
    });
    test('scheduled + active window -> startable', () {
      expect(reason(TestStatus.scheduled, startsAt.add(minute)), isNull);
    });
    test('scheduled + expired window -> ended (server applies ends_at to every status)', () {
      expect(reason(TestStatus.scheduled, endsAt.add(minute)), 'Test ended.');
    });
    test('live + expired window -> "Test ended."', () {
      expect(reason(TestStatus.live, endsAt.add(minute)), 'Test ended.');
    });
    test('live + future start -> not started (server applies starts_at to every status)', () {
      expect(reason(TestStatus.live, startsAt.subtract(minute)), startsWith('Test starts at'));
    });
    test('expired window + allow_late_join -> startable (mirrors server)', () {
      expect(reason(TestStatus.published, endsAt.add(minute), lateJoin: true), isNull);
    });
    test('terminal statuses stay blocked regardless of window', () {
      for (final s in [TestStatus.completed, TestStatus.ended, TestStatus.evaluated]) {
        expect(reason(s, startsAt.add(minute)), 'This test has ended.');
      }
      expect(reason(TestStatus.draft, startsAt.add(minute)), contains('draft'));
    });
  });

  group('timezone conversion', () {
    test('timestamptz with +00:00 parses to the same instant, exposed in local time', () {
      final t = Test.fromJson({
        'id': 't', 'created_by': 'u', 'title': 'jai', 'status': 'published',
        'starts_at': '2026-09-16T17:04:00+00:00',
        'ends_at': '2026-09-16T18:04:00+00:00',
      });
      expect(t.startsAt!.isUtc, isFalse);
      expect(t.startsAt!.toUtc(), startsAt);
      expect(t.endsAt!.toUtc(), endsAt);
      // The formatter prints local wall-clock, i.e. what the user picked.
      final local = startsAt.toLocal();
      expect(TestFormatters.dateTime(t.startsAt),
          '${local.day}/${local.month}/${local.year} ${local.hour}:${local.minute.toString().padLeft(2, '0')}');
      // Same output whether given the UTC or local representation.
      expect(TestFormatters.dateTime(startsAt), TestFormatters.dateTime(t.startsAt));
    });

    test('Z suffix and explicit offsets map to the same instant', () {
      final a = parseTimestamp('2026-09-16T17:04:00Z')!;
      final b = parseTimestamp('2026-09-16T22:34:00+05:30')!;
      expect(a, b);
      expect(a.toUtc(), startsAt);
    });

    test('write payload carries an explicit UTC offset (never a naive local string)', () {
      final picked = DateTime(2026, 9, 16, 22, 34); // local picker value
      final input = TestWriteInput(
        title: 'jai', testMode: 'self', settings: const {},
        startsAt: picked, endsAt: picked.add(const Duration(hours: 1)),
      );
      final p = input.toCreateParams();
      final sent = p['p_starts_at'] as String;
      expect(sent, endsWith('Z'));
      expect(DateTime.parse(sent), picked.toUtc());
      expect(Test(id: 't', createdBy: 'u', title: 'x', status: TestStatus.draft, startsAt: picked)
          .toJson()['starts_at'], endsWith('Z'));
    });

    test('a naive local string sent to timestamptz would shift the instant (the old bug)', () {
      final picked = DateTime(2026, 9, 16, 22, 34);
      final naive = picked.toIso8601String(); // no offset
      final asServerWouldStore = DateTime.parse('${naive}Z'); // session tz UTC
      expect(asServerWouldStore.difference(picked.toUtc()),
          DateTime.now().timeZoneOffset, // = the shift users saw
          skip: DateTime.now().timeZoneOffset == Duration.zero
              ? 'host runs in UTC; shift is zero here'
              : false);
    });
  });

  group('TestDetailController', () {
    Test jai({TestStatus status = TestStatus.published, String mode = 'self', String? join}) =>
        Test(
          id: 't-1', createdBy: 'u-1', title: 'jai', status: status, testMode: mode,
          durationSec: 3600, startsAt: startsAt, endsAt: endsAt, accessCode: 'x', joinCode: join,
        );

    TestDetailController make(Test t, DateTime now) => TestDetailController(
          testId: 't-1',
          tests: FakeTestRepository()..rows['t-1'] = t,
          questions: FakeQuestionRepository(),
          attempts: FakeAttemptRepository(),
          results: FakeResultRepository(),
          currentUserId: () => 'u-1',
          clock: () => now,
        );

    test('inside window: startable, phase active (screenshot scenario)', () async {
      final c = make(jai(), startsAt.add(const Duration(minutes: 6)).toLocal());
      await c.load();
      expect(c.phase, SchedulePhase.active);
      expect(c.startBlockReason(), isNull);
    });

    test('before window: "Test starts at" with local formatting', () async {
      final c = make(jai(), startsAt.subtract(minute));
      await c.load();
      expect(c.phase, SchedulePhase.notStarted);
      expect(c.startBlockReason(formatDateTime: TestFormatters.dateTime),
          'Test starts at ${TestFormatters.dateTime(startsAt)}.');
    });

    test('after window: "Test ended."', () async {
      final c = make(jai(), endsAt.add(minute));
      await c.load();
      expect(c.phase, SchedulePhase.ended);
      expect(c.startBlockReason(), 'Test ended.');
    });

    test('join code hidden for Self, shown for Challenge with Friends', () async {
      final self = make(jai(join: 'ABCD'), startsAt);
      await self.load();
      expect(self.showsJoinCode, isFalse);
      final live = make(jai(mode: 'live', join: 'ABCD'), startsAt);
      await live.load();
      expect(live.showsJoinCode, isTrue);
    });

    test('existing in_progress attempt: server resume is passed through untouched', () async {
      final attempts = FakeAttemptRepository()
        ..next = Attempt(
          id: 'a-old', testId: 't-1', userId: 'u-1', status: AttemptStatus.inProgress,
          startedAt: startsAt, deadlineAt: endsAt, attemptNumber: 1,
        );
      final c = TestDetailController(
        testId: 't-1',
        tests: FakeTestRepository()..rows['t-1'] = jai(),
        questions: FakeQuestionRepository(),
        attempts: attempts,
        results: FakeResultRepository(),
        currentUserId: () => 'u-1',
        clock: () => startsAt.add(minute),
      );
      await c.load();
      final launched = await c.start();
      expect(attempts.calls, ['start:t-1']);
      expect(launched.started.attempt.id, 'a-old');
      expect(launched.started.attempt.status, AttemptStatus.inProgress);
    });
  });
}
