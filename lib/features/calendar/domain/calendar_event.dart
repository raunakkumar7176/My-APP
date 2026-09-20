import '../../../core/models/test.dart';
import 'calendar_clock.dart';

/// A routine as the calendar needs it — the live `public.routines` columns
/// the calendar reads (`id, title, subject_id, start_time, end_time,
/// weekdays, is_active, created_at`). Kept local to the calendar so the
/// Routine feature's own models can evolve independently.
final class CalendarRoutine {
  const CalendarRoutine({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.weekdays,
    required this.isActive,
    required this.createdAt,
    this.subjectId,
  });

  final String id;
  final String title;

  /// `HH:MM[:SS]` wall-clock strings exactly as stored (`time without time zone`).
  final String startTime;
  final String endTime;

  /// Live encoding: 0 = Sunday … 6 = Saturday.
  final List<int> weekdays;
  final bool isActive;
  final DateTime createdAt;
  final String? subjectId;

  factory CalendarRoutine.fromJson(Map<String, dynamic> json) => CalendarRoutine(
    id: json['id'] as String,
    title: (json['title'] as String?)?.trim().isNotEmpty == true
        ? (json['title'] as String).trim()
        : 'Study routine',
    startTime: (json['start_time'] as String?) ?? '00:00',
    endTime: (json['end_time'] as String?) ?? '00:00',
    weekdays: [for (final w in (json['weekdays'] as List? ?? const [])) (w as num).toInt()],
    isActive: json['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    subjectId: json['subject_id'] as String?,
  );

  static String hhmm(String t) => t.length >= 5 ? t.substring(0, 5) : t;
}

/// One `public.routine_logs` row (`routine_id, log_date, status, completed,
/// duration_minutes`). `status` ∈ COMPLETED | SKIPPED | MISSED | PENDING.
final class CalendarRoutineLog {
  const CalendarRoutineLog({
    required this.routineId,
    required this.logDate,
    required this.status,
    this.durationMinutes,
  });

  final String routineId;

  /// Date-only (UTC-flagged) — the user's local day as stored by the server.
  final DateTime logDate;
  final String status;
  final int? durationMinutes;

  bool get isCompleted => status == 'COMPLETED';

  factory CalendarRoutineLog.fromJson(Map<String, dynamic> json) => CalendarRoutineLog(
    routineId: json['routine_id'] as String,
    logDate: CalendarDates.parseIso(json['log_date'] as String),
    status: (json['status'] as String?) ?? (json['completed'] == true ? 'COMPLETED' : 'PENDING'),
    durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
  );
}

enum CalendarEventKind { routine, test }

/// Completion / lifecycle state shown on the agenda.
enum CalendarEventState { scheduled, completed, skipped, missed, live, ended, cancelled }

/// One agenda item on one user-zone calendar day. Derived, never stored.
final class CalendarEvent implements Comparable<CalendarEvent> {
  const CalendarEvent({
    required this.id,
    required this.kind,
    required this.day,
    required this.title,
    required this.state,
    this.startsAt,
    this.endsAt,
    this.timeLabel,
    this.subtitle,
    this.testId,
    this.routineId,
  });

  final String id;
  final CalendarEventKind kind;

  /// User-zone calendar day (date-only, UTC-flagged).
  final DateTime day;
  final String title;
  final CalendarEventState state;

  /// Real instants (tests) — null for routines, which are wall-clock only.
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// `HH:MM` (– `HH:MM`) in the user's zone.
  final String? timeLabel;
  final String? subtitle;
  final String? testId;
  final String? routineId;

  bool get isDone => state == CalendarEventState.completed;

  /// Sort key inside a day: by wall-clock time label, routines before tests
  /// at equal times.
  @override
  int compareTo(CalendarEvent other) {
    final t = (timeLabel ?? '').compareTo(other.timeLabel ?? '');
    if (t != 0) return t;
    return kind.index.compareTo(other.kind.index);
  }
}

/// Pure builder: expands routines over the month's days (weekday recurrence,
/// active or logged, not before creation) and maps tests to the user-zone day
/// of `starts_at`. Nothing is persisted; the server rows stay authoritative.
abstract final class CalendarEventBuilder {
  static List<CalendarEvent> build({
    required CalendarClock clock,
    required int year,
    required int month,
    required List<CalendarRoutine> routines,
    required List<CalendarRoutineLog> logs,
    required List<Test> tests,
  }) {
    final out = <CalendarEvent>[];
    final logByKey = {for (final l in logs) '${l.routineId}|${CalendarDates.iso(l.logDate)}': l};
    final days = CalendarDates.daysInMonth(year, month);
    for (var d = 1; d <= days; d++) {
      final day = CalendarDates.date(year, month, d);
      final wd = CalendarDates.liveWeekday(day);
      for (final r in routines) {
        final log = logByKey['${r.id}|${CalendarDates.iso(day)}'];
        final created = clock.dayOf(r.createdAt);
        final scheduledToday = r.weekdays.contains(wd) && !day.isBefore(created) && r.isActive;
        if (!scheduledToday && log == null) continue;
        final state = switch (log?.status) {
          'COMPLETED' => CalendarEventState.completed,
          'SKIPPED' => CalendarEventState.skipped,
          'MISSED' => CalendarEventState.missed,
          _ => CalendarEventState.scheduled,
        };
        out.add(CalendarEvent(
          id: 'routine:${r.id}:${CalendarDates.iso(day)}',
          kind: CalendarEventKind.routine,
          day: day,
          title: r.title,
          state: state,
          timeLabel: '${CalendarRoutine.hhmm(r.startTime)} – ${CalendarRoutine.hhmm(r.endTime)}',
          subtitle: log?.durationMinutes != null ? '${log!.durationMinutes} min logged' : null,
          routineId: r.id,
        ));
      }
    }
    for (final t in tests) {
      final s = t.startsAt;
      if (s == null) continue;
      final day = clock.dayOf(s);
      if (day.year != year || day.month != month) continue;
      final state = switch (t.status) {
        TestStatus.live => CalendarEventState.live,
        TestStatus.ended || TestStatus.completed || TestStatus.evaluated => CalendarEventState.ended,
        TestStatus.cancelled || TestStatus.archived || TestStatus.expired => CalendarEventState.cancelled,
        _ => CalendarEventState.scheduled,
      };
      final end = t.endsAt;
      out.add(CalendarEvent(
        id: 'test:${t.id}',
        kind: CalendarEventKind.test,
        day: day,
        title: t.title,
        state: state,
        startsAt: s,
        endsAt: end,
        timeLabel: end == null
            ? clock.timeLabel(s)
            : '${clock.timeLabel(s)} – ${clock.timeLabel(end)}',
        subtitle: t.groupId != null ? 'Group test' : 'Test',
        testId: t.id,
      ));
    }
    out.sort((a, b) {
      final d = a.day.compareTo(b.day);
      return d != 0 ? d : a.compareTo(b);
    });
    return out;
  }
}
