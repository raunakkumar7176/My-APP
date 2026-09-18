import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/answer.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/test_errors.dart';

/// Answers are written ONLY via `rpc_save_answers(uuid, jsonb)` — the server
/// verifies ownership, `in_progress` status and the deadline, validates each
/// `selected_option` against the question's options array and upserts into
/// `public.answers`.
///
/// Reads go through the RLS-protected table (live, 2026-09-16):
/// `GRANT SELECT ON public.answers TO authenticated` + policy "own answers"
/// (`attempts.user_id = auth.uid()` via `attempt_id`). Columns:
/// `attempt_id, question_id, selected_option integer, marked_for_review,
/// updated_at`. A user therefore only ever sees answers of their own
/// attempts, and only after that attempt exists (i.e. was started through
/// the authorized start RPC).
abstract interface class AnswerRepository {
  Future<void> save(String attemptId, List<Answer> answers);

  /// Saved answers of [attemptId] (RLS: own attempts only). Empty when none.
  Future<List<Answer>> forAttempt(String attemptId);
}

class SupabaseAnswerRepository implements AnswerRepository {
  const SupabaseAnswerRepository();

  SupabaseClient get _client => SupabaseService.client;

  /// Exactly the live columns; never `select *` so a schema drift surfaces
  /// as a clear error instead of silently-null fields.
  static const selectColumns =
      'attempt_id, question_id, selected_option, marked_for_review, updated_at';

  @override
  Future<void> save(String attemptId, List<Answer> answers) => _guard(() async {
    if (answers.isEmpty) return;
    final response = await _client.rpc(
      'rpc_save_answers',
      params: {
        'p_attempt': attemptId,
        'p_answers': [for (final a in answers) a.toRpcJson()],
      },
    );
    AppLogger.rpcShape('rpc_save_answers', response);
  }, TestErrorContext.save);

  @override
  Future<List<Answer>> forAttempt(String attemptId) => _guard(() async {
    final rows = await _client
        .from('answers')
        .select(selectColumns)
        .eq('attempt_id', attemptId);
    final list = rows as List;
    if (list.isNotEmpty) AppLogger.rpcShape('answers.select', list);
    return [for (final r in list) Answer.fromRow(r as Map<String, dynamic>)];
  }, TestErrorContext.load);

  static Future<T> _guard<T>(
    Future<T> Function() body,
    TestErrorContext context,
  ) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'AnswerRepository PostgrestException: code=${e.code}, '
        'message=${e.message}',
      );
      throw DataError(message: TestErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('AnswerRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}
