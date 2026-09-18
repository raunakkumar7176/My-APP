import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/result.dart';
import '../../../core/models/result_batch.dart';
import '../../../core/services/supabase_service.dart';
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
