import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/question.dart';
import 'supabase_service.dart';

final class QuestionService {
  QuestionService._();

  static SupabaseQueryBuilder get _db =>
      SupabaseService.client.from('questions');

  // ─── READ ────────────────────────────────────────────────

  static Future<List<Question>> getQuestionsSafe({
    required String testId,
    String? accessCode,
  }) async {
    try {
      final params = <String, dynamic>{'p_test_id': testId};
      if (accessCode != null) {
        params['p_access_code'] = accessCode;
      }
      final response = await SupabaseService.client
          .rpc('get_test_questions_safe', params: params);

      if (response == null) return [];

      final list = response is List ? response : [response];
      // Contract diagnostics (keys only). The answer key must never reach the
      // client; if the RPC ever returns it, say so loudly.
      AppLogger.rpcShape('get_test_questions_safe', response);
      if (list.isNotEmpty &&
          list.first is Map &&
          (list.first as Map).containsKey('correct_option')) {
        AppLogger.error(
            'SECURITY: get_test_questions_safe returned a correct_option key');
      }
      return list
          .map((json) => Question.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getQuestionsSafe PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getQuestionsSafe unexpected error: $e');
      throw const DataError(
          message: 'Failed to load questions. Please try again.');
    }
  }

  static Future<Question?> getQuestionById(String questionId) async {
    try {
      final response = await _db.select().eq('id', questionId).maybeSingle();

      if (response == null) return null;
      return Question.fromJson(response);
    } on PostgrestException catch (e) {
      AppLogger.error('getQuestionById PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getQuestionById unexpected error: $e');
      throw const DataError(
          message: 'Failed to load question. Please try again.');
    }
  }

  // ─── CREATE ──────────────────────────────────────────────

  @visibleForTesting
  static String questionTypeToRpc(QuestionType? type) {
    switch (type) {
      case QuestionType.mcqSingle:
      case QuestionType.mcqMultiple:
        return 'mcq';
      case QuestionType.trueFalse:
        return 'tf';
      case QuestionType.integer:
        return 'num';
      case QuestionType.shortAnswer:
        return 'short';
      default:
        return 'mcq';
    }
  }

  @visibleForTesting
  static Map<String, dynamic> buildCreateQuestionParams({
    required String testId,
    required String questionText,
    QuestionType? questionType,
    String? questionTextTranslated,
    List<Map<String, dynamic>>? options,
    int? correctOption,
    String? explanation,
    String? subjectId,
    String? topicNodeId,
    String? difficulty,
    int? marks,
    double? negativeMarks,
    String? questionStatus,
    String? questionImage,
    String? questionImageDark,
    Map<String, dynamic>? metadata,
    String? language,
    String? sourceBatch,
    String? bankId,
  }) {
    final params = <String, dynamic>{
      'p_test_id': testId,
      'p_question': questionText,
    };
    if (questionType != null) {
      params['p_question_type'] = questionTypeToRpc(questionType);
    }
    if (questionTextTranslated != null) {
      params['p_question_text_translated'] = questionTextTranslated;
    }
    if (options != null) params['p_options'] = options;
    if (correctOption != null) params['p_correct_option'] = correctOption;
    if (explanation != null) params['p_explanation'] = explanation;
    if (subjectId != null) params['p_subject_id'] = subjectId;
    if (topicNodeId != null) params['p_topic_node_id'] = topicNodeId;
    if (difficulty != null) params['p_difficulty'] = difficulty;
    if (marks != null) params['p_marks'] = marks;
    if (negativeMarks != null) params['p_negative_marks'] = negativeMarks;
    if (questionStatus != null) params['p_status'] = questionStatus;
    if (questionImage != null) params['p_question_image'] = questionImage;
    if (questionImageDark != null) {
      params['p_question_image_dark'] = questionImageDark;
    }
    if (metadata != null) params['p_metadata'] = metadata;
    if (language != null) params['p_language'] = language;
    if (sourceBatch != null) params['p_source_batch'] = sourceBatch;
    if (bankId != null) params['p_bank_id'] = bankId;
    return params;
  }

  static Future<String> createQuestion({
    required String testId,
    required String questionText,
    QuestionType? questionType,
    String? questionTextTranslated,
    List<Map<String, dynamic>>? options,
    int? correctOption,
    String? explanation,
    String? subjectId,
    String? topicNodeId,
    String? difficulty,
    int? marks,
    double? negativeMarks,
    String? questionStatus,
    String? questionImage,
    String? questionImageDark,
    Map<String, dynamic>? metadata,
    String? language,
    String? sourceBatch,
    String? bankId,
  }) async {
    try {
      final params = buildCreateQuestionParams(
        testId: testId,
        questionText: questionText,
        questionType: questionType,
        questionTextTranslated: questionTextTranslated,
        options: options,
        correctOption: correctOption,
        explanation: explanation,
        subjectId: subjectId,
        topicNodeId: topicNodeId,
        difficulty: difficulty,
        marks: marks,
        negativeMarks: negativeMarks,
        questionStatus: questionStatus,
        questionImage: questionImage,
        questionImageDark: questionImageDark,
        metadata: metadata,
        language: language,
        sourceBatch: sourceBatch,
        bankId: bankId,
      );

      AppLogger.info('createQuestion: calling rpc_create_question');
      final response = await SupabaseService.client
          .rpc('rpc_create_question', params: params);

      final data = response as Map<String, dynamic>;
      final questionId = data['question_id'] as String;
      AppLogger.info('createQuestion: created question $questionId');

      return questionId;
    } on PostgrestException catch (e) {
      AppLogger.error('createQuestion PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('createQuestion unexpected error: $e');
      throw const DataError(
          message: 'Failed to create question. Please try again.');
    }
  }

  // ─── UPDATE ──────────────────────────────────────────────

  @visibleForTesting
  static Map<String, dynamic> buildUpdateQuestionParams({
    required String questionId,
    String? questionText,
    QuestionType? questionType,
    String? questionTextTranslated,
    List<Map<String, dynamic>>? options,
    int? correctOption,
    String? explanation,
    String? subjectId,
    String? topicNodeId,
    String? difficulty,
    int? marks,
    double? negativeMarks,
    String? questionStatus,
    String? questionImage,
    String? questionImageDark,
    Map<String, dynamic>? metadata,
    String? language,
  }) {
    final params = <String, dynamic>{
      'p_question_id': questionId,
    };
    if (questionText != null) params['p_question'] = questionText;
    if (questionType != null) {
      params['p_question_type'] = questionTypeToRpc(questionType);
    }
    if (questionTextTranslated != null) {
      params['p_question_text_translated'] = questionTextTranslated;
    }
    if (options != null) params['p_options'] = options;
    if (correctOption != null) params['p_correct_option'] = correctOption;
    if (explanation != null) params['p_explanation'] = explanation;
    if (subjectId != null) params['p_subject_id'] = subjectId;
    if (topicNodeId != null) params['p_topic_node_id'] = topicNodeId;
    if (difficulty != null) params['p_difficulty'] = difficulty;
    if (marks != null) params['p_marks'] = marks;
    if (negativeMarks != null) params['p_negative_marks'] = negativeMarks;
    if (questionStatus != null) params['p_status'] = questionStatus;
    if (questionImage != null) params['p_question_image'] = questionImage;
    if (questionImageDark != null) {
      params['p_question_image_dark'] = questionImageDark;
    }
    if (metadata != null) params['p_metadata'] = metadata;
    if (language != null) params['p_language'] = language;
    return params;
  }

  static Future<void> updateQuestion({
    required String questionId,
    String? questionText,
    QuestionType? questionType,
    String? questionTextTranslated,
    List<Map<String, dynamic>>? options,
    int? correctOption,
    String? explanation,
    String? subjectId,
    String? topicNodeId,
    String? difficulty,
    int? marks,
    double? negativeMarks,
    String? questionStatus,
    String? questionImage,
    String? questionImageDark,
    Map<String, dynamic>? metadata,
    String? language,
  }) async {
    try {
      final params = buildUpdateQuestionParams(
        questionId: questionId,
        questionText: questionText,
        questionType: questionType,
        questionTextTranslated: questionTextTranslated,
        options: options,
        correctOption: correctOption,
        explanation: explanation,
        subjectId: subjectId,
        topicNodeId: topicNodeId,
        difficulty: difficulty,
        marks: marks,
        negativeMarks: negativeMarks,
        questionStatus: questionStatus,
        questionImage: questionImage,
        questionImageDark: questionImageDark,
        metadata: metadata,
        language: language,
      );

      AppLogger.info(
          'updateQuestion: calling rpc_update_question for $questionId');
      await SupabaseService.client
          .rpc('rpc_update_question', params: params);
    } on PostgrestException catch (e) {
      AppLogger.error('updateQuestion PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('updateQuestion unexpected error: $e');
      throw const DataError(
          message: 'Failed to update question. Please try again.');
    }
  }

  // ─── APPROVE ────────────────────────────────────────────

  static Future<void> approveQuestion(String questionId) async {
    await updateQuestion(
      questionId: questionId,
      questionStatus: 'approved',
    );
  }

  // ─── DELETE ──────────────────────────────────────────────

  @visibleForTesting
  static Map<String, dynamic> buildDeleteQuestionParams(String questionId) {
    return {'p_question_id': questionId};
  }

  static Future<void> deleteQuestion(String questionId) async {
    try {
      AppLogger.info(
          'deleteQuestion: calling rpc_delete_question for $questionId');
      await SupabaseService.client.rpc('rpc_delete_question',
          params: buildDeleteQuestionParams(questionId));
      AppLogger.info('deleteQuestion: deleted question $questionId');
    } on PostgrestException catch (e) {
      AppLogger.error('deleteQuestion PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('deleteQuestion unexpected error: $e');
      throw const DataError(
          message: 'Failed to delete question. Please try again.');
    }
  }

  // ─── HELPERS ─────────────────────────────────────────────

  @visibleForTesting
  static String mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have access to these questions.';
    }
    if (lower.contains('row-level security') || lower.contains('rls')) {
      return 'You do not have permission to access these questions.';
    }
    if (lower.contains('not found')) {
      return 'Questions not found for this test.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to load questions. Please try again.';
  }

  static String _mapErrorMessage(String message) => mapErrorMessage(message);
}
