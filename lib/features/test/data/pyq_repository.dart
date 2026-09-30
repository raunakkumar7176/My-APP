import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/pyq_models.dart';
import '../domain/test_errors.dart';

/// Repository for the PYQ (Previous Year Questions) catalog and the
/// Practice/Test engine — all access goes through SECURITY DEFINER RPCs
/// (0087_pyq_catalog_and_engine.sql), never a direct `question_bank`
/// table read, so Test Mode never receives `correct_option` before the
/// student submits.
abstract interface class PyqRepository {
  Future<List<PyqCatalogEntry>> fetchCatalog();

  Future<List<PyqQuestion>> fetchPracticeQuestions({
    required String examName,
    required int examYear,
    String? examShift,
  });

  Future<List<PyqQuestion>> fetchTestQuestions({
    required String examName,
    required int examYear,
    String? examShift,
  });

  Future<PyqTestResult> submitTest(
    List<({String questionId, int? selectedOption})> answers,
  );
}

class SupabasePyqRepository implements PyqRepository {
  const SupabasePyqRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<List<PyqCatalogEntry>> fetchCatalog() => _guard(() async {
    final response = await _client.rpc('rpc_get_pyq_catalog');
    AppLogger.rpcShape('rpc_get_pyq_catalog', response);
    if (response is! List) return const [];
    return response
        .map((e) => PyqCatalogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  });

  @override
  Future<List<PyqQuestion>> fetchPracticeQuestions({
    required String examName,
    required int examYear,
    String? examShift,
  }) => _guard(() async {
    final response = await _client.rpc(
      'rpc_get_pyq_questions_practice',
      params: {
        'p_exam_name': examName,
        'p_exam_year': examYear,
        'p_exam_shift': examShift,
      },
    );
    if (response is! List) return const [];
    return response
        .map((e) => PyqQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  });

  @override
  Future<List<PyqQuestion>> fetchTestQuestions({
    required String examName,
    required int examYear,
    String? examShift,
  }) => _guard(() async {
    final response = await _client.rpc(
      'rpc_get_pyq_questions_test',
      params: {
        'p_exam_name': examName,
        'p_exam_year': examYear,
        'p_exam_shift': examShift,
      },
    );
    if (response is! List) return const [];
    return response
        .map((e) => PyqQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  });

  @override
  Future<PyqTestResult> submitTest(
    List<({String questionId, int? selectedOption})> answers,
  ) => _guard(() async {
    final payload = answers
        .map((a) => {'question_id': a.questionId, 'selected_option': a.selectedOption})
        .toList();
    final response = await _client.rpc(
      'rpc_submit_pyq_test',
      params: {'p_answers': payload},
    );
    AppLogger.rpcShape('rpc_submit_pyq_test', response);
    return PyqTestResult.fromJson(
      response is Map ? Map<String, dynamic>.from(response) : {},
    );
  });

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('PyqRepository PostgrestException: ${e.message}');
      throw DataError(message: TestErrors.map(e.message, context: TestErrorContext.load));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('PyqRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: TestErrorContext.load));
    }
  }
}
