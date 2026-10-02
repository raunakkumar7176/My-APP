// Routine V1 — widget tests for the list, today card, create/edit form,
// detail and history screens, plus route registration.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/app/app_router.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/subject.dart';
import 'package:my_praperation/core/models/syllabus_node.dart';
import 'package:my_praperation/features/calendar/domain/calendar_clock.dart';
import 'package:my_praperation/features/routine/screens/routine_create_screen.dart';
import 'package:my_praperation/features/routine/screens/routine_detail_screen.dart';
import 'package:my_praperation/features/routine/screens/routine_history_screen.dart';
import 'package:my_praperation/features/routine/screens/routine_list_screen.dart';
import 'package:my_praperation/features/routine/state/routine_controller.dart';
import 'package:my_praperation/features/routine/widgets/today_routine_card.dart';

import 'fake_routine_repository.dart';

void main() {
  // 2026-09-20 20:00 UTC = Monday 2026-09-21 01:30 IST.
  final nowUtc = DateTime.utc(2026, 9, 20, 20, 0);
  const istToday = '2026-09-21';

  late FakeRoutineRepository repo;
  late RoutineController controller;

  setUp(() {
    repo = FakeRoutineRepository();
    controller = RoutineController(
      repository: repo,
      clock: CalendarClock('Asia/Kolkata', now: () => nowUtc),
      now: () => nowUtc,
    );
  });

  tearDown(() => controller.dispose());

  final subjects = [
    const Subject(id: 's-maths', name: 'Maths'),
    const Subject(id: 's-sci', name: 'Science'),
  ];
  final topics = {
    's-maths': [
      SyllabusNode(id: 'n1', subjectId: 's-maths', name: 'Number System', createdAt: DateTime.utc(2026)),
      SyllabusNode(id: 'n2', subjectId: 's-maths', name: 'Algebra', createdAt: DateTime.utc(2026)),
    ],
    's-sci': [
      SyllabusNode(id: 'n3', subjectId: 's-sci', name: 'Cell', createdAt: DateTime.utc(2026)),
    ],
  };

  /// Scrolls the first Scrollable until [f] is built and visible (lazy lists).
  Future<void> show(WidgetTester t, Finder f, {bool up = false}) async {
    await t.scrollUntilVisible(f, up ? -150 : 150, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
  }

  /// Hosts [home] under a GoRouter so `context.push/pop` work; `/tests/:id`
  /// and `/routine/...` land on a stub page whose text is the location.
  Widget host(Widget home, {List<String> pushed = const []}) {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, _) => home),
        GoRoute(
          path: '/:a',
          builder: (_, s) => Text('at ${s.uri}', key: const Key('stub')),
          routes: [
            GoRoute(path: ':b', builder: (_, s) => Text('at ${s.uri}', key: const Key('stub'))),
          ],
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  group('RoutineListScreen', () {
    testWidgets('loading → empty state', (tester) async {
      await tester.pumpWidget(host(RoutineListScreen(controller: controller)));
      expect(find.byKey(const Key('routine_list_loading')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_list_empty')), findsOneWidget);
      expect(find.text('No routines yet'), findsOneWidget);
    });

    testWidgets('sections: today, other days, paused', (tester) async {
      repo.seed(id: 'today', title: 'Maths · Algebra · Practice', weekdays: [1]);
      repo.seed(id: 'sat', title: 'Weekend reading', weekdays: [6]);
      repo.seed(id: 'paused', title: 'Old habit', isActive: false);
      await tester.pumpWidget(host(RoutineListScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_section_today')), findsOneWidget);
      expect(find.text('Today · Mon'), findsOneWidget);
      expect(find.byKey(const Key('routine_section_upcoming')), findsOneWidget);
      expect(find.byKey(const Key('routine_section_paused')), findsOneWidget);
      expect(find.byKey(const Key('routine_card_today')), findsOneWidget);
      expect(find.byKey(const Key('routine_card_paused')), findsOneWidget);
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('Maths · Algebra · Practice'), findsOneWidget);
    });

    testWidgets('day view: week strip, progress card and current-activity highlight', (tester) async {
      // now = 2026-09-21 01:30 IST (Monday).
      repo.seed(id: 'now', title: 'Live now', startTime: '01:00', endTime: '02:00');
      repo.seed(id: 'later', title: 'Later today', startTime: '03:00', endTime: '04:00');
      await tester.pumpWidget(host(RoutineListScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('routine_week_strip')), findsOneWidget);
      expect(find.byKey(const Key('routine_week_day_2026-09-21')), findsOneWidget);
      expect(find.byKey(const Key('routine_day_progress')), findsOneWidget);
      expect(find.byKey(const Key('routine_current_activity')), findsOneWidget);
      expect(find.textContaining('Now: Live now'), findsOneWidget);
      expect(find.byKey(const Key('routine_card_now')), findsOneWidget);
      expect(find.byKey(const Key('routine_card_later')), findsOneWidget);

      // Browsing to the next day drops the current-activity highlight and
      // loads that date's own items (same [wk]-style routine, real data).
      await tester.tap(find.byKey(const Key('routine_week_day_2026-09-22')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_current_activity')), findsNothing);
    });

    testWidgets('error → retry → list', (tester) async {
      repo.failListWith = const DataError(message: 'Network error');
      await tester.pumpWidget(host(RoutineListScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_list_error')), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      repo.failListWith = null;
      repo.seed(title: 'Back online');
      await tester.tap(find.byKey(const Key('routine_list_retry')));
      await tester.pumpAndSettle();
      expect(find.text('Back online'), findsOneWidget);
    });

    testWidgets('tapping a card opens the detail route; FAB opens create', (tester) async {
      repo.seed(id: 'r-9', title: 'Go');
      await tester.pumpWidget(host(RoutineListScreen(controller: controller)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_card_r-9')));
      await tester.pumpAndSettle();
      expect(find.text('at /routine/r-9'), findsOneWidget);
    });

    testWidgets('reloads when another controller changes a routine (revision bus)', (tester) async {
      await tester.pumpWidget(host(RoutineListScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_list_empty')), findsOneWidget);
      final other = RoutineController(repository: repo, clock: controller.clock);
      await other.createRoutine(title: 'From elsewhere', startTime: '09:00', endTime: '10:00');
      await tester.pumpAndSettle();
      expect(find.text('From elsewhere'), findsOneWidget);
      other.dispose();
    });
  });

  group('TodayRoutineCard', () {
    testWidgets('empty today', (tester) async {
      repo.seed(weekdays: [0]); // Sunday only; today is Monday IST
      await tester.pumpWidget(host(Scaffold(body: TodayRoutineCard(controller: controller))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today_routine_empty')), findsOneWidget);
    });

    testWidgets('progress, complete toggle persists, undo; compact view shows only the next slot', (tester) async {
      repo.seed(id: 'a', title: 'Maths · Lecture', startTime: '07:00', endTime: '08:00', targetDurationMinutes: 45);
      repo.seed(id: 'b', title: 'Science · Revision', startTime: '09:00', endTime: '10:00');
      await tester.pumpWidget(host(Scaffold(body: TodayRoutineCard(controller: controller))));
      await tester.pumpAndSettle();
      expect(find.text('0/2'), findsOneWidget);
      // Dashboard home card is a compact snapshot: only the nearest
      // still-to-come slot ('a', starting first) is shown; a later slot
      // ('b') stays off this card until 'a' is done or past.
      expect(find.byKey(const Key('today_routine_a')), findsOneWidget);
      expect(find.byKey(const Key('today_routine_b')), findsNothing);

      await tester.tap(find.byKey(const Key('today_routine_a')));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(repo.logs['a:$istToday']!.status, 'COMPLETED');
      expect(repo.logs['a:$istToday']!.durationMinutes, 45, reason: 'target duration is logged');
      expect(find.text('Completed (1)'), findsOneWidget);

      // Undo.
      await tester.tap(find.byKey(const Key('today_routine_a')));
      await tester.pumpAndSettle();
      expect(find.text('0/2'), findsOneWidget);
      expect(repo.logs['a:$istToday']!.status, 'PENDING');
    });

    testWidgets('a missed (not completed, already ended) slot never shows on the dashboard card', (tester) async {
      // Clock is 2026-09-21 01:30 IST — this slot ended 30 minutes ago and
      // was never marked complete, matching the real "Ended 21 hrs ago"
      // staleness bug.
      repo.seed(id: 'a', title: 'Late Night Revision', startTime: '00:15', endTime: '01:00');
      await tester.pumpWidget(host(Scaffold(body: TodayRoutineCard(controller: controller))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today_routine_a')), findsNothing);
      expect(find.textContaining('Ended'), findsNothing);
      expect(find.byKey(const Key('today_routine_all_done')), findsOneWidget);
    });

    testWidgets('an ongoing slot still shows even though it started before now', (tester) async {
      repo.seed(id: 'a', title: 'Live Now', startTime: '01:00', endTime: '02:00');
      await tester.pumpWidget(host(Scaffold(body: TodayRoutineCard(controller: controller))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today_routine_a')), findsOneWidget);
      expect(find.byKey(const Key('today_routine_all_done')), findsNothing);
    });

    testWidgets('completion survives a rebuild with a fresh controller (restart)', (tester) async {
      repo.seed(id: 'a');
      await repo.upsertLog(routineId: 'a', logDate: istToday, status: 'COMPLETED');
      final fresh = RoutineController(repository: repo, clock: controller.clock);
      await tester.pumpWidget(host(Scaffold(body: TodayRoutineCard(controller: fresh))));
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      fresh.dispose();
    });

    testWidgets('error → retry', (tester) async {
      repo.failTodayWith = const DataError(message: 'offline');
      await tester.pumpWidget(host(Scaffold(body: TodayRoutineCard(controller: controller))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today_routine_error')), findsOneWidget);
      repo.failTodayWith = null;
      repo.seed(title: 'Recovered');
      await tester.tap(find.byKey(const Key('today_routine_retry')));
      await tester.pumpAndSettle();
      expect(find.text('Recovered'), findsOneWidget);
    });

    testWidgets('failed toggle shows a snackbar and keeps state', (tester) async {
      repo.seed(id: 'a');
      await tester.pumpWidget(host(Scaffold(body: TodayRoutineCard(controller: controller))));
      await tester.pumpAndSettle();
      repo.failLogWith = const DataError(message: 'Could not save');
      await tester.tap(find.byKey(const Key('today_routine_a')));
      await tester.pumpAndSettle();
      expect(find.text('Could not save'), findsOneWidget);
      expect(find.text('0/1'), findsOneWidget);
    });
  });

  group('RoutineCreateScreen', () {
    Widget form({String? routineId}) => RoutineCreateScreen(
      routineId: routineId,
      controller: controller,
      subjectLoader: () async => subjects,
      topicLoader: (id) async => topics[id] ?? const [],
    );

    Future<void> pickSubject(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('routine_subject')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('create with subject, topic and activity composes the title', (tester) async {
      await tester.pumpWidget(host(form()));
      await tester.pumpAndSettle();

      await pickSubject(tester, 'Maths');
      await tester.tap(find.byKey(const Key('routine_topic_s-maths')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number System').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_activity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lecture').last);
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_duration')));
      await tester.enterText(find.byKey(const Key('routine_duration')), '45');
      // The Session Type/Alarm sections added below Duration make the form
      // taller, so the title field's "Shown as" helper (scrolled away above)
      // needs bringing back into view before asserting on it.
      await show(tester, find.byKey(const Key('routine_title')), up: true);
      expect(find.textContaining('Shown as: Number System · Lecture'), findsOneWidget);

      await show(tester, find.byKey(const Key('routine_save')));
      await tester.tap(find.byKey(const Key('routine_save')));
      await tester.pumpAndSettle();

      expect(repo.routines, hasLength(1));
      final r = repo.routines.values.single;
      expect(r.title, 'Number System · Lecture');
      expect(r.subjectId, 's-maths');
      expect(r.targetDurationMinutes, 45);
      expect(r.startTime, '09:00');
      expect(r.endTime, '10:00');
      expect(r.weekdays, [0, 1, 2, 3, 4, 5, 6]);
    });

    testWidgets('invalid duration is refused before anything is saved', (tester) async {
      await tester.pumpWidget(host(form()));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_duration')));
      await tester.enterText(find.byKey(const Key('routine_duration')), '0');
      await show(tester, find.byKey(const Key('routine_save')));
      await tester.tap(find.byKey(const Key('routine_save')));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_form_error')), up: true);
      expect(find.textContaining('positive'), findsOneWidget);
      expect(repo.routines, isEmpty);

      await show(tester, find.byKey(const Key('routine_duration')));
      await tester.enterText(find.byKey(const Key('routine_duration')), '90');
      await show(tester, find.byKey(const Key('routine_save')));
      await tester.tap(find.byKey(const Key('routine_save')));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_form_error')), up: true);
      expect(find.textContaining('longer than the time slot'), findsOneWidget);
      expect(repo.routines, isEmpty);
      expect(repo.calls.where((c) => c == 'hasConflict'), isEmpty);
    });

    testWidgets('no weekday selected is refused', (tester) async {
      await tester.pumpWidget(host(form()));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_weekday_0')));
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byKey(Key('routine_weekday_$i')));
      }
      await tester.pump();
      await show(tester, find.byKey(const Key('routine_save')));
      await tester.tap(find.byKey(const Key('routine_save')));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_form_error')), up: true);
      expect(find.text('Select at least one day'), findsOneWidget);
      expect(repo.routines, isEmpty);
    });

    testWidgets('conflicting time is refused and nothing is overwritten', (tester) async {
      repo.seed(id: 'existing', title: 'Existing', startTime: '09:30', endTime: '10:30');
      await tester.pumpWidget(host(form()));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_save')));
      await tester.tap(find.byKey(const Key('routine_save')));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_form_error')), up: true);
      expect(find.textContaining('overlaps another active routine'), findsOneWidget);
      expect(repo.routines, hasLength(1));
      expect(repo.routines['existing']!.title, 'Existing');
    });

    testWidgets('conflict check failure blocks saving (fail closed)', (tester) async {
      repo.failConflictWith = const DataError(message: 'offline');
      await tester.pumpWidget(host(form()));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_save')));
      await tester.tap(find.byKey(const Key('routine_save')));
      await tester.pumpAndSettle();
      await show(tester, find.byKey(const Key('routine_form_error')), up: true);
      expect(find.text('offline'), findsOneWidget);
      expect(repo.routines, isEmpty);
    });

    testWidgets('edit mode: loads the routine, keeps activity once, saves changes', (tester) async {
      repo.seed(
        id: 'r-1',
        title: 'Morning · Number System · Lecture',
        subjectId: 's-maths',
        startTime: '06:00',
        endTime: '07:00',
        weekdays: [1, 3],
        targetDurationMinutes: 30,
      );
      await tester.pumpWidget(host(form(routineId: 'r-1')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Routine'), findsOneWidget);
      expect((tester.widget(find.byKey(const Key('routine_title'))) as TextFormField).controller!.text, 'Morning');
      expect(find.text('Number System'), findsOneWidget, reason: 'topic recognised from the syllabus');
      expect(find.text('Lecture'), findsOneWidget);
      expect(find.textContaining('Shown as: Morning · Number System · Lecture'), findsOneWidget);

      await show(tester, find.byKey(const Key('routine_duration')));
      await tester.enterText(find.byKey(const Key('routine_duration')), '');
      await show(tester, find.byKey(const Key('routine_save')));
      await tester.tap(find.byKey(const Key('routine_save')));
      await tester.pumpAndSettle();

      final r = repo.routines['r-1']!;
      expect(r.title, 'Morning · Number System · Lecture', reason: 'activity not re-appended');
      expect(r.targetDurationMinutes, isNull, reason: 'cleared duration is persisted as null');
      expect(r.subjectId, 's-maths');
      expect(r.weekdays, [1, 3]);
    });

    testWidgets('edit mode: unknown routine shows retry', (tester) async {
      await tester.pumpWidget(host(form(routineId: 'missing')));
      await tester.pumpAndSettle();
      expect(find.text('Routine not found'), findsOneWidget);
      expect(find.byKey(const Key('routine_form_retry')), findsOneWidget);
    });
  });

  group('RoutineDetailScreen', () {
    Widget detail(String id) => RoutineDetailScreen(
      routineId: id,
      controller: controller,
      subjectLoader: () async => subjects,
    );

    testWidgets('shows study context, schedule, 30-day stats; mark complete / skip', (tester) async {
      repo.seed(
        id: 'r-1',
        title: 'Science · Cell · Revision',
        subjectId: 's-sci',
        weekdays: [1, 2, 3, 4, 5],
        startTime: '18:00',
        endTime: '19:00',
        targetDurationMinutes: 40,
        createdAt: DateTime.utc(2026, 9, 1),
      );
      await tester.pumpWidget(host(detail('r-1')));
      await tester.pumpAndSettle();

      expect(find.text('Science'), findsOneWidget);
      expect(find.text('Revision'), findsOneWidget);
      expect(find.text('Weekdays'), findsOneWidget);
      expect(find.text('60 min slot'), findsOneWidget);
      expect(find.text('40 min target'), findsOneWidget);
      expect(find.byKey(const Key('routine_today_card')), findsOneWidget);
      expect(find.text('Not done yet today'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine_mark_complete')));
      await tester.pumpAndSettle();
      expect(find.text('Completed today'), findsOneWidget);
      expect(repo.logs['r-1:$istToday']!.status, 'COMPLETED');
      expect(repo.logs['r-1:$istToday']!.durationMinutes, 40);
      await show(tester, find.byKey(const Key('routine_stats_text')));
      expect(find.textContaining('scheduled days completed'), findsOneWidget);
      expect(find.textContaining('40 min logged'), findsOneWidget);

      await show(tester, find.byKey(const Key('routine_mark_incomplete')), up: true);
      await tester.tap(find.byKey(const Key('routine_mark_incomplete')));
      await tester.pumpAndSettle();
      expect(find.text('Not done yet today'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine_skip_today')));
      await tester.pumpAndSettle();
      expect(find.text('Skipped today'), findsOneWidget);
    });

    testWidgets('no today card when not scheduled today; pause and resume via menu', (tester) async {
      repo.seed(id: 'r-1', weekdays: [6]);
      await tester.pumpWidget(host(detail('r-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_today_card')), findsNothing);
      expect(find.text('Active'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(repo.routines['r-1']!.isActive, isFalse);
      expect(find.text('Paused'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(repo.routines['r-1']!.isActive, isTrue);
    });

    testWidgets('delete asks for confirmation, then removes and pops', (tester) async {
      repo.seed(id: 'r-1');
      await tester.pumpWidget(host(detail('r-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_menu_delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete Routine'), findsOneWidget);
      expect(repo.routines, hasLength(1), reason: 'nothing deleted before confirming');
      await tester.tap(find.byKey(const Key('routine_delete_confirm')));
      await tester.pumpAndSettle();
      expect(repo.routines, isEmpty);
    });

    testWidgets('not found and error states', (tester) async {
      await tester.pumpWidget(host(detail('nope')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_detail_not_found')), findsOneWidget);
    });
  });

  group('RoutineHistoryScreen', () {
    testWidgets('groups logs by day with done/total badge, titles from paused routines too', (tester) async {
      repo.seed(id: 'a', title: 'Maths · Lecture');
      repo.seed(id: 'b', title: 'Old', isActive: false);
      await repo.upsertLog(routineId: 'a', logDate: istToday, status: 'COMPLETED', durationMinutes: 30);
      await repo.upsertLog(routineId: 'b', logDate: istToday, status: 'SKIPPED');
      await repo.upsertLog(routineId: 'a', logDate: '2026-09-20', status: 'COMPLETED');
      await tester.pumpWidget(host(RoutineHistoryScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.byKey(const Key('routine_history_badge_$istToday')), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('Old'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.byKey(const Key('routine_history_more')), findsNothing, reason: 'fewer than a page');
    });

    testWidgets('filters to one routine when given routineId', (tester) async {
      repo.seed(id: 'a', title: 'Only me');
      repo.seed(id: 'b', title: 'Not me');
      await repo.upsertLog(routineId: 'a', logDate: istToday, status: 'COMPLETED');
      await repo.upsertLog(routineId: 'b', logDate: istToday, status: 'COMPLETED');
      await tester.pumpWidget(host(RoutineHistoryScreen(controller: controller, routineId: 'a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_history_a_$istToday')), findsOneWidget);
      expect(find.byKey(const Key('routine_history_b_$istToday')), findsNothing);
    });

    testWidgets('empty, error and retry', (tester) async {
      repo.failHistoryWith = const DataError(message: 'offline');
      await tester.pumpWidget(host(RoutineHistoryScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_history_error')), findsOneWidget);
      repo.failHistoryWith = null;
      await tester.tap(find.byKey(const Key('routine_history_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_history_empty')), findsOneWidget);
    });
  });

  test('routine routes are registered (static history before :routineId)', () {
    List<String> paths(List<RouteBase> routes, [String prefix = '']) {
      final out = <String>[];
      for (final r in routes) {
        if (r is GoRoute) {
          final full = r.path.startsWith('/') ? r.path : '$prefix/${r.path}';
          out.add(full);
          out.addAll(paths(r.routes, full));
        } else {
          out.addAll(paths(r.routes, prefix));
        }
      }
      return out;
    }

    final all = paths(AppRouter.router.configuration.routes);
    expect(all, containsAll(['/routine', '/routine/create', '/routine/history', '/routine/:routineId', '/routine/:routineId/edit']));
    expect(all.indexOf('/routine/history'), lessThan(all.indexOf('/routine/:routineId')));
  });
}
