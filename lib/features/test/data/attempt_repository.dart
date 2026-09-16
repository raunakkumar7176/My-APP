import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/attempt.dart';
import '../../../core/models/result.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/test_errors.dart';

/// Result of starting/joining: the attempt plus the optional `test_title`
/// the code-entry RPC may include (R4_3 shape). Null when absent.
typedef StartedAttempt = ({Attempt attempt, String? testTitle});

/// Attempts are created, saved and submitted ONLY through the secure RPCs.
/// The client never reads or writes `public.attempts` directly; the server
/// owns access checks, the deadline, attempt numbering and scoring.
abstract interface class AttemptRepository {
  Future<StartedAttempt> start(String testId);

  Future<StartedAttempt> startByCode(String code);

  /// Submits and scores on the server. Returns the `results` row when the
  /// RPC includes one in its response; null otherwise (the result screen
  /// then reads the row via RLS). The live return shape is NOT VERIFIED.
  Future<Result?> submit(String attemptId, {required bool timedOut});
}

class SupabaseAttemptRepository implements AttemptRepository {
  const SupabaseAttemptRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<StartedAttempt> start(String testId) => _guard(() async {
        final response =
            await _client.rpc('rpc_start_attempt', params: {'p_test': testId});
        AppLogger.rpcShape('rpc_start_attempt', response);
        return parseStarted(response);
      }, TestErrorContext.start);

  @override
  Future<StartedAttempt> startByCode(String code) => _guard(() async {
        final trimmed = code.trim();
        if (trimmed.isEmpty) {
          throw const ValidationError(message: 'Enter a test code.');
        }
        final response = await _client
            .rpc('rpc_start_attempt_by_code', params: {'p_code': trimmed});
        AppLogger.rpcShape('rpc_start_attempt_by_code', response);
        return parseStarted(response);
      }, TestErrorContext.start);

  @override
  Future<Result?> submit(String attemptId, {required bool timedOut}) =>
      _guard(() async {
        final response = await _client.rpc('rpc_submit_attempt', params: {
          'p_attempt': attemptId,
          'p_timed_out': timedOut,
        });
        AppLogger.rpcShape('rpc_submit_attempt', response);
        return resultFromSubmitResponse(response, attemptId: attemptId);
      }, TestErrorContext.submit);

  /// A `results` row is recognised by its `attempt_id` + a score-like key;
  /// an `attempts` row, a status message or null yield null (not an error —
  /// the submission itself succeeded).
  static Result? resultFromSubmitResponse(dynamic response, {required String attemptId}) {
    final data =
        response is List && response.isNotEmpty ? response.first : response;
    if (data is! Map) return null;
    final json = Map<String, dynamic>.from(data);
    final looksLikeResult = json['attempt_id'] == attemptId &&
        (json.containsKey('score') ||
            json.containsKey('marks_obtained') ||
            json.containsKey('correct_count') ||
            json.containsKey('percentage'));
    if (!looksLikeResult) return null;
    try {
      return Result.fromJson(json);
    } catch (e) {
      AppLogger.warning('Submit response not parseable as Result: $e');
      return null;
    }
  }

  /// The ONE place the start RPCs' response is normalized. Accepts both
  /// shapes that exist in the repo history (live shape: see R4.1):
  ///  - jsonb `{attempt_id, test_id, status: started|resumed, started_at,
  ///    deadline_at[, attempt_number, test_title]}` (R4_3)
  ///  - an `attempts` row `{id, test_id, user_id, status, ...}` (R4_7_6)
  /// Anything without a usable attempt id + test id is rejected — never
  /// fabricated.
  static StartedAttempt parseStarted(dynamic response) {
    final data =
        response is List && response.isNotEmpty ? response.first : response;
    if (data is! Map) {
      throw const DataError(message: 'Unexpected response from server.');
    }
    final json = Map<String, dynamic>.from(data);
    final title = json['test_title'] is String ? json['test_title'] as String : null;

    final Attempt attempt;
    if (json['attempt_id'] is String) {
      final status = json['status'] as String?;
      attempt = Attempt(
        id: json['attempt_id'] as String,
        testId: json['test_id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        status: _statusFromOperation(status),
        startedAt: json['started_at'] != null
            ? DateTime.parse(json['started_at'] as String)
            : DateTime.now(),
        attemptNumber: (json['attempt_number'] as num?)?.toInt() ?? 1,
        deadlineAt: json['deadline_at'] != null
            ? DateTime.parse(json['deadline_at'] as String)
            : null,
      );
    } else if (json['id'] is String) {
      attempt = Attempt.fromJson(json);
    } else {
      throw const DataError(message: 'Unexpected response from server.');
    }

    if (attempt.testId.isEmpty) {
      AppLogger.error('Start RPC response had no test_id');
      throw const DataError(
          message: 'The attempt could not be linked to a test. Please try again.');
    }
    return (attempt: attempt, testTitle: title);
  }

  static AttemptStatus _statusFromOperation(String? s) {
    switch (s) {
      case 'started':
      case 'resumed':
      case 'in_progress':
        return AttemptStatus.inProgress;
      case 'submitted':
        return AttemptStatus.submitted;
      case 'auto_submitted':
        return AttemptStatus.autoSubmitted;
      case 'scored':
        return AttemptStatus.scored;
      default:
        return AttemptStatus.inProgress;
    }
  }

  static Future<T> _guard<T>(
      Future<T> Function() body, TestErrorContext context) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('AttemptRepository PostgrestException: ${e.message}');
      throw DataError(message: TestErrors.map(e.message, context: context));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('AttemptRepository unexpected: $e', stackTrace: st);
      throw DataError(message: TestErrors.map(e.toString(), context: context));
    }
  }
}
