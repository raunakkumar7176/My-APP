// Routine V1 — controller behaviour against the in-memory repository.
//
// "Today" is injected through CalendarClock(now:) so every date assertion is
// deterministic and independent of the machine running the tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/features/calendar/domain/calendar_clock.dart';
import 'package:my_praperation/features/routine/state/routine_controller.dart';

import 'fake_routine_repository.dart';

void main() {
  late FakeRoutineRepository repo;
  late RoutineController controller;

  // 2026-09-20 20:00 UTC = 2026-09-21 01:30 IST (Monday, live weekday 1).
  final nowUtc = DateTime.utc(2026, 9, 20, 20, 0);
  CalendarClock ist() => CalendarClock('Asia/Kolkata', now: () => nowUtc);
  const istToday = '2026-09-21';
  const istWeekday = 1;

  setUp(() {
    repo = FakeRoutineRepository();
    controller = RoutineController(repository: repo, clock: ist(), now: () => nowUtc);
  });

  tearDown(() => controller.dispose());

  group('timezone / date behaviour', () {
    test('today is the profile-zone day, not the UTC/device day', () {
      expect(controller.todayDate, istToday);
      expect(controller.todayWeekday, istWeekday);
      // The same instant is still Sunday the 20th in UTC.
      final utc = RoutineController(
        repository: repo,
        clock: CalendarClock('UTC', now: () => nowUtc),
      );
      expect(utc.todayDate, '2026-09-20');
      expect(utc.todayWeekday, 0);
      utc.dispose();
    });

    test('loadToday asks the repository for the user-zone date and weekday', () async {
      await controller.loadToday();
      expect(repo.calls, contains('getToday:$istToday:$istWeekday'));
    });

    test('markComplete logs on the user-zone date', () async {
      repo.seed(id: 'r-1');
      await controller.markComplete('r-1');
      expect(repo.logs.keys, contains('r-1:$istToday'));
      expect(repo.logs.keys, isNot(contains('r-1:2026-09-20')));
    });
  });

  group('loadAll', () {
    test('returns active and paused routines, active first', () async {
      repo.seed(id: 'a', startTime: '10:00');
      repo.seed(id: 'b', startTime: '08:00', isActive: false);
      repo.seed(id: 'c', startTime: '09:00');
      await controller.loadAll();
      expect(controller.allRoutines.map((r) => r.id), ['c', 'a', 'b']);
      expect(controller.activeRoutines.map((r) => r.id), ['c', 'a']);
      expect(controller.pausedRoutines.map((r) => r.id), ['b']);
      expect(controller.error, isNull);
    });

    test('sets error on failure and clears loading', () async {
      repo.failListWith = const DataError(message: 'Network error');
      await controller.loadAll();
      expect(controller.error, 'Network error');
      expect(controller.isLoading, isFalse);
      expect(controller.allRoutines, isEmpty);
    });

    test('retry after failure succeeds', () async {
      repo.failListWith = const DataError(message: 'boom');
      await controller.loadAll();
      expect(controller.error, isNotNull);
      repo.failListWith = null;
      repo.seed();
      await controller.loadAll();
      expect(controller.error, isNull);
      expect(controller.allRoutines, hasLength(1));
    });
  });

  group('create', () {
    test('creates, refreshes the list and bumps the revision', () async {
      final before = RoutineController.revision.value;
      final id = await controller.createRoutine(
        title: 'Maths · Number System · Lecture',
        startTime: '09:00',
        endTime: '10:00',
        weekdays: [1, 3, 5],
        subjectId: 's-maths',
        targetDurationMinutes: 45,
      );
      expect(id, isNotNull);
      expect(controller.allRoutines, hasLength(1));
      final r = controller.allRoutines.single;
      expect(r.title, 'Maths · Number System · Lecture');
      expect(r.subjectId, 's-maths');
      expect(r.weekdays, [1, 3, 5]);
      expect(r.targetDurationMinutes, 45);
      expect(RoutineController.revision.value, before + 1);
    });

    test('rethrows so the form can show the message', () async {
      repo.failCreateWith = const DataError(message: 'Failed to save routine.');
      await expectLater(
        controller.createRoutine(title: 'x', startTime: '09:00', endTime: '10:00'),
        throwsA(isA<DataError>()),
      );
    });
  });

  group('edit', () {
    test('updates fields and can clear subject and target duration', () async {
      repo.seed(id: 'r-1', subjectId: 's-1', targetDurationMinutes: 30);
      await controller.updateRoutine(
        id: 'r-1',
        title: 'Science · Cell · Revision',
        startTime: '14:00',
        endTime: '15:00',
        weekdays: [0, 6],
        clearSubject: true,
        clearTargetDuration: true,
      );
      final r = repo.routines['r-1']!;
      expect(r.title, 'Science · Cell · Revision');
      expect(r.startTime, '14:00');
      expect(r.endTime, '15:00');
      expect(r.weekdays, [0, 6]);
      expect(r.subjectId, isNull);
      expect(r.targetDurationMinutes, isNull);
    });

    test('null fields leave values untouched', () async {
      repo.seed(id: 'r-1', subjectId: 's-1', targetDurationMinutes: 30, title: 'Keep');
      await controller.updateRoutine(id: 'r-1', reminderEnabled: false);
      final r = repo.routines['r-1']!;
      expect(r.title, 'Keep');
      expect(r.subjectId, 's-1');
      expect(r.targetDurationMinutes, 30);
      expect(r.reminderEnabled, isFalse);
    });

    test('rethrows on failure', () async {
      repo.seed(id: 'r-1');
      repo.failUpdateWith = const DataError(message: 'nope');
      await expectLater(
        controller.updateRoutine(id: 'r-1', title: 'x'),
        throwsA(isA<DataError>()),
      );
    });
  });

  group('delete / disable', () {
    test('deactivate keeps the routine and its logs but marks it paused', () async {
      repo.seed(id: 'r-1');
      await controller.markComplete('r-1');
      await controller.deactivateRoutine('r-1');
      expect(repo.routines['r-1']!.isActive, isFalse);
      expect(repo.logs, hasLength(1));
      await controller.loadToday();
      expect(controller.todayItems, isEmpty, reason: 'paused routines are not due today');
    });

    test('activate resumes a paused routine', () async {
      repo.seed(id: 'r-1', isActive: false);
      await controller.activateRoutine('r-1');
      expect(repo.routines['r-1']!.isActive, isTrue);
    });

    test('delete removes the routine (logs cascade) and refreshes', () async {
      repo.seed(id: 'r-1');
      await controller.markComplete('r-1');
      await controller.deleteRoutine('r-1');
      expect(repo.routines, isEmpty);
      expect(repo.logs, isEmpty);
      expect(controller.allRoutines, isEmpty);
    });

    test('delete rethrows on failure', () async {
      repo.seed(id: 'r-1');
      repo.failDeleteWith = const DataError(message: 'denied');
      await expectLater(controller.deleteRoutine('r-1'), throwsA(isA<DataError>()));
    });
  });

  group("today's tasks", () {
    test('only active routines scheduled on the user-zone weekday, by start time', () async {
      repo.seed(id: 'mon-late', weekdays: [1], startTime: '18:00');
      repo.seed(id: 'mon-early', weekdays: [1], startTime: '06:00');
      repo.seed(id: 'tue', weekdays: [2]);
      repo.seed(id: 'paused-mon', weekdays: [1], isActive: false);
      await controller.loadToday();
      expect(controller.todayItems.map((i) => i.routine.id), ['mon-early', 'mon-late']);
      expect(controller.totalCount, 2);
    });

    test('empty when nothing is scheduled today', () async {
      repo.seed(weekdays: [0]);
      await controller.loadToday();
      expect(controller.todayItems, isEmpty);
      expect(controller.error, isNull);
    });

    test('error and retry', () async {
      repo.failTodayWith = const DataError(message: 'offline');
      await controller.loadToday();
      expect(controller.error, 'offline');
      repo.failTodayWith = null;
      repo.seed();
      await controller.loadToday();
      expect(controller.error, isNull);
      expect(controller.todayItems, hasLength(1));
    });

    test('upNext is the first pending item that has not started yet', () async {
      // 01:30 IST now → everything is still ahead; earliest pending wins.
      repo.seed(id: 'a', startTime: '09:00');
      repo.seed(id: 'b', startTime: '07:00');
      repo.seed(id: 'c', startTime: '06:00');
      await controller.markComplete('c');
      expect(controller.upNext!.routine.id, 'b');
    });

    test('loadToday and loadAll do not block each other', () async {
      repo.seed();
      await Future.wait([controller.loadToday(), controller.loadAll()]);
      expect(controller.todayItems, hasLength(1));
      expect(controller.allRoutines, hasLength(1));
    });
  });

  group('completion', () {
    test('markComplete writes a COMPLETED log with duration and refreshes today', () async {
      repo.seed(id: 'r-1', targetDurationMinutes: 45);
      await controller.markComplete('r-1', durationMinutes: 45);
      final log = repo.logs['r-1:$istToday']!;
      expect(log.status, 'COMPLETED');
      expect(log.completed, isTrue);
      expect(log.durationMinutes, 45);
      expect(controller.todayItems.single.isCompleted, isTrue);
      expect(controller.completedCount, 1);
      expect(controller.completionPercentage, 1.0);
    });

    test('markIncomplete reverts the same day to PENDING (same log row)', () async {
      repo.seed(id: 'r-1');
      await controller.markComplete('r-1');
      final firstId = repo.logs['r-1:$istToday']!.id;
      await controller.markIncomplete('r-1');
      final log = repo.logs['r-1:$istToday']!;
      expect(log.id, firstId, reason: 'upsert on (routine_id, log_date), no duplicate row');
      expect(log.status, 'PENDING');
      expect(log.completed, isFalse);
      expect(controller.todayItems.single.isCompleted, isFalse);
    });

    test('skipRoutine sets SKIPPED', () async {
      repo.seed(id: 'r-1');
      await controller.skipRoutine('r-1');
      expect(repo.logs['r-1:$istToday']!.status, 'SKIPPED');
      expect(controller.todayItems.single.isSkipped, isTrue);
    });

    test('completion percentage over several routines', () async {
      repo.seed(id: 'a');
      repo.seed(id: 'b');
      repo.seed(id: 'c');
      repo.seed(id: 'd');
      await controller.loadToday();
      expect(controller.completionPercentage, 0);
      await controller.markComplete('a');
      expect(controller.completionPercentage, 0.25);
      await controller.markComplete('b');
      expect(controller.completedCount, 2);
      expect(controller.completionPercentage, 0.5);
    });

    test('persistence: a fresh controller on the same repository sees the completion', () async {
      repo.seed(id: 'r-1');
      await controller.markComplete('r-1');
      final restarted = RoutineController(repository: repo, clock: ist());
      await restarted.loadToday();
      expect(restarted.todayItems.single.isCompleted, isTrue);
      restarted.dispose();
    });

    test('logging failure rethrows and leaves state unchanged', () async {
      repo.seed(id: 'r-1');
      await controller.loadToday();
      repo.failLogWith = const DataError(message: 'offline');
      await expectLater(controller.markComplete('r-1'), throwsA(isA<DataError>()));
      expect(controller.todayItems.single.isCompleted, isFalse);
    });
  });

  group('conflict validation', () {
    test('detects an overlapping active routine on a shared weekday', () async {
      repo.seed(startTime: '09:00', endTime: '10:00', weekdays: [1, 2]);
      expect(
        await controller.hasConflict(startTime: '09:30', endTime: '10:30', weekdays: [2]),
        isTrue,
      );
    });

    test('no conflict on different days, adjacent times, or paused routines', () async {
      repo.seed(startTime: '09:00', endTime: '10:00', weekdays: [1]);
      repo.seed(startTime: '11:00', endTime: '12:00', weekdays: [3], isActive: false);
      expect(
        await controller.hasConflict(startTime: '09:00', endTime: '10:00', weekdays: [2]),
        isFalse,
      );
      expect(
        await controller.hasConflict(startTime: '10:00', endTime: '11:00', weekdays: [1]),
        isFalse,
      );
      expect(
        await controller.hasConflict(startTime: '11:00', endTime: '12:00', weekdays: [3]),
        isFalse,
      );
    });

    test('excludes the routine being edited', () async {
      repo.seed(id: 'r-1', startTime: '09:00', endTime: '10:00', weekdays: [1]);
      expect(
        await controller.hasConflict(
          startTime: '09:00',
          endTime: '10:00',
          weekdays: [1],
          excludeId: 'r-1',
        ),
        isFalse,
      );
    });

    test('fails closed: a failing check throws instead of returning false', () async {
      repo.failConflictWith = const DataError(message: 'offline');
      await expectLater(
        controller.hasConflict(startTime: '09:00', endTime: '10:00', weekdays: [1]),
        throwsA(isA<DataError>()),
      );
    });
  });

  group('history and stats', () {
    test('history is newest first and can be filtered by routine', () async {
      repo.seed(id: 'a');
      repo.seed(id: 'b');
      await repo.upsertLog(routineId: 'a', logDate: '2026-09-18', status: 'COMPLETED');
      await repo.upsertLog(routineId: 'b', logDate: '2026-09-19', status: 'SKIPPED');
      await repo.upsertLog(routineId: 'a', logDate: '2026-09-20', status: 'COMPLETED');
      final all = await controller.getHistory();
      expect(all.map((l) => l.logDate), ['2026-09-20', '2026-09-19', '2026-09-18']);
      final onlyA = await controller.getHistory(routineId: 'a');
      expect(onlyA.map((l) => l.routineId).toSet(), {'a'});
      expect(onlyA, hasLength(2));
    });

    test('history failure throws (screen shows retry)', () async {
      repo.failHistoryWith = const DataError(message: 'offline');
      await expectLater(controller.getHistory(), throwsA(isA<DataError>()));
    });

    test('statsFor counts only scheduled days since creation', () async {
      // Created 2026-09-15 (Tue); Mon/Wed/Fri; window = 30 days to 2026-09-21.
      final r = repo.seed(
        id: 'r-1',
        weekdays: [1, 3, 5],
        createdAt: DateTime.utc(2026, 9, 14, 20, 0), // 15 Sep 01:30 IST
      );
      // Scheduled since creation: Wed 16, Fri 18, Mon 21 → 3 days.
      await repo.upsertLog(routineId: 'r-1', logDate: '2026-09-16', status: 'COMPLETED', durationMinutes: 40);
      await repo.upsertLog(routineId: 'r-1', logDate: '2026-09-18', status: 'SKIPPED');
      final s = await controller.statsFor(r);
      expect(s.scheduledDays, 3);
      expect(s.completedDays, 1);
      expect(s.skippedDays, 1);
      expect(s.loggedMinutes, 40);
      expect(s.completionRate, closeTo(1 / 3, 1e-9));
    });

    test('statsFor with no scheduled days is 0 without dividing by zero', () async {
      final r = repo.seed(id: 'r-1', weekdays: [1], createdAt: DateTime.utc(2030));
      final s = await controller.statsFor(r);
      expect(s.scheduledDays, 0);
      expect(s.completionRate, 0);
    });
  });

  group('authorization (RLS analogue)', () {
    test('only the current user\'s routines and logs are visible', () async {
      repo.seed(id: 'mine');
      repo.seed(id: 'theirs', userId: 'u-2');
      await repo.upsertLog(routineId: 'mine', logDate: istToday, status: 'COMPLETED');
      repo.currentUser = 'u-2';
      await repo.upsertLog(routineId: 'theirs', logDate: istToday, status: 'COMPLETED');
      repo.currentUser = 'u-1';

      await controller.loadAll();
      expect(controller.allRoutines.map((r) => r.id), ['mine']);
      await controller.loadToday();
      expect(controller.todayItems.map((i) => i.routine.id), ['mine']);
      expect((await controller.getHistory()).map((l) => l.routineId), ['mine']);
      expect(await controller.getById('theirs'), isNull);
    });

    test('cannot log completion for another user\'s routine', () async {
      repo.seed(id: 'theirs', userId: 'u-2');
      await expectLater(controller.markComplete('theirs'), throwsA(isA<StateError>()));
    });

    test('updating another user\'s routine changes nothing', () async {
      repo.seed(id: 'theirs', userId: 'u-2', title: 'Untouched');
      await controller.updateRoutine(id: 'theirs', title: 'Hacked');
      expect(repo.routines['theirs']!.title, 'Untouched');
    });
  });

  group('repeat schedule', () {
    test('a weekday-only routine is due on Monday but not on Sunday', () async {
      repo.seed(id: 'wk', weekdays: [1, 2, 3, 4, 5]);
      await controller.loadToday(); // Monday IST
      expect(controller.todayItems.map((i) => i.routine.id), ['wk']);

      final sunday = RoutineController(
        repository: repo,
        clock: CalendarClock('Asia/Kolkata', now: () => DateTime.utc(2026, 9, 19, 20, 0)),
      );
      expect(sunday.todayWeekday, 0);
      await sunday.loadToday();
      expect(sunday.todayItems, isEmpty);
      sunday.dispose();
    });

    test('scheduledOn lists what is due on another weekday (upcoming)', () async {
      repo.seed(id: 'sat', weekdays: [6]);
      repo.seed(id: 'daily');
      await controller.loadAll();
      expect(controller.scheduledOn(6).map((r) => r.id), containsAll(['sat', 'daily']));
      expect(controller.scheduledOn(2).map((r) => r.id), ['daily']);
    });
  });
}
