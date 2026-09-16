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
/// R4.1 STATUS: the live `answers` column names are UNVERIFIED (owner list:
/// `selected_option`, `marked_for_review`; repo DDL: `selected_option_id`,
/// `is_marked_for_review`, `is_answered`, `text_answer`). Until the R4.1
/// script settles it, this repository keeps the exact write payload the app
/// has always sent (so server behaviour is unchanged) and normalizes READS in
/// one place, [answerFromRow], accepting either naming. Once verified, delete
/// the losing branch here — nowhere else needs to change.
abstract interface class AnswerRepository {
  Future<void> save(String attemptId, List<Answer> answers);

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
        final rows = await _client
            .from('answers')
            .select()
            .eq('attempt_id', attemptId)
            .order('question_id');
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
    } catch (e, st) {
      AppLogger.error('AnswerRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}
