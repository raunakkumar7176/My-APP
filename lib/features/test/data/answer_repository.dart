import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/answer.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/test_errors.dart';

/// Answers are written ONLY via `rpc_save_answers` (the server validates the
/// attempt, ownership and deadline) and read back for resume via the
/// RLS-protected `answers` table.
///
/// R4.1 STATUS (live, 2026-09-16): `SELECT` on `public.answers` is DENIED to
/// the authenticated role (42501). There is therefore NO client read path for
/// saved answers today — [forAttempt] reports that as [AnswerReadUnavailable]
/// (not a transient error) so callers can tell the user honestly. Column
/// naming stays unverified; [answerFromRow] keeps accepting both candidate
/// namings until a read path exists and the R4.1 script settles it. The write
/// payload is unchanged from the historical client.
/// Thrown when the backend does not permit reading answers back at all
/// (missing GRANT/policy). Distinct from transient failures so the UI can
/// explain "answers are saved but cannot be shown on resume" instead of
/// retrying.
final class AnswerReadUnavailable implements Exception {
  const AnswerReadUnavailable();

  String get message => 'Saved answers cannot be loaded on this backend.';

  @override
  String toString() => 'AnswerReadUnavailable: $message';
}

abstract interface class AnswerRepository {
  Future<void> save(String attemptId, List<Answer> answers);

  /// Throws [AnswerReadUnavailable] when the server forbids the read.
  Future<List<Answer>> forAttempt(String attemptId);
}

class SupabaseAnswerRepository implements AnswerRepository {
  const SupabaseAnswerRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<void> save(String attemptId, List<Answer> answers) =>
      _guard(() async {
        if (answers.isEmpty) return;
        final response = await _client.rpc('rpc_save_answers', params: {
          'p_attempt': attemptId,
          'p_answers': [for (final a in answers) a.toJson()],
        });
        AppLogger.rpcShape('rpc_save_answers', response);
      }, TestErrorContext.save);

  @override
  Future<List<Answer>> forAttempt(String attemptId) => _guard(() async {
        final dynamic rows;
        try {
          rows = await _client
              .from('answers')
              .select()
              .eq('attempt_id', attemptId)
              .order('question_id');
        } on PostgrestException catch (e) {
          // 42501 = no table privilege for this role (verified live 2026-09-16).
          if (e.code == '42501') throw const AnswerReadUnavailable();
          rethrow;
        }
        final list = rows as List;
        if (list.isNotEmpty) AppLogger.rpcShape('answers.select', list);
        return [
          for (final r in list) answerFromRow(r as Map<String, dynamic>),
        ];
      }, TestErrorContext.load);

  /// Single normalization point for an `answers` row (see class doc).
  static Answer answerFromRow(Map<String, dynamic> row) {
    final selected = (row['selected_option_id'] ?? row['selected_option']) as String?;
    final text = row['text_answer'] as String?;
    final marked = (row['is_marked_for_review'] ?? row['marked_for_review']) as bool?;
    final answered = row['is_answered'] as bool?;
    return Answer(
      attemptId: row['attempt_id'] as String,
      questionId: row['question_id'] as String,
      selectedOptionId: selected,
      textAnswer: text,
      isMarkedForReview: marked ?? false,
      // Without an explicit flag, "answered" means a value exists.
      isAnswered: answered ?? (selected != null || text != null),
    );
  }

  static Future<T> _guard<T>(
      Future<T> Function() body, TestErrorContext context) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('AnswerRepository PostgrestException: ${e.message}');
      throw DataError(message: TestErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } on AnswerReadUnavailable {
      rethrow;
    } catch (e, st) {
      AppLogger.error('AnswerRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}
