import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/test.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/calendar_clock.dart';
import '../domain/calendar_event.dart';

/// Read-only source for the calendar. Nothing is written; no calendar table
/// exists or is created — events are derived from the authoritative rows:
///   * `public.routines`      — own rows (live policy `own routine`)
///   * `public.routine_logs`  — own via routine (live policy `own routine logs`)
///   * `public.tests`         — whatever the live `tests` SELECT policies allow
///                              (creator, group member, standalone owner)
/// Every query is bounded to the requested month.
abstract interface class CalendarRepository {
  /// The caller's routines (active and inactive — inactive ones still explain
  /// historical logs). Bounded by the user's own rows.
  Future<List<CalendarRoutine>> routines();

  /// Own routine logs with `log_date` in `[from, to]` (date-only, inclusive).
  Future<List<CalendarRoutineLog>> routineLogs({required DateTime from, required DateTime to});

  /// Accessible tests whose `starts_at` lies in `[startUtc, endUtc)`.
  Future<List<Test>> testsBetween({required DateTime startUtc, required DateTime endUtc, int limit = 200});
}

final class SupabaseCalendarRepository implements CalendarRepository {
  const SupabaseCalendarRepository();

  static SupabaseClient get _client => SupabaseService.client;

  static const _routineColumns =
      'id, title, subject_id, start_time, end_time, weekdays, is_active, created_at';
  static const _logColumns = 'routine_id, log_date, status, completed, duration_minutes';

  @override
  Future<List<CalendarRoutine>> routines() => _guard(() async {
    final rows = await _client
        .from('routines')
        .select(_routineColumns)
        .order('start_time')
        .limit(200);
    AppLogger.rpcShape('routines.select(calendar)', rows);
    return [for (final r in rows as List) CalendarRoutine.fromJson(r as Map<String, dynamic>)];
  });

  @override
  Future<List<CalendarRoutineLog>> routineLogs({required DateTime from, required DateTime to}) =>
      _guard(() async {
        final rows = await _client
            .from('routine_logs')
            .select(_logColumns)
            .gte('log_date', CalendarDates.iso(from))
            .lte('log_date', CalendarDates.iso(to))
            .limit(1000);
        return [for (final r in rows as List) CalendarRoutineLog.fromJson(r as Map<String, dynamic>)];
      });

  @override
  Future<List<Test>> testsBetween({required DateTime startUtc, required DateTime endUtc, int limit = 200}) =>
      _guard(() async {
        final rows = await _client
            .from('tests')
            .select()
            .eq('is_soft_deleted', false)
            .gte('starts_at', startUtc.toUtc().toIso8601String())
            .lt('starts_at', endUtc.toUtc().toIso8601String())
            .order('starts_at')
            .limit(limit);
        AppLogger.rpcShape('tests.select(calendar)', rows);
        return [for (final r in rows as List) Test.fromJson(r as Map<String, dynamic>)];
      });

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('CalendarRepository PostgrestException: ${e.code} ${e.message}');
      throw DataError(message: _friendly(e.message));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('CalendarRepository unexpected: $e', stackTrace: st);
      throw DataError(message: _friendly(e.toString()));
    }
  }

  static String _friendly(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('jwt') || l.contains('not authenticated')) return 'Please sign in again to continue.';
    if (l.contains('socketexception') || l.contains('failed host lookup') || l.contains('clientexception') || l.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Could not load your calendar. Please try again.';
  }
}
