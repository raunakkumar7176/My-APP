import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/result.dart';
import '../../../core/models/result_batch.dart';
import '../../../core/services/supabase_service.dart';
import '../../group/domain/group_test_results.dart';
import '../domain/test_errors.dart';

/// Results are produced only by the server (`rpc_submit_attempt` /
/// `rpc_generate_results`); the client reads rows under RLS. No analytics
/// are fabricated here — only what the row contains is returned.
abstract interface class ResultRepository {
  Future<Result?> byAttempt(String attemptId);

  /// The current user's results for a test, newest first (attempt history).
  Future<List<Result>> mineForTest(String testId);

  /// Requests batch result generation via `rpc_generate_results`. The server
  /// authorizes (test owner, or group user with GENERATE_RESULTS) and returns
  /// the batch state directly — that JSON is the authoritative result. The
  /// client never reads `public.result_batches` for this (its SELECT policy
  /// is group-permission based and would hide a standalone owner's batch).
  Future<ResultBatch> generateResults(String testId);

  /// Publishes an already-generated batch via `rpc_publish_results` — the
  /// one authorized action that makes a group test's results visible to
  /// students, distinct from `generateResults`. Idempotent: a second call
  /// (or a concurrent one) returns the same published state, never a
  /// duplicate. The server rejects this when no completed batch exists
  /// (`RESULTS_NOT_GENERATED`) — call `generateResults` first.
  Future<ResultBatch> publishResults(String testId);

  // ── Group test results (G11) ──

  /// All scored results for a test, visible under RLS. Leaders with
  /// `VIEW_GROUP_ANALYTICS` see all participants; members see only their
  /// own (per the `own results` + `analytics holders see group results`
  /// policies).
  Future<List<Result>> resultsForTest(String testId);

  /// `rpc_get_leaderboard(p_test)` — the SECURITY DEFINER server ranking
  /// (remediated 2026-09-20: rows only for the test creator, members of the
  /// test's group, or participants; anon revoked). Returns the raw rows
  /// `rank, user_id, full_name, avatar_url, student_code, score, max_score,
  /// percentage, accuracy, submitted_at` in server rank order. Read-only.
  Future<List<Map<String, dynamic>>> leaderboard(String testId);

  /// The current user's AI coach report for a test (if one exists).
  /// Reads from `ai_reports` under RLS (own reports policy).
  Future<AiCoachReport?> myAiReport(String testId);

  /// All AI reports for a test (leaders with GENERATE_RESULTS permission
  /// see all; members see only their own — per `report trigger reads` +
  /// `own reports` policies).
  Future<List<AiCoachReport>> allAiReports(String testId);

  /// The test's `result_batches` row (UNIQUE per test) — a plain read under
  /// the live "trigger sees batches" policy (GENERATE_RESULTS holders; the
  /// owner via the function bypass). Null when none exists or not visible.
  /// Opening a screen must never call `generateResults` to learn the status.
  Future<ResultBatch?> batchForTest(String testId);

  /// Queues AI coach-report generation for a test through the proposed
  /// `rpc_request_coach_reports(p_test_id)` (migrations/G11_*): server checks
  /// auth, creator-or-GENERATE_RESULTS, a finished deterministic batch, and
  /// inserts one `ai_jobs` row (type `coach_reports`) idempotently. No AI
  /// runs in the request path; a worker processes the queue later.
  Future<CoachReportJob> requestCoachReports(String testId);
}

class SupabaseResultRepository implements ResultRepository {
  const SupabaseResultRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<Result?> byAttempt(String attemptId) => _guard(() async {
    final row = await _client
        .from('results')
        .select()
        .eq('attempt_id', attemptId)
        .maybeSingle();
    // Live `results` columns are not yet frozen; log the key set (no
    // answer keys are ever in this row) so a parse failure is diagnosable.
    if (row != null) {
      AppLogger.rpcShape('results.select', row);
      final missing = [
        for (final k in const ['attempt_id', 'test_id', 'user_id'])
          if (row[k] == null) k,
      ];
      if (missing.isNotEmpty) {
        AppLogger.warning('results row null required columns: $missing');
      }
    }
    return row == null ? null : Result.fromJson(row);
  }, TestErrorContext.load);

  @override
  Future<List<Result>> mineForTest(String testId) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthError(message: 'You must be logged in.');
    }
    final rows = await _client
        .from('results')
        .select()
        .eq('test_id', testId)
        .eq('user_id', uid)
        .order('computed_at', ascending: false);
    return [
      for (final r in rows as List) Result.fromJson(r as Map<String, dynamic>),
    ];
  }, TestErrorContext.load);

  @override
  Future<ResultBatch> generateResults(String testId) => _guard(() async {
    final response = await _client.rpc(
      'rpc_generate_results',
      params: {'p_test_id': testId},
    );
    AppLogger.rpcShape('rpc_generate_results', response);
    return batchFromRpcResponse(response);
  }, TestErrorContext.generic);

  @override
  Future<ResultBatch> publishResults(String testId) => _guard(() async {
    final response = await _client.rpc(
      'rpc_publish_results',
      params: {'p_test_id': testId},
    );
    AppLogger.rpcShape('rpc_publish_results', response);
    return publishFromRpcResponse(response);
  }, TestErrorContext.generic);

  // ── Group test results (G11) ──

  @override
  Future<List<Result>> resultsForTest(String testId) => _guard(() async {
    final rows = await _client
        .from('results')
        .select()
        .eq('test_id', testId)
        .order('score', ascending: false);
    AppLogger.rpcShape('results.select(group)', rows);
    return [
      for (final r in rows as List) Result.fromJson(r as Map<String, dynamic>),
    ];
  }, TestErrorContext.load);

  @override
  Future<List<Map<String, dynamic>>> leaderboard(String testId) =>
      _guard(() async {
        final rows = await _client.rpc(
          'rpc_get_leaderboard',
          params: {'p_test': testId},
        );
        AppLogger.rpcShape('rpc_get_leaderboard', rows);
        return [
          for (final r in rows as List) Map<String, dynamic>.from(r as Map),
        ];
      }, TestErrorContext.load);

  @override
  Future<AiCoachReport?> myAiReport(String testId) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('ai_reports')
        .select()
        .eq('test_id', testId)
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return null;
    AppLogger.rpcShape('ai_reports.select', row);
    return AiCoachReport.fromJson(row);
  }, TestErrorContext.load);

  @override
  Future<List<AiCoachReport>> allAiReports(String testId) => _guard(() async {
    final rows = await _client
        .from('ai_reports')
        .select()
        .eq('test_id', testId)
        .order('created_at', ascending: false);
    return [
      for (final r in rows as List)
        AiCoachReport.fromJson(r as Map<String, dynamic>),
    ];
  }, TestErrorContext.load);

  @override
  Future<ResultBatch?> batchForTest(String testId) => _guard(() async {
    // Live: UNIQUE(test_id); SELECT policy "trigger sees batches"
    // (GENERATE_RESULTS) — anyone else simply gets no row. A read, never
    // the generating RPC, so opening a screen creates nothing.
    final row = await _client
        .from('result_batches')
        .select()
        .eq('test_id', testId)
        .maybeSingle();
    if (row == null) return null;
    AppLogger.rpcShape('result_batches.select', row);
    return ResultBatch.fromJson(row);
  }, TestErrorContext.load);

  @override
  Future<CoachReportJob> requestCoachReports(String testId) =>
      _guard(() async {
        final response = await _client.rpc(
          'rpc_request_coach_reports',
          params: {'p_test_id': testId},
        );
        AppLogger.rpcShape('rpc_request_coach_reports', response);
        final data = response is List && response.isNotEmpty
            ? response.first
            : response;
        if (data is Map && (data['job_id'] ?? data['id']) != null) {
          return CoachReportJob.fromJson(Map<String, dynamic>.from(data));
        }
        throw const DataError(
          message: 'Coach report request returned an unexpected response.',
        );
      }, TestErrorContext.generic);

  /// Parses the RPC jsonb (`{batch_id, test_id, status, reports_done,
  /// reports_total, errors, reused}`; a one-element list is tolerated).
  /// Anything without `batch_id` is an unexpected response — reported, never
  /// papered over with a table read.
  static ResultBatch batchFromRpcResponse(dynamic response) {
    final data = response is List && response.isNotEmpty
        ? response.first
        : response;
    if (data is Map && data['batch_id'] is String) {
      return ResultBatch.fromRpcJson(Map<String, dynamic>.from(data));
    }
    throw const DataError(
      message: 'Result generation returned an unexpected response.',
    );
  }

  /// Parses the `rpc_publish_results` jsonb (`{batch_id, test_id, status:
  /// 'published', published_at, notified, reused}`).
  static ResultBatch publishFromRpcResponse(dynamic response) {
    final data = response is List && response.isNotEmpty
        ? response.first
        : response;
    if (data is Map && data['batch_id'] is String) {
      return ResultBatch.fromPublishRpcJson(Map<String, dynamic>.from(data));
    }
    throw const DataError(
      message: 'Result publication returned an unexpected response.',
    );
  }

  static Future<T> _guard<T>(
    Future<T> Function() body,
    TestErrorContext context,
  ) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('ResultRepository PostgrestException: ${e.message}');
      throw DataError(message: TestErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('ResultRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}
