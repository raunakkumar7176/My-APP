import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/attempt.dart';
import '../models/result.dart';
import 'supabase_service.dart';

final class AttemptService {
  AttemptService._();

  static Future<Attempt> startAttempt(String testId) async {
    try {
      final response = await SupabaseService.client
          .rpc('rpc_start_attempt', params: {'p_test': testId});

      AppLogger.rpcShape('rpc_start_attempt', response);
      if (response == null) {
        throw const DataError(message: 'Failed to start attempt. No response from server.');
      }

      final data = response is Map<String, dynamic> ? response : response as dynamic;
      return _parseAttemptResponse(data);
    } on PostgrestException catch (e) {
      AppLogger.error('startAttempt PostgrestException: ${e.message}');
      throw DataError(message: _mapAttemptErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('startAttempt unexpected error: $e');
      throw const DataError(message: 'Failed to start attempt. Please try again.');
    }
  }

  static Future<Attempt> startAttemptByCode(String code) async =>
      (await joinByCode(code)).attempt;

  /// Starts (or resumes) an attempt via an access/join code.
  ///
  /// The RPC may return either a jsonb object (which can carry `test_title`)
  /// or an `attempts` row; both are handled. `testTitle` is null when the
  /// server does not include it — callers must fall back gracefully.
  static Future<({Attempt attempt, String? testTitle})> joinByCode(
      String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw const ValidationError(message: 'Enter a test code.');
    }
    try {
      final response = await SupabaseService.client
          .rpc('rpc_start_attempt_by_code', params: {'p_code': trimmed});

      AppLogger.rpcShape('rpc_start_attempt_by_code', response);
      if (response == null) {
        throw const DataError(message: 'Failed to start attempt. No response from server.');
      }

      final data = response is Map<String, dynamic> ? response : response as dynamic;
      final attempt = _parseAttemptResponse(data);
      if (attempt.testId.isEmpty) {
        // A bare id / unexpected shape: the test cannot be loaded from it.
        throw const DataError(
            message: 'Joined, but the test could not be identified. Please try again.');
      }
      final title = data is Map<String, dynamic> ? data['test_title'] as String? : null;
      return (attempt: attempt, testTitle: title);
    } on PostgrestException catch (e) {
      AppLogger.error('startAttemptByCode PostgrestException: ${e.message}');
      throw DataError(message: _mapAttemptErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('startAttemptByCode unexpected error: $e');
      throw const DataError(message: 'Failed to start attempt. Please try again.');
    }
  }

  static Future<Result> submitAttempt({
    required String attemptId,
    required bool timedOut,
  }) async {
    try {
      final response = await SupabaseService.client
          .rpc('rpc_submit_attempt', params: {
        'p_attempt': attemptId,
        'p_timed_out': timedOut,
      });

      AppLogger.rpcShape('rpc_submit_attempt', response);
      if (response == null) {
        throw const DataError(message: 'No response from server after submission.');
      }

      if (response is Map<String, dynamic>) {
        return Result.fromJson(response);
      }

      if (response is List && response.isNotEmpty) {
        final first = response.first;
        if (first is Map<String, dynamic>) {
          return Result.fromJson(first);
        }
      }

      throw const DataError(message: 'Unexpected response format from server.');
    } on PostgrestException catch (e) {
      AppLogger.error('submitAttempt PostgrestException: ${e.message}');
      throw DataError(message: _mapSubmitErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('submitAttempt unexpected error: $e');
      throw const DataError(message: 'Failed to submit test. Please try again.');
    }
  }

  static Attempt _parseAttemptResponse(dynamic response) {
    if (response is Map<String, dynamic>) {
      if (response.containsKey('attempt_id')) {
        final operationStatus = response['status'] as String?;
        AttemptStatus attemptStatus;
        switch (operationStatus) {
          case 'started':
          case 'resumed':
            attemptStatus = AttemptStatus.inProgress;
            break;
          case 'submitted':
            attemptStatus = AttemptStatus.submitted;
            break;
          case 'auto_submitted':
            attemptStatus = AttemptStatus.autoSubmitted;
            break;
          case 'scored':
            attemptStatus = AttemptStatus.scored;
            break;
          default:
            attemptStatus = AttemptStatus.inProgress;
        }

        return Attempt(
          id: response['attempt_id'] as String,
          testId: response['test_id'] as String? ?? '',
          userId: '',
          status: attemptStatus,
          startedAt: response['started_at'] != null
              ? DateTime.parse(response['started_at'] as String)
              : DateTime.now(),
          attemptNumber:
              (response['attempt_number'] as num?)?.toInt() ?? 1,
          deadlineAt: response['deadline_at'] != null
              ? DateTime.parse(response['deadline_at'] as String)
              : null,
        );
      }
      return Attempt.fromJson(response);
    }

    if (response is String) {
      return Attempt(
        id: response,
        testId: '',
        userId: '',
        status: AttemptStatus.inProgress,
        startedAt: DateTime.now(),
      );
    }

    throw const DataError(message: 'Unexpected response format from server.');
  }

  static String _mapAttemptErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('not_authenticated')) {
      return 'You must be signed in to start a test.';
    }
    if (lower.contains('test_code_invalid')) {
      return 'Invalid test code. Please check and try again.';
    }
    if (lower.contains('test_code_ambiguous')) {
      return 'This code matches more than one test. Ask the creator for the exact code.';
    }
    if (lower.contains('late_join_not_allowed')) {
      return 'This challenge has already started and does not allow late joining.';
    }
    if (lower.contains('test_not_found')) {
      return 'Test not found.';
    }
    if (lower.contains('test_not_available') || lower.contains('test_not_started')) {
      return 'This test is not currently available.';
    }
    if (lower.contains('test_ended')) {
      return 'This test has ended.';
    }
    if (lower.contains('test_full')) {
      return 'This test has reached maximum participants.';
    }
    if (lower.contains('test_access_denied')) {
      return 'You do not have access to this test.';
    }
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to start this test.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to start test. Please try again.';
  }

  static String _mapSubmitErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('not_authenticated')) {
      return 'You must be signed in to submit a test.';
    }
    if (lower.contains('attempt_not_found') || lower.contains('not found')) {
      return 'Attempt not found.';
    }
    if (lower.contains('attempt_not_owned') || lower.contains('not owned')) {
      return 'You do not have permission to submit this attempt.';
    }
    if (lower.contains('attempt_not_in_progress') || lower.contains('not in progress')) {
      return 'This attempt is no longer in progress.';
    }
    if (lower.contains('deadline_expired') || lower.contains('deadline passed')) {
      return 'The deadline has expired. Your test has been auto-submitted.';
    }
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to submit this test.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to submit test. Please try again.';
  }
}
