import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/performance_summary.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';

/// Server-authoritative performance analytics via migration 0072's RPCs.
/// Every RPC is self-only (the server rejects any other `p_user_id`) — this
/// repository always passes the caller's own id, never anyone else's.
abstract interface class PerformanceRepository {
  Future<PerformanceSummary> fetchSummary(TimeFilter filter);
  Future<List<SubjectWiseBreakdown>> fetchSubjectBreakdown(TimeFilter filter);

  /// The caller's own scored results behind one Subject Mastery row, via
  /// `rpc_get_subject_results` (migration 0082) — newest first.
  Future<List<SubjectResultEntry>> fetchSubjectResults(
    String groupKey,
    TimeFilter filter,
  );
  Future<List<DailyActivity>> fetchDailyActivity({int days = 7});

  /// Generates/refreshes the caller's own report for the current week.
  Future<WeeklyPerformanceReport> generateWeeklyReport();

  /// The caller's own most recent stored weekly report, or null if none
  /// has ever been generated.
  Future<WeeklyPerformanceReport?> fetchLatestWeeklyReport();
}

class SupabasePerformanceRepository implements PerformanceRepository {
  const SupabasePerformanceRepository();

  SupabaseClient get _client => SupabaseService.client;

  String get _userId {
    final uid = AuthService.currentUser?.id;
    if (uid == null) throw const AuthError(message: 'You must be signed in.');
    return uid;
  }

  @override
  Future<PerformanceSummary> fetchSummary(TimeFilter filter) => _guard(() async {
        final res = await _client.rpc(
          'rpc_get_performance_summary',
          params: {'p_user_id': _userId, 'p_filter': filter.rpcValue},
        );
        return PerformanceSummary.fromJson(Map<String, dynamic>.from(res as Map));
      });

  @override
  Future<List<SubjectWiseBreakdown>> fetchSubjectBreakdown(TimeFilter filter) => _guard(() async {
        final res = await _client.rpc(
          'rpc_get_subject_wise_breakdown',
          params: {'p_user_id': _userId, 'p_filter': filter.rpcValue},
        );
        return (res as List)
            .map((r) => SubjectWiseBreakdown.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList();
      });

  @override
  Future<List<DailyActivity>> fetchDailyActivity({int days = 7}) => _guard(() async {
        final res = await _client.rpc(
          'rpc_get_daily_activity',
          params: {'p_user_id': _userId, 'p_days': days},
        );
        return (res as List)
            .map((r) => DailyActivity.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList();
      });

  @override
  Future<List<SubjectResultEntry>> fetchSubjectResults(
    String groupKey,
    TimeFilter filter,
  ) => _guard(() async {
        final res = await _client.rpc(
          'rpc_get_subject_results',
          params: {'p_group_key': groupKey, 'p_filter': filter.rpcValue},
        );
        return (res as List)
            .map((r) => SubjectResultEntry.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList();
      });

  @override
  Future<WeeklyPerformanceReport> generateWeeklyReport() => _guard(() async {
        final res = await _client.rpc('rpc_generate_my_weekly_report');
        return WeeklyPerformanceReport.fromJson(Map<String, dynamic>.from(res as Map));
      });

  @override
  Future<WeeklyPerformanceReport?> fetchLatestWeeklyReport() => _guard(() async {
        final row = await _client
            .from('weekly_performance_reports')
            .select()
            .eq('user_id', _userId)
            .order('week_start_date', ascending: false)
            .limit(1)
            .maybeSingle();
        return row == null ? null : WeeklyPerformanceReport.fromJson(row);
      });

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('PerformanceRepository PostgrestException: ${e.message}');
      throw const DataError(message: 'Could not load your performance data. Please try again.');
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('PerformanceRepository unexpected: $e', stackTrace: st);
      throw const DataError(message: 'Could not load your performance data. Please try again.');
    }
  }
}
