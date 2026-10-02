import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/question_wallet_models.dart';
import '../domain/test_errors.dart';

/// "Question Wallet" — reusing questions from the caller's own past tests,
/// via the 4 RPCs in 0094_question_wallet_reuse.sql. Every question shown
/// here is one the caller already wrote/owns; the server re-verifies
/// ownership on create regardless of what the client sends.
abstract interface class QuestionWalletRepository {
  Future<List<PastTestSummary>> myPastTests();
  Future<List<ReusableQuestion>> questionsForReuse(String testId);
  Future<List<ReusableQuestion>> myIncorrectQuestions({int limit = 50});
  Future<String> createTestFromReusedQuestions({
    required String title,
    required int durationSec,
    required List<String> questionIds,
    String? groupId,
    String testMode = 'self',
  });

  /// Mistakes grouped by source test (0099), within [retentionDays] or
  /// starred — the accordion-card Mistake Vault.
  Future<List<MistakeTestGroup>> mistakeTestsSummary({int retentionDays = 30});

  Future<void> toggleMistakeStar({
    required String attemptId,
    required String questionId,
    required bool starred,
  });

  /// Self-practice from the caller's own wrong answers, regardless of who
  /// created the source test (0099's rpc_create_selftest_from_mistakes) —
  /// always a 'self' mode test, never group/challenge.
  Future<String> createSelfTestFromMistakes({
    required String title,
    required int durationSec,
    required List<String> questionIds,
  });
}

class SupabaseQuestionWalletRepository implements QuestionWalletRepository {
  const SupabaseQuestionWalletRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<List<PastTestSummary>> myPastTests() => _guard(() async {
    final response = await _client.rpc('rpc_get_my_past_tests');
    AppLogger.rpcShape('rpc_get_my_past_tests', response);
    if (response is! List) return const [];
    return response
        .map((e) => PastTestSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  });

  @override
  Future<List<ReusableQuestion>> questionsForReuse(String testId) => _guard(() async {
    final response = await _client.rpc(
      'rpc_get_test_questions_for_reuse',
      params: {'p_test_id': testId},
    );
    if (response is! List) return const [];
    return response
        .map((e) => ReusableQuestion.fromPickerJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  });

  @override
  Future<List<ReusableQuestion>> myIncorrectQuestions({int limit = 50}) => _guard(() async {
    final response = await _client.rpc(
      'rpc_get_my_incorrect_questions',
      params: {'p_limit': limit},
    );
    if (response is! List) return const [];
    return response
        .map((e) => ReusableQuestion.fromMistakeJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  });

  @override
  Future<String> createTestFromReusedQuestions({
    required String title,
    required int durationSec,
    required List<String> questionIds,
    String? groupId,
    String testMode = 'self',
  }) => _guard(() async {
    final response = await _client.rpc(
      'rpc_create_test_from_reused_questions',
      params: {
        'p_title': title,
        'p_duration_sec': durationSec,
        'p_question_ids': questionIds,
        'p_group_id': groupId,
        'p_test_mode': testMode,
      },
    );
    AppLogger.rpcShape('rpc_create_test_from_reused_questions', response);
    if (response is! String) {
      throw const DataError(message: 'Could not create the test from reused questions.');
    }
    return response;
  });

  @override
  Future<List<MistakeTestGroup>> mistakeTestsSummary({int retentionDays = 30}) =>
      _guard(() async {
        final response = await _client.rpc(
          'rpc_get_mistake_tests_summary',
          params: {'p_retention_days': retentionDays},
        );
        AppLogger.rpcShape('rpc_get_mistake_tests_summary', response);
        if (response is! List) return const [];
        return response
            .map((e) => MistakeTestGroup.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      });

  @override
  Future<void> toggleMistakeStar({
    required String attemptId,
    required String questionId,
    required bool starred,
  }) => _guard(() async {
    await _client.rpc(
      'rpc_toggle_mistake_star',
      params: {
        'p_attempt_id': attemptId,
        'p_question_id': questionId,
        'p_starred': starred,
      },
    );
  });

  @override
  Future<String> createSelfTestFromMistakes({
    required String title,
    required int durationSec,
    required List<String> questionIds,
  }) => _guard(() async {
    final response = await _client.rpc(
      'rpc_create_selftest_from_mistakes',
      params: {
        'p_title': title,
        'p_duration_sec': durationSec,
        'p_question_ids': questionIds,
      },
    );
    AppLogger.rpcShape('rpc_create_selftest_from_mistakes', response);
    if (response is! String) {
      throw const DataError(message: 'Could not create the self-practice test.');
    }
    return response;
  });

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('QuestionWalletRepository PostgrestException: ${e.message}');
      throw DataError(message: TestErrors.map(e.message, context: TestErrorContext.load));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('QuestionWalletRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: TestErrorContext.load));
    }
  }
}
