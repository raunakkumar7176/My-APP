import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/answer.dart';
import 'supabase_service.dart';

final class AnswerService {
  AnswerService._();

  static Future<void> saveAnswers({
    required String attemptId,
    required List<Answer> answers,
  }) async {
    try {
      final payload = answers.map((a) => a.toJson()).toList();
      final response = await SupabaseService.client
          .rpc('rpc_save_answers', params: {
        'p_attempt': attemptId,
        'p_answers': payload,
      });
      AppLogger.rpcShape('rpc_save_answers', response);

      AppLogger.info('Saved ${answers.length} answers for attempt $attemptId');
    } on PostgrestException catch (e) {
      AppLogger.error('saveAnswers PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('saveAnswers unexpected error: $e');
      throw const DataError(message: 'Failed to save answers. Please try again.');
    }
  }

  static Future<void> saveSingleAnswer({
    required String attemptId,
    required Answer answer,
  }) async {
    await saveAnswers(attemptId: attemptId, answers: [answer]);
  }

  static Future<List<Answer>> getAnswersForAttempt(String attemptId) async {
    try {
      final response = await SupabaseService.client
          .from('answers')
          .select()
          .eq('attempt_id', attemptId)
          .order('question_id');

      return (response as List<dynamic>)
          .map((json) => Answer.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getAnswersForAttempt PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getAnswersForAttempt unexpected error: $e');
      throw const DataError(message: 'Failed to load answers. Please try again.');
    }
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to save answers.';
    }
    if (lower.contains('not found') || lower.contains('invalid')) {
      return 'Attempt not found or no longer active.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Answers may not have been saved.';
    }
    return 'Failed to save answers. Please try again.';
  }
}
