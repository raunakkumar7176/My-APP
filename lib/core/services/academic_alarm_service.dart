import 'package:timezone/timezone.dart' as tz;

import '../logging/app_logger.dart';
import '../models/routine.dart';
import 'push_notification_service.dart';

/// Schedules exact-time local alarms for the next 14 days of a user's
/// alarm-enabled routine sessions (`routines.has_alarm`, migration 0068).
/// Owns only "which occurrences need an alarm and when" — the actual
/// scheduling/full-screen-intent mechanics live in [PushNotificationService],
/// reusing its already-initialized `flutter_local_notifications` plugin
/// instance rather than adding a second native alarm package
/// (`android_alarm_manager_plus`/`alarm`) alongside it.
abstract final class AcademicAlarmService {
  static const _rollingWindowDays = 14;

  /// Deterministic per-occurrence notification id: stable across re-runs
  /// (same routine + same date always maps to the same id), so re-scheduling
  /// the same occurrence twice just overwrites it instead of duplicating it.
  static int _occurrenceId(String routineId, DateTime date) =>
      Object.hash(routineId, date.year, date.month, date.day) & 0x7fffffff;

  /// Cancels and re-schedules every alarm-enabled routine's next 14 days of
  /// occurrences. Call after any routine create/update/delete, and once on
  /// app start for the signed-in user. [routines] is the caller's already
  /// loaded routine list (this service never fetches its own copy, so it
  /// never disagrees with what the Routine/Calendar screens show).
  static Future<void> resyncAlarms(List<Routine> routines) async {
    final alarmRoutines = routines.where((r) => r.hasAlarm && r.isActive).toList();
    if (alarmRoutines.isEmpty) return;

    // Best-effort, always: a timezone-database/plugin hiccup (e.g. this
    // runs before PushNotificationService.initialize() has set up
    // `tz.local`, which is a real possible race on cold start, not just a
    // test artifact) must never break the routine create/edit/delete flow
    // that calls this.
    try {
      final now = tz.TZDateTime.now(tz.local);
      for (final routine in alarmRoutines) {
        final start = _parseTime(routine.startTime);
        if (start == null) continue;

        for (var offset = 0; offset < _rollingWindowDays; offset++) {
          final date = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
          final liveWeekday = date.weekday % 7; // DateTime: Mon=1..Sun=7 -> 0..6, Sun=0
          if (!routine.isScheduledOn(liveWeekday)) continue;

          final alarmAt = tz.TZDateTime(
            tz.local,
            date.year,
            date.month,
            date.day,
            start.$1,
            start.$2,
          ).subtract(Duration(minutes: routine.alarmLeadMinutes));
          if (alarmAt.isBefore(now)) continue;

          final id = _occurrenceId(routine.id, date);
          final payload = _deepLinkFor(routine);
          await PushNotificationService.instance.scheduleExactNotification(
            id: id,
            title: '⏰ Time for ${routine.title.isNotEmpty ? routine.title : routine.sessionTypeLabel}',
            body: routine.alarmLeadMinutes > 0
                ? 'Starts in ${routine.alarmLeadMinutes} minutes'
                : 'Your session starts now',
            scheduledDate: alarmAt,
            payload: payload,
          );
        }
      }
    } catch (e, st) {
      AppLogger.warning('AcademicAlarmService.resyncAlarms failed: $e', error: e, stackTrace: st);
    }
  }

  /// Cancels every alarm this service could plausibly have scheduled for
  /// [routine] in the rolling window — call before deleting a routine or
  /// turning its alarm off.
  static Future<void> cancelAlarmsFor(Routine routine) async {
    final now = DateTime.now();
    for (var offset = 0; offset < _rollingWindowDays; offset++) {
      final date = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
      await PushNotificationService.instance.cancelScheduledNotification(
        _occurrenceId(routine.id, date),
      );
    }
  }

  static String _deepLinkFor(Routine routine) {
    if (routine.topicId != null) {
      return '/study/topic/${routine.topicId}/practice';
    }
    if (routine.subjectId != null) {
      return '/study/subject/${routine.subjectId}';
    }
    return '/routine/${routine.id}';
  }

  /// Parses `HH:MM`/`HH:MM:SS` into (hour, minute); null if malformed.
  static (int, int)? _parseTime(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return (h, m);
  }
}
