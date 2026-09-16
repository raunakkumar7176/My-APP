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

  Future<ResultBatch?> latestBatch(String testId);

  /// Owner-only on the server. Returns the batch when the RPC provides one.
  Future<ResultBatch?> generateResults(String testId);
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
  Future<ResultBatch?> latestBatch(String testId) => _guard(() async {
        final row = await _client
            .from('result_batches')
            .select()
            .eq('test_id', testId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        return row == null ? null : ResultBatch.fromJson(row);
      }, TestErrorContext.load);

  @override
  Future<ResultBatch?> generateResults(String testId) => _guard(() async {
        final response = await _client
            .rpc('rpc_generate_results', params: {'p_test_id': testId});
        AppLogger.rpcShape('rpc_generate_results', response);
        final data =
            response is List && response.isNotEmpty ? response.first : response;
        if (data is Map<String, dynamic> && data['id'] != null) {
          return ResultBatch.fromJson(data);
        }
        // RPC acknowledged without a row: read the latest batch once.
        return latestBatch(testId);
      }, TestErrorContext.generic);

  static Future<T> _guard<T>(
      Future<T> Function() body, TestErrorContext context) async {
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
