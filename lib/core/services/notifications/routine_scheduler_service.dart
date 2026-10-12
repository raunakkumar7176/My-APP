import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../features/routine/data/routine_repository.dart';
import '../../../features/routine/state/routine_controller.dart';
import '../../logging/app_logger.dart';
import '../../models/routine.dart';
import '../push_notification_service.dart';
import '../settings/library_mode_controller.dart';

/// Top-level background action handler for notification buttons.
@pragma('vm:entry-point')
void routineBackgroundNotificationResponseHandler(NotificationResponse details) {
  RoutineSchedulerService.handleBackgroundAction(details);
}

/// Exact-time local notifications for Routine slots matching Google Tasks:
/// - Punctual & reliable alarms (SCHEDULE_EXACT_ALARM, androidAllowWhileIdle)
/// - Actionable notification buttons: [ ✅ Done ] and [ ⏳ +10 Mins ]
/// - Channel with raw resource audio ('routine_start.mp3') and Library Mode awareness
/// - Auto-reschedule active slots on launch and boot
class RoutineSchedulerService {
  RoutineSchedulerService._();
  static final RoutineSchedulerService instance = RoutineSchedulerService._();

  static const String channelId = 'channel_routine_start';
  static const String channelName = 'Routine Slot Reminders';
  static const String channelDesc = 'Exact time reminders for study routines';

  static const String actionDone = 'mark_done';
  static const String actionSnooze = 'snooze_10';

  static const String _pendingDonePrefsKey = 'routine_pending_done_ids';

  FlutterLocalNotificationsPlugin get _local =>
      PushNotificationService.instance.local;

  /// Initializes timezone and notification channels if not already done.
  Future<void> init() async {
    try {
      await PushNotificationService.instance.initialize();
      await syncPendingCompletions();
    } catch (e, st) {
      AppLogger.warning('RoutineSchedulerService init error: $e', stackTrace: st);
    }
  }

  /// Stable per-(routine, weekday) notification id — distinct from the
  /// plain `slotId.hashCode` id used for a daily (all-7-days) slot, and
  /// distinct from the snooze id, so none of the three ever collide and
  /// silently overwrite each other's scheduled entry.
  static int _idFor(String slotId, int weekday) =>
      Object.hash(slotId, 'weekday', weekday) & 0x7fffffff;

  static int _snoozeIdFor(String slotId) =>
      Object.hash(slotId, 'snooze') & 0x7fffffff;

  /// The next TZDateTime on or after [weekday] (0=Sun..6=Sat) at the slot's
  /// start time (minus lead minutes). Used to seed a recurring schedule for
  /// that one weekday — `matchDateTimeComponents: dayOfWeekAndTime` then
  /// keeps it firing every week on its own.
  tz.TZDateTime _nextOccurrenceForWeekday(Routine slot, int weekday) {
    final now = tz.TZDateTime.now(tz.local);
    final parts = slot.startTime.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (slot.alarmLeadMinutes > 0) {
      scheduledDate = scheduledDate.subtract(Duration(minutes: slot.alarmLeadMinutes));
    }
    while (scheduledDate.isBefore(now) || scheduledDate.weekday % 7 != weekday) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  NotificationDetails _slotDetails(bool isLibraryMode) => NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          sound: const RawResourceAndroidNotificationSound('routine_start'),
          playSound: !isLibraryMode,
          enableVibration: true,
          category: AndroidNotificationCategory.alarm,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              actionDone,
              '✅ Done',
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              actionSnooze,
              '⏳ +10 Mins',
              showsUserInterface: false,
            ),
          ],
        ),
      );

  /// Schedules an exact-time, recurring notification with action buttons
  /// for [slot]. A 7-day slot gets ONE daily-recurring entry; a slot that
  /// only recurs on some weekdays (e.g. Mon/Wed/Fri) gets ONE entry PER
  /// weekday it recurs on — `zonedSchedule` + `dayOfWeekAndTime` can only
  /// repeat on a single weekday per call, so one call for the "next
  /// matching day" alone would silently never fire on the others.
  Future<bool> scheduleSlot(Routine slot) async {
    await cancelSlot(slot.id);
    if (!slot.isActive || slot.weekdays.isEmpty) return false;
    try {
      final isLibraryMode = LibraryModeController.instance.isLibraryMode;
      final title = slot.title.isNotEmpty ? slot.title : 'Study Routine';
      final subtitle = '$title padhai ka time shuru ho gaya hai!';
      final details = _slotDetails(isLibraryMode);

      if (slot.weekdays.length == 7) {
        final tzScheduledTime = _nextOccurrenceForWeekday(
          slot,
          tz.TZDateTime.now(tz.local).weekday % 7,
        );
        await _local.zonedSchedule(
          slot.id.hashCode,
          '⏰ Routine Time: $title',
          subtitle,
          tzScheduledTime,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: slot.id,
        );
      } else {
        for (final weekday in slot.weekdays) {
          final tzScheduledTime = _nextOccurrenceForWeekday(slot, weekday);
          await _local.zonedSchedule(
            _idFor(slot.id, weekday),
            '⏰ Routine Time: $title',
            subtitle,
            tzScheduledTime,
            details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: slot.id,
          );
        }
      }

      AppLogger.info('Scheduled routine slot ${slot.id} on weekdays ${slot.weekdays}');
      return true;
    } catch (e, st) {
      AppLogger.error('Failed to schedule routine slot ${slot.id}: $e',
          stackTrace: st);
      return false;
    }
  }

  /// Cancels every notification entry this service could have scheduled
  /// for [slotId]: the daily-slot id, every per-weekday id, and the snooze
  /// id — regardless of how it was last scheduled (its weekday set may
  /// have changed since), so a stale entry never keeps firing.
  Future<void> cancelSlot(String slotId) async {
    try {
      await _local.cancel(slotId.hashCode);
      await _local.cancel(_snoozeIdFor(slotId));
      for (var weekday = 0; weekday < 7; weekday++) {
        await _local.cancel(_idFor(slotId, weekday));
      }
    } catch (e) {
      AppLogger.warning('Failed to cancel routine slot $slotId: $e');
    }
  }

  /// Reschedules all active routines with reminder or alarm enabled.
  Future<void> rescheduleAllActive(List<Routine> slots) async {
    for (final slot in slots) {
      if (slot.isActive && (slot.hasAlarm || slot.reminderEnabled)) {
        await scheduleSlot(slot);
      } else {
        await cancelSlot(slot.id);
      }
    }
  }

  /// Handles 'mark_done' action: records completion in Supabase and triggers feedback.
  static Future<void> handleDoneAction(String routineId) async {
    if (routineId.isEmpty) return;
    try {
      // 1. Play celebration haptic and sound
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);

      // 2. Dismiss/cancel the alarm notification
      unawaited(RoutineSchedulerService.instance.cancelSlot(routineId));

      // 3. Persist log to Supabase
      final today = DateTime.now();
      final logDate =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      const repo = SupabaseRoutineRepository();
      await repo.upsertLog(
        routineId: routineId,
        logDate: logDate,
        status: 'COMPLETED',
      );

      // 4. Notify open UI controllers
      RoutineController.revision.value++;
      AppLogger.info('Routine $routineId marked COMPLETED from notification action.');
    } catch (e, st) {
      AppLogger.error('handleDoneAction error: $e', stackTrace: st);
      // Store offline to sync later
      await _storePendingDone(routineId);
    }
  }

  /// Handles 'snooze_10' action: schedules reminder 10 minutes from now.
  static Future<void> handleSnoozeAction(String routineId) async {
    if (routineId.isEmpty) return;
    try {
      final isLibraryMode = LibraryModeController.instance.isLibraryMode;
      final snoozeTime =
          tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
      final details = RoutineSchedulerService.instance._slotDetails(isLibraryMode);

      // A dedicated id (never the slot's own recurring id) — otherwise this
      // one-shot entry would overwrite the slot's recurring schedule and it
      // would never fire again until the next full resync.
      await RoutineSchedulerService.instance._local.zonedSchedule(
        _snoozeIdFor(routineId),
        '⏰ Snoozed Routine Reminder',
        'Study session remind: 10 minute ho gaye!',
        snoozeTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: routineId,
      );

      AppLogger.info('Snoozed routine $routineId for 10 minutes.');
    } catch (e, st) {
      AppLogger.error('handleSnoozeAction error: $e', stackTrace: st);
    }
  }

  /// Background handler entry point (no BuildContext).
  @pragma('vm:entry-point')
  static Future<void> handleBackgroundAction(NotificationResponse details) async {
    final routineId = details.payload ?? '';
    if (details.actionId == actionDone) {
      await _storePendingDone(routineId);
      // Attempt immediate background upsert
      try {
        final today = DateTime.now();
        final logDate =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        const repo = SupabaseRoutineRepository();
        await repo.upsertLog(
          routineId: routineId,
          logDate: logDate,
          status: 'COMPLETED',
        );
      } catch (_) {}
    } else if (details.actionId == actionSnooze) {
      await handleSnoozeAction(routineId);
    }
  }

  static Future<void> _storePendingDone(String routineId) async {
    if (routineId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingDonePrefsKey) ?? [];
      if (!list.contains(routineId)) {
        list.add(routineId);
        await prefs.setStringList(_pendingDonePrefsKey, list);
      }
    } catch (_) {}
  }

  /// Flushes any pending offline completions to Supabase.
  static Future<void> syncPendingCompletions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingDonePrefsKey) ?? [];
      if (list.isEmpty) return;

      final today = DateTime.now();
      final logDate =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      const repo = SupabaseRoutineRepository();

      for (final id in list) {
        await repo.upsertLog(
          routineId: id,
          logDate: logDate,
          status: 'COMPLETED',
        );
      }
      await prefs.remove(_pendingDonePrefsKey);
      RoutineController.revision.value++;
    } catch (e) {
      AppLogger.warning('syncPendingCompletions failed: $e');
    }
  }
}
