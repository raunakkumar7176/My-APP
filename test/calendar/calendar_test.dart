// Calendar V1 — client tests over an in-memory repository that mirrors the
// live rows (routines: weekly recurrence with weekdays 0=Sun..6=Sat and
// wall-clock start/end; routine_logs: log_date + status; tests: starts_at /
// ends_at instants). The user-zone clock is Asia/Kolkata (+05:30) unless a
// test says otherwise; `now` is injected so "today" is deterministic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/app/app_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/calendar/data/calendar_repository.dart';
import 'package:my_praperation/features/calendar/domain/calendar_clock.dart';
import 'package:my_praperation/features/calendar/domain/calendar_event.dart';
import 'package:my_praperation/features/calendar/screens/calendar_screen.dart';
import 'package:my_praperation/features/calendar/state/calendar_controller.dart';

class FakeCalendarRepository implements CalendarRepository {
  final List<CalendarRoutine> routines_ = [];
  final List<CalendarRoutineLog> logs_ = [];
  final List<Test> tests_ = [];
  final List<String> calls = [];
  Object? failNextWith;
  Duration delay = Duration.zero;

  void _fail() {
    final f = failNextWith;
    if (f != null) {
      failNextWith = null;
      throw f;
    }
  }

  @override
  Future<List<CalendarRoutine>> routines() async {
    calls.add('routines');
    await Future<void>.delayed(delay);
    _fail();
    return List.of(routines_);
  }

  @override
  Future<List<CalendarRoutineLog>> routineLogs({required DateTime from, required DateTime to}) async {
    calls.add('logs:${CalendarDates.iso(from)}..${CalendarDates.iso(to)}');
    return [for (final l in logs_) if (!l.logDate.isBefore(from) && !l.logDate.isAfter(to)) l];
  }

  @override
  Future<List<Test>> testsBetween({required DateTime startUtc, required DateTime endUtc, int limit = 200}) async {
    calls.add('tests:${startUtc.toIso8601String()}..${endUtc.toIso8601String()}');
    return [
      for (final t in tests_)
        if (t.startsAt != null && !t.startsAt!.isBefore(startUtc) && t.startsAt!.isBefore(endUtc)) t,
    ];
  }
}

// Fixed "now": 2026-09-20 10:00 IST == 04:30 UTC.
final DateTime nowUtc = DateTime.utc(2026, 9, 20, 4, 30);
CalendarClock ist() => CalendarClock('Asia/Kolkata', now: () => nowUtc);

CalendarRoutine routine({String id = 'r1', String title = 'Physics', List<int> weekdays = const [0, 1, 2, 3, 4, 5, 6], bool active = true, DateTime? createdAt}) => CalendarRoutine(
  id: id,
  title: title,
  startTime: '16:15:00',
  endTime: '17:00:00',
  weekdays: weekdays,
  isActive: active,
  createdAt: createdAt ?? DateTime.utc(2026, 8, 1),
);

Test testAt(String id, DateTime startsAt, {TestStatus status = TestStatus.scheduled, DateTime? endsAt, String? groupId}) =>
    Test(id: id, createdBy: 'u', title: 'Test $id', status: status, startsAt: startsAt, endsAt: endsAt, groupId: groupId, durationSec: 600);

CalendarController ctl(FakeCalendarRepository repo, {DateTime? initialDay, CalendarClock? clock}) =>
    CalendarController(repository: repo, clock: clock ?? ist(), initialDay: initialDay);

void main() {
  group('CalendarClock (user timezone, no device dependence)', () {
    test('Asia/Kolkata is fixed-offset; instants map to the user day', () {
      final c = ist();
      expect(c.usesDeviceFallback, isFalse);
      // 2026-09-20 20:00 UTC == 2026-09-21 01:30 IST → next day for the user.
      expect(CalendarDates.iso(c.dayOf(DateTime.utc(2026, 9, 20, 20))), '2026-09-21');
      expect(c.timeLabel(DateTime.utc(2026, 9, 20, 20)), '01:30');
      expect(CalendarDates.iso(c.today()), '2026-09-20');
    });

    test('midnight and month boundary: 18:30 UTC on the 30th is the 1st for the user', () {
      final c = ist();
      expect(CalendarDates.iso(c.dayOf(DateTime.utc(2026, 9, 30, 18, 30))), '2026-10-01');
      expect(CalendarDates.iso(c.dayOf(DateTime.utc(2026, 9, 30, 18, 29))), '2026-09-30');
      final r = c.monthRange(2026, 9);
      expect(r.start, DateTime.utc(2026, 8, 31, 18, 30));
      expect(r.end, DateTime.utc(2026, 9, 30, 18, 30));
      final dec = c.monthRange(2026, 12);
      expect(dec.end, DateTime.utc(2026, 12, 31, 18, 30));
    });

    test('fromUserWall round-trips and Kathmandu (+05:45) differs from IST', () {
      final c = ist();
      expect(c.fromUserWall(2026, 9, 20, 0, 0), DateTime.utc(2026, 9, 19, 18, 30));
      final k = CalendarClock('Asia/Kathmandu', now: () => nowUtc);
      expect(k.timeLabel(DateTime.utc(2026, 9, 20, 4, 30)), '10:15');
    });

    test('unknown / DST zone falls back to device time and says so; blank → default', () {
      final e = CalendarClock('Europe/London', now: () => nowUtc);
      expect(e.usesDeviceFallback, isTrue);
      expect(CalendarClock(null).timezoneName, 'Asia/Kolkata');
      expect(CalendarClock('  ').usesDeviceFallback, isFalse);
    });

    test('month grid: 6×7, Monday first, covers the month', () {
      final g = CalendarDates.monthGrid(2026, 9); // Sept 1 2026 is a Tuesday
      expect(g.length, 42);
      expect(CalendarDates.iso(g.first), '2026-08-31');
      expect(g.first.weekday, DateTime.monday);
      expect(g.any((d) => CalendarDates.iso(d) == '2026-09-30'), isTrue);
      expect(CalendarDates.liveWeekday(CalendarDates.date(2026, 9, 20)), 0); // Sunday → 0
      expect(CalendarDates.liveWeekday(CalendarDates.date(2026, 9, 21)), 1);
    });
  });

  group('CalendarEventBuilder', () {
    test('routine recurs on its weekdays only, not before creation, inactive only via logs', () {
      final c = ist();
      final events = CalendarEventBuilder.build(
        clock: c, year: 2026, month: 9,
        routines: [
          routine(id: 'mon', title: 'Mondays', weekdays: [1]),
          routine(id: 'late', title: 'Late', createdAt: DateTime.utc(2026, 9, 15, 12)),
          routine(id: 'off', title: 'Inactive', active: false),
        ],
        logs: [CalendarRoutineLog(routineId: 'off', logDate: CalendarDates.date(2026, 9, 3), status: 'COMPLETED', durationMinutes: 30)],
        tests: const [],
      );
      final mon = events.where((e) => e.routineId == 'mon').map((e) => e.day.day).toList();
      expect(mon, [7, 14, 21, 28]);
      final late = events.where((e) => e.routineId == 'late').map((e) => e.day.day).toList();
      expect(late.first, 15);
      expect(late.length, 16);
      final off = events.where((e) => e.routineId == 'off').toList();
      expect(off.length, 1);
      expect(off.single.state, CalendarEventState.completed);
      expect(off.single.subtitle, '30 min logged');
      expect(off.single.timeLabel, '16:15 – 17:00');
    });

    test('routine states follow routine_logs status', () {
      final c = ist();
      final events = CalendarEventBuilder.build(
        clock: c, year: 2026, month: 9, routines: [routine()],
        logs: [
          CalendarRoutineLog(routineId: 'r1', logDate: CalendarDates.date(2026, 9, 1), status: 'COMPLETED'),
          CalendarRoutineLog(routineId: 'r1', logDate: CalendarDates.date(2026, 9, 2), status: 'SKIPPED'),
          CalendarRoutineLog(routineId: 'r1', logDate: CalendarDates.date(2026, 9, 3), status: 'MISSED'),
          CalendarRoutineLog(routineId: 'r1', logDate: CalendarDates.date(2026, 9, 4), status: 'PENDING'),
        ],
        tests: const [],
      );
      CalendarEventState st(int d) => events.firstWhere((e) => e.day.day == d).state;
      expect(st(1), CalendarEventState.completed);
      expect(st(2), CalendarEventState.skipped);
      expect(st(3), CalendarEventState.missed);
      expect(st(4), CalendarEventState.scheduled);
      expect(st(5), CalendarEventState.scheduled);
      expect(events.firstWhere((e) => e.day.day == 1).isDone, isTrue);
    });

    test('tests land on the user-zone day of starts_at with state from status', () {
      final c = ist();
      final events = CalendarEventBuilder.build(
        clock: c, year: 2026, month: 9, routines: const [], logs: const [],
        tests: [
          testAt('a', DateTime.utc(2026, 9, 20, 20), endsAt: DateTime.utc(2026, 9, 20, 21), groupId: 'g'), // 21 Sep IST
          testAt('b', DateTime.utc(2026, 9, 10, 4), status: TestStatus.live),
          testAt('c', DateTime.utc(2026, 9, 11, 4), status: TestStatus.ended),
          testAt('d', DateTime.utc(2026, 9, 12, 4), status: TestStatus.cancelled),
          testAt('e', DateTime.utc(2026, 10, 1, 4)), // other month → excluded
        ],
      );
      final a = events.firstWhere((e) => e.testId == 'a');
      expect(a.day.day, 21);
      expect(a.timeLabel, '01:30 – 02:30');
      expect(a.subtitle, 'Group test');
      expect(events.firstWhere((e) => e.testId == 'b').state, CalendarEventState.live);
      expect(events.firstWhere((e) => e.testId == 'c').state, CalendarEventState.ended);
      expect(events.firstWhere((e) => e.testId == 'd').state, CalendarEventState.cancelled);
      expect(events.any((e) => e.testId == 'e'), isFalse);
    });

    test('multiple events on one day are ordered by time', () {
      final c = ist();
      final events = CalendarEventBuilder.build(
        clock: c, year: 2026, month: 9, routines: [routine()], logs: const [],
        tests: [testAt('t', DateTime.utc(2026, 9, 20, 3))], // 08:30 IST, before the 16:15 routine
      );
      final day = events.where((e) => e.day.day == 20).toList();
      expect(day.map((e) => e.kind), [CalendarEventKind.test, CalendarEventKind.routine]);
    });
  });

  group('CalendarController', () {
    test('initial month is today; one bounded load per month (routines, logs, tests)', () async {
      final repo = FakeCalendarRepository()..routines_.add(routine())..tests_.add(testAt('t', DateTime.utc(2026, 9, 25, 4)));
      final c = ctl(repo);
      expect(c.monthTitle, 'September 2026');
      expect(CalendarDates.iso(c.selectedDay), '2026-09-20');
      await c.load();
      expect(repo.calls, [
        'routines',
        'logs:2026-09-01..2026-09-30',
        'tests:2026-08-31T18:30:00.000Z..2026-09-30T18:30:00.000Z',
      ]);
      expect(c.selectedDayEvents.length, 1); // routine today
      expect(c.eventsOn(CalendarDates.date(2026, 9, 25)).length, 2);
      expect(c.error, isNull);
      expect(c.hasLoaded, isTrue);
      c.dispose();
    });

    test('next / previous month reload with the new range; selection is kept inside the month', () async {
      final repo = FakeCalendarRepository();
      final c = ctl(repo);
      await c.load();
      await c.nextMonth();
      expect(c.monthTitle, 'October 2026');
      expect(CalendarDates.iso(c.selectedDay), '2026-10-01');
      expect(repo.calls.last, 'tests:2026-09-30T18:30:00.000Z..2026-10-31T18:30:00.000Z');
      await c.previousMonth();
      await c.previousMonth();
      expect(c.monthTitle, 'August 2026');
      await c.previousMonth(); // year boundary backwards
      for (var i = 0; i < 7; i++) {
        await c.previousMonth();
      }
      expect(c.monthTitle, 'December 2025');
      c.dispose();
    });

    test('today returns to the current month and selects today', () async {
      final repo = FakeCalendarRepository();
      final c = ctl(repo);
      await c.load();
      await c.nextMonth();
      await c.nextMonth();
      await c.goToToday();
      expect(c.monthTitle, 'September 2026');
      expect(CalendarDates.iso(c.selectedDay), '2026-09-20');
      c.dispose();
    });

    test('selecting a leading/trailing grid day switches month', () async {
      final repo = FakeCalendarRepository();
      final c = ctl(repo);
      await c.load();
      c.selectDay(CalendarDates.date(2026, 8, 31)); // shown in September's grid
      expect(c.monthTitle, 'August 2026');
      expect(CalendarDates.iso(c.selectedDay), '2026-08-31');
      c.dispose();
    });

    test('empty day and error/retry', () async {
      final repo = FakeCalendarRepository();
      final c = ctl(repo, initialDay: CalendarDates.date(2026, 9, 5));
      repo.failNextWith = const DataError(message: 'Network error. Please check your connection and try again.');
      await c.load();
      expect(c.error, contains('Network error'));
      expect(c.events, isEmpty);
      await c.load(); // retry
      expect(c.error, isNull);
      expect(c.selectedDayEvents, isEmpty);
      c.dispose();
    });

    test('a superseded load never overwrites the newer month', () async {
      final repo = FakeCalendarRepository()..delay = const Duration(milliseconds: 20);
      repo.tests_.add(testAt('sep', DateTime.utc(2026, 9, 25, 4)));
      final c = ctl(repo);
      final first = c.load();
      final second = c.nextMonth();
      await Future.wait([first, second]);
      expect(c.monthTitle, 'October 2026');
      expect(c.events.any((e) => e.testId == 'sep'), isFalse);
      c.dispose();
    });
  });

  group('CalendarScreen', () {
    Future<CalendarController> pump(WidgetTester tester, FakeCalendarRepository repo, {DateTime? initialDay, CalendarClock? clock}) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ctl(repo, initialDay: initialDay, clock: clock);
      await tester.pumpWidget(MaterialApp(home: CalendarScreen(controller: c)));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('renders month, markers, agenda with routine and test events and states', (tester) async {
      final repo = FakeCalendarRepository()
        ..routines_.add(routine())
        ..logs_.add(CalendarRoutineLog(routineId: 'r1', logDate: CalendarDates.date(2026, 9, 20), status: 'COMPLETED'))
        ..tests_.add(testAt('t1', DateTime.utc(2026, 9, 20, 3)));
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('calendar_month_title')), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.byKey(const Key('routine_dot_2026-09-20')), findsOneWidget);
      expect(find.byKey(const Key('test_dot_2026-09-20')), findsOneWidget);
      expect(find.text('Today · 20 September'), findsOneWidget);
      expect(find.byKey(const Key('calendar_event_test:t1')), findsOneWidget);
      expect(find.byKey(const Key('calendar_event_routine:r1:2026-09-20')), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.byKey(const Key('calendar_empty_day')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('empty day, day selection, prev/next/today', (tester) async {
      final repo = FakeCalendarRepository()..tests_.add(testAt('t1', DateTime.utc(2026, 9, 25, 4)));
      final c = await pump(tester, repo);
      expect(find.byKey(const Key('calendar_empty_day')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_day_2026-09-25')));
      await tester.pumpAndSettle();
      expect(find.text('25 September 2026'), findsOneWidget);
      expect(find.byKey(const Key('calendar_event_test:t1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_next')));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_prev')));
      await tester.tap(find.byKey(const Key('calendar_prev')));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_today')));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('Today · 20 September'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('loading, error and retry states', (tester) async {
      final repo = FakeCalendarRepository()..delay = const Duration(milliseconds: 50);
      repo.failNextWith = const DataError(message: 'Could not load your calendar. Please try again.');
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ctl(repo);
      await tester.pumpWidget(MaterialApp(home: CalendarScreen(controller: c)));
      await tester.pump();
      expect(find.byKey(const Key('calendar_loading')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_error')), findsNothing);
      expect(find.byKey(const Key('calendar_empty_day')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('device-fallback zone shows the timezone note', (tester) async {
      final repo = FakeCalendarRepository();
      final c = await pump(tester, repo, clock: CalendarClock('Europe/London', now: () => nowUtc));
      expect(find.byKey(const Key('calendar_tz_note')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  test('route /calendar is registered', () {
    bool has(List<RouteBase> routes) => routes.any((r) => (r is GoRoute && r.path == '/calendar') || has(r.routes));
    expect(has(AppRouter.router.configuration.routes), isTrue);
  });
}
