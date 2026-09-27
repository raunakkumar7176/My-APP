import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/routine.dart';
import '../../../core/models/routine_log.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/routine_schedule.dart';

/// Repository for the R3 `routines` and `routine_logs` tables.
///
/// SECURITY:
/// - Every query runs under the live RLS policies (`own routine`,
///   `own routine logs`): a user only ever sees or writes their own rows.
/// - `user_id` is filled server-side (default `auth.uid()`); the client never
///   sends or filters by it. No policy is widened here.
///
/// DATES: the repository never computes "today". Callers pass the user-zone
/// date (`YYYY-MM-DD`) and live weekday (0 = Sunday … 6 = Saturday) so the
/// profile timezone — not the device clock — decides which day a log is on.
abstract interface class RoutineRepository {
  /// All of the caller's routines (active first, then by start time).
  /// Paused routines are included so they can be resumed or deleted.
  Future<List<Routine>> list();

  /// One routine, or null when it does not exist / is not the caller's.
  Future<Routine?> getById(String id);

  /// Creates a routine and returns its id.
  Future<String> create({
    required String title,
    required String startTime,
    required String endTime,
    List<int> weekdays = const [0, 1, 2, 3, 4, 5, 6],
    String? subjectId,
    bool reminderEnabled = true,
    int? targetDurationMinutes,
    String? chapterId,
    String? topicId,
    String sessionType = 'study',
    bool hasAlarm = false,
    int alarmLeadMinutes = 0,
  });

  /// Updates the given fields. Null means "leave unchanged"; use
  /// [clearSubject] / [clearTargetDuration] to null a column explicitly.
  Future<void> update({
    required String id,
    String? title,
    String? startTime,
    String? endTime,
    List<int>? weekdays,
    String? subjectId,
    bool clearSubject = false,
    bool? reminderEnabled,
    bool? isActive,
    int? targetDurationMinutes,
    bool clearTargetDuration = false,
    String? chapterId,
    bool clearChapter = false,
    String? topicId,
    bool clearTopic = false,
    String? sessionType,
    bool? hasAlarm,
    int? alarmLeadMinutes,
  });

  /// Pauses a routine (`is_active = false`). Logs are kept.
  Future<void> deactivate(String id);

  /// Resumes a paused routine.
  Future<void> activate(String id);

  /// Permanently deletes a routine (logs cascade server-side).
  Future<void> delete(String id);

  /// True when an **active** routine of the caller overlaps the slot on a
  /// shared weekday (excluding [excludeId] while editing).
  Future<bool> hasConflict({
    required String startTime,
    required String endTime,
    required List<int> weekdays,
    String? excludeId,
  });

  /// Logs with `log_date` in `[startDate, endDate]` (inclusive, `YYYY-MM-DD`),
  /// newest first, optionally for one routine.
  Future<List<RoutineLog>> getLogs({
    required String startDate,
    required String endDate,
    String? routineId,
  });

  /// Records the state of one routine on one day (upsert on the UNIQUE
  /// `(routine_id, log_date)`): COMPLETED | SKIPPED | MISSED | PENDING.
  Future<void> upsertLog({
    required String routineId,
    required String logDate,
    required String status,
    int? durationMinutes,
  });

  /// Active routines scheduled on [weekday] paired with their log for [date].
  Future<List<RoutineWithLog>> getToday({
    required String date,
    required int weekday,
  });

  /// Logs newest first, paged; optionally for one routine.
  Future<List<RoutineLog>> getHistory({
    int limit = 30,
    int offset = 0,
    String? routineId,
  });
}

/// A routine paired with its log for a specific day.
class RoutineWithLog {
  const RoutineWithLog({required this.routine, this.log});

  final Routine routine;
  final RoutineLog? log;

  bool get isCompleted => log?.isCompleted ?? false;
  bool get isSkipped => log?.isSkipped ?? false;
  bool get isPending => log == null || log!.isPending;
}

class SupabaseRoutineRepository implements RoutineRepository {
  const SupabaseRoutineRepository();

  SupabaseClient get _client => SupabaseService.client;

  /// Bounded: a user's own routines are a short list; the cap only guards
  /// against runaway data.
  static const _routineLimit = 200;

  @override
  Future<List<Routine>> list() => _guard(() async {
    final data = await _client
        .from('routines')
        .select()
        .order('is_active', ascending: false)
        .order('start_time')
        .limit(_routineLimit);

    return (data as List<dynamic>)
        .map((row) => Routine.fromJson(row as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<Routine?> getById(String id) => _guard(() async {
    final data = await _client
        .from('routines')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (data == null) return null;
    return Routine.fromJson(data);
  });

  @override
  Future<String> create({
    required String title,
    required String startTime,
    required String endTime,
    List<int> weekdays = const [0, 1, 2, 3, 4, 5, 6],
    String? subjectId,
    bool reminderEnabled = true,
    int? targetDurationMinutes,
    String? chapterId,
    String? topicId,
    String sessionType = 'study',
    bool hasAlarm = false,
    int alarmLeadMinutes = 0,
  }) => _guard(() async {
    final data = await _client
        .from('routines')
        .insert({
          'title': title,
          'start_time': startTime,
          'end_time': endTime,
          'weekdays': weekdays,
          'subject_id': subjectId,
          'reminder_enabled': reminderEnabled,
          'target_duration_minutes': targetDurationMinutes,
          'chapter_id': chapterId,
          'topic_id': topicId,
          'session_type': sessionType,
          'has_alarm': hasAlarm,
          'alarm_lead_minutes': alarmLeadMinutes,
        })
        .select('id')
        .single();

    final id = data['id'] as String;
    AppLogger.info('Created routine: $id');
    return id;
  });

  @override
  Future<void> update({
    required String id,
    String? title,
    String? startTime,
    String? endTime,
    List<int>? weekdays,
    String? subjectId,
    bool clearSubject = false,
    bool? reminderEnabled,
    bool? isActive,
    int? targetDurationMinutes,
    bool clearTargetDuration = false,
    String? chapterId,
    bool clearChapter = false,
    String? topicId,
    bool clearTopic = false,
    String? sessionType,
    bool? hasAlarm,
    int? alarmLeadMinutes,
  }) => _guard(() async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (startTime != null) updates['start_time'] = startTime;
    if (endTime != null) updates['end_time'] = endTime;
    if (weekdays != null) updates['weekdays'] = weekdays;
    if (clearSubject) {
      updates['subject_id'] = null;
    } else if (subjectId != null) {
      updates['subject_id'] = subjectId;
    }
    if (reminderEnabled != null) updates['reminder_enabled'] = reminderEnabled;
    if (isActive != null) updates['is_active'] = isActive;
    if (clearTargetDuration) {
      updates['target_duration_minutes'] = null;
    } else if (targetDurationMinutes != null) {
      updates['target_duration_minutes'] = targetDurationMinutes;
    }
    if (clearChapter) {
      updates['chapter_id'] = null;
    } else if (chapterId != null) {
      updates['chapter_id'] = chapterId;
    }
    if (clearTopic) {
      updates['topic_id'] = null;
    } else if (topicId != null) {
      updates['topic_id'] = topicId;
    }
    if (sessionType != null) updates['session_type'] = sessionType;
    if (hasAlarm != null) updates['has_alarm'] = hasAlarm;
    if (alarmLeadMinutes != null) updates['alarm_lead_minutes'] = alarmLeadMinutes;

    if (updates.isEmpty) return;

    await _client.from('routines').update(updates).eq('id', id);
    AppLogger.info('Updated routine: $id');
  });

  @override
  Future<void> deactivate(String id) => _guard(() async {
    await _client.from('routines').update({'is_active': false}).eq('id', id);
    AppLogger.info('Deactivated routine: $id');
  });

  @override
  Future<void> activate(String id) => _guard(() async {
    await _client.from('routines').update({'is_active': true}).eq('id', id);
    AppLogger.info('Activated routine: $id');
  });

  @override
  Future<void> delete(String id) => _guard(() async {
    await _client.from('routines').delete().eq('id', id);
    AppLogger.info('Deleted routine: $id');
  });

  @override
  Future<bool> hasConflict({
    required String startTime,
    required String endTime,
    required List<int> weekdays,
    String? excludeId,
  }) => _guard(() async {
    var query = _client
        .from('routines')
        .select('id, start_time, end_time, weekdays')
        .eq('is_active', true);
    if (excludeId != null) {
      query = query.neq('id', excludeId);
    }
    final rows = await query.limit(_routineLimit) as List<dynamic>;

    for (final row in rows) {
      final existing = row as Map<String, dynamic>;
      final existingWeekdays = [
        for (final w in (existing['weekdays'] as List? ?? const []))
          (w as num).toInt(),
      ];
      if (RoutineSchedule.overlaps(
        aStart: startTime,
        aEnd: endTime,
        aDays: weekdays,
        bStart: existing['start_time'] as String,
        bEnd: existing['end_time'] as String,
        bDays: existingWeekdays,
      )) {
        return true;
      }
    }
    return false;
  });

  @override
  Future<List<RoutineLog>> getLogs({
    required String startDate,
    required String endDate,
    String? routineId,
  }) => _guard(() async {
    var query = _client
        .from('routine_logs')
        .select()
        .gte('log_date', startDate)
        .lte('log_date', endDate);

    if (routineId != null) {
      query = query.eq('routine_id', routineId);
    }

    final data = await query.order('log_date', ascending: false).limit(1000);

    return (data as List<dynamic>)
        .map((row) => RoutineLog.fromJson(row as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<void> upsertLog({
    required String routineId,
    required String logDate,
    required String status,
    int? durationMinutes,
  }) => _guard(() async {
    await _client.from('routine_logs').upsert({
      'routine_id': routineId,
      'log_date': logDate,
      'completed': status == 'COMPLETED',
      'status': status,
      'duration_minutes': durationMinutes,
    }, onConflict: 'routine_id,log_date');

    AppLogger.info('Upserted routine log: $routineId on $logDate -> $status');
  });

  @override
  Future<List<RoutineWithLog>> getToday({
    required String date,
    required int weekday,
  }) => _guard(() async {
    final routinesData = await _client
        .from('routines')
        .select()
        .eq('is_active', true)
        .order('start_time')
        .limit(_routineLimit);

    final routines = (routinesData as List<dynamic>)
        .map((row) => Routine.fromJson(row as Map<String, dynamic>))
        .toList();

    final scheduled = RoutineSchedule.scheduledOn(routines, weekday);
    if (scheduled.isEmpty) return const [];

    final routineIds = scheduled.map((r) => r.id).toList();
    final logsData = await _client
        .from('routine_logs')
        .select()
        .eq('log_date', date)
        .inFilter('routine_id', routineIds);

    final logs = (logsData as List<dynamic>)
        .map((row) => RoutineLog.fromJson(row as Map<String, dynamic>))
        .toList();
    final logByRoutineId = {for (final l in logs) l.routineId: l};

    return scheduled
        .map((r) => RoutineWithLog(routine: r, log: logByRoutineId[r.id]))
        .toList();
  });

  @override
  Future<List<RoutineLog>> getHistory({
    int limit = 30,
    int offset = 0,
    String? routineId,
  }) => _guard(() async {
    var query = _client.from('routine_logs').select();
    if (routineId != null) {
      query = query.eq('routine_id', routineId);
    }
    final data = await query
        .order('log_date', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List<dynamic>)
        .map((row) => RoutineLog.fromJson(row as Map<String, dynamic>))
        .toList();
  });

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('RoutineRepository PostgrestException: ${e.message}');
      throw DataError(message: _mapPostgrestError(e.message));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('RoutineRepository unexpected: $e', stackTrace: st);
      throw const DataError(message: 'Something went wrong. Please try again.');
    }
  }

  static String _mapPostgrestError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') ||
        lower.contains('denied') ||
        lower.contains('row-level')) {
      return 'You do not have permission to perform this action.';
    }
    if (lower.contains('jwt') || lower.contains('not authenticated')) {
      return 'Please sign in again to continue.';
    }
    if (lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('socket')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (lower.contains('unique') || lower.contains('duplicate')) {
      return 'This routine already has an entry for that day.';
    }
    return 'Failed to save routine. Please try again.';
  }
}
