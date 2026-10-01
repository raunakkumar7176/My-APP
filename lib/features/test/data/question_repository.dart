import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/question.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/test_errors.dart';
import '../models/question_draft.dart';

/// Question type as the RPCs expect it.
String questionTypeToRpc(QuestionType? type) {
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
    case QuestionType.unknown:
    case null:
      return 'mcq';
  }
}

/// The only place question rows are read from or written to Supabase.
///
/// SECURITY: reads go exclusively through `get_test_questions_safe`, which is
/// the server-side answer-key filter. This repository never selects
/// `public.questions`, and it logs a `SECURITY:` error if the RPC ever
/// returns a `correct_option` key. `correct_option` is sent *to* the server
/// only inside create/update params.
abstract interface class QuestionRepository {
  Future<List<Question>> safeQuestions(String testId, {String? accessCode});

  /// Questions for the caller's own already-submitted [attemptId] — no
  /// access/join code required, since owning a submitted attempt already
  /// proves legitimate access. This is what the Review screen and the
  /// detailed PDF report must use instead of [safeQuestions] for a
  /// code-protected test (e.g. Challenge with Friends): by the time the
  /// result is being viewed, the code used to join is no longer threaded
  /// through, so `safeQuestions(testId)` with no code returns nothing.
  Future<List<Question>> reviewQuestionsForAttempt(String attemptId);

  /// Returns the new question id.
  Future<String> create(String testId, QuestionDraft draft);

  /// Only non-null fields are sent; `correctOption` null means "unchanged".
  Future<void> update(String questionId, QuestionDraft draft);

  Future<void> approve(String questionId);

  Future<void> delete(String questionId);
}

class SupabaseQuestionRepository implements QuestionRepository {
  const SupabaseQuestionRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<List<Question>> safeQuestions(String testId, {String? accessCode}) =>
      _guard(() async {
        final response = await _client.rpc(
          'get_test_questions_safe',
          params: {'p_test_id': testId, 'p_access_code': ?accessCode},
        );
        AppLogger.rpcShape('get_test_questions_safe', response);
        if (response == null) return const <Question>[];
        final list = response is List ? response : [response];
        if (list.isNotEmpty &&
            list.first is Map &&
            (list.first as Map).containsKey('correct_option')) {
          AppLogger.error(
            'SECURITY: get_test_questions_safe returned a correct_option key',
          );
        }
        return list
            .map((r) => Question.fromJson(r as Map<String, dynamic>))
            .toList();
      }, TestErrorContext.load);

  @override
  Future<List<Question>> reviewQuestionsForAttempt(String attemptId) =>
      _guard(() async {
        final response = await _client.rpc(
          'rpc_get_review_questions',
          params: {'p_attempt_id': attemptId},
        );
        AppLogger.rpcShape('rpc_get_review_questions', response);
        if (response == null) return const <Question>[];
        final list = response is List ? response : [response];
        return list
            .map((r) => Question.fromJson(r as Map<String, dynamic>))
            .toList();
      }, TestErrorContext.load);

  @override
  Future<String> create(String testId, QuestionDraft draft) => _guard(() async {
    final params = <String, dynamic>{
      'p_test_id': testId,
      ..._draftParams(draft),
    };
    final response = await _client.rpc('rpc_create_question', params: params);
    AppLogger.rpcShape('rpc_create_question', response);
    final data = response is List && response.isNotEmpty
        ? response.first
        : response;
    if (data is Map && data['question_id'] is String) {
      return data['question_id'] as String;
    }
    if (data is String && data.isNotEmpty) return data;
    throw const DataError(message: 'Unexpected response from server.');
  }, TestErrorContext.save);

  @override
  Future<void> update(String questionId, QuestionDraft draft) =>
      _guard(() async {
        await _client.rpc(
          'rpc_update_question',
          params: {'p_question_id': questionId, ..._draftParams(draft)},
        );
      }, TestErrorContext.save);

  @override
  Future<void> approve(String questionId) => _guard(() async {
    await _client.rpc(
      'rpc_update_question',
      params: {'p_question_id': questionId, 'p_status': 'approved'},
    );
  }, TestErrorContext.save);

  @override
  Future<void> delete(String questionId) => _guard(() async {
    await _client.rpc(
      'rpc_delete_question',
      params: {'p_question_id': questionId},
    );
  }, TestErrorContext.save);

  /// Shared create/update param mapping. Option ids are sent as-is (empty for
  /// new options — the server assigns ids); `correct_option` is an index.
  ///
  /// Deliberately NOT sent: `p_negative_marks`. `QuestionDraft.negativeMarks`
  /// is a real, valid field (the `questions` table has its own
  /// `negative_marks` column, separate from the test-level one), but no
  /// live version of `rpc_create_question`/`rpc_update_question` declares a
  /// `p_negative_marks` parameter (checked against every migration that
  /// defines either function: R4_5_1, R4_QUESTION_OPTION_GUARD, R7_FIX/
  /// R7_QUESTION_BANK_V1 for create; R4_5_1, R4_QUESTION_OPTION_GUARD,
  /// R4_FIX_rpc_update_question_status_cast for update — none accept it).
  /// Sending an unknown named parameter makes PostgREST fail to resolve the
  /// function overload entirely, and that failure's message doesn't match
  /// any case in TestErrors.map, so it always surfaced as the generic
  /// "Failed to save. Please try again." — this was breaking question
  /// creation/update for every draft with a non-null negativeMarks value.
  /// Per-question negative marking is not currently settable via any live
  /// RPC; re-add this only alongside a real signature change.
  static Map<String, dynamic> _draftParams(QuestionDraft d) => {
    'p_question': d.questionText,
    'p_question_type': questionTypeToRpc(d.questionType),
    'p_options': [
      for (final o in d.options) {'id': o.id ?? '', 'text': o.text},
    ],
    if (d.correctOptionIndex != null) 'p_correct_option': d.correctOptionIndex,
    if (d.explanation != null) 'p_explanation': d.explanation,
    if (d.subjectId != null) 'p_subject_id': d.subjectId,
    if (d.topicNodeId != null) 'p_topic_node_id': d.topicNodeId,
    'p_difficulty': d.difficulty.name,
    'p_marks': d.marks,
    if (d.language != null) 'p_language': d.language,
  };

  static Future<T> _guard<T>(
    Future<T> Function() body,
    TestErrorContext context,
  ) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'QuestionRepository PostgrestException: code=${e.code}, '
        'message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      throw DataError(message: TestErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('QuestionRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}
