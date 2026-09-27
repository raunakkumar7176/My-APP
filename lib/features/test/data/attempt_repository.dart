import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/attempt.dart';
import '../../../core/models/submit_scorecard.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/test_errors.dart';

/// Result of starting/joining: the attempt plus the optional `test_title`
/// the code-entry RPC may include (R4_3 shape). Null when absent.
typedef StartedAttempt = ({Attempt attempt, String? testTitle});

/// Server's response to `rpc_record_integrity_event`: whether the event was
/// actually recorded (a terminal attempt or a suppressed duplicate is a
/// no-op, not an error), the server's own running count, the configured
/// threshold, and whether this call caused the server to auto-submit. The
/// count/threshold/auto-submitted fields are the only truth — the client
/// never computes or trusts its own copy of the count.
typedef IntegrityEventOutcome = ({
  bool eventRecorded,
  int integrityEventCount,
  int? autoSubmitThreshold,
  bool autoSubmitted,
});

/// Attempts are created, saved and submitted ONLY through the secure RPCs;
/// the server owns access checks, the deadline, attempt numbering, the
/// re-attempt policy and scoring. The only direct read is the user's OWN
/// attempts ([mine]) under the verified "own attempts" SELECT policy.
abstract interface class AttemptRepository {
  /// Starts attempt 1, resumes an in_progress attempt, or — only with
  /// [reattempt] — allocates attempt N+1 within the test's limit.
  Future<StartedAttempt> start(String testId, {bool reattempt = false});

  Future<StartedAttempt> startByCode(String code, {bool reattempt = false});

  /// The current user's attempts on [testId], ascending attempt_number.
  Future<List<Attempt>> mine(String testId);

  /// Submits and scores on the server via `rpc_submit_and_score_test`
  /// (migration 0060, confirmed live). [timedOut] is a client-side hint only
  /// — the RPC itself derives lateness from `now() > deadline_at` and is not
  /// passed a flag; passing `timedOut` here does not change what the server
  /// does, it only lets the controller set local UI state without waiting
  /// for the round trip.
  Future<SubmitScorecard> submit(String attemptId, {required bool timedOut});

  /// Reports one client-observed integrity event (app backgrounded,
  /// multi-window entered, …) against the caller's own in-progress attempt.
  /// The server owns the count, the threshold, dedup and any resulting
  /// auto-submit — this call never sends a count, only an occurrence.
  Future<IntegrityEventOutcome> recordIntegrityEvent({
    required String attemptId,
    required String testId,
    required String eventType,
    Map<String, dynamic>? details,
  });

  /// Records that the caller accepted the pre-test disclaimer for their own
  /// [attemptId]. Server-side idempotent (a retry/double-call is a silent
  /// no-op, never overwrites the original acceptance).
  Future<void> recordDisclaimerAcceptance({
    required String attemptId,
    required String version,
    required String language,
  });
}

class SupabaseAttemptRepository implements AttemptRepository {
  const SupabaseAttemptRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<StartedAttempt> start(String testId, {bool reattempt = false}) =>
      _guard(() async {
        final response = await _client.rpc(
          'rpc_start_attempt',
          params: {
            'p_test': testId,
            // Live: rpc_start_attempt(p_test uuid, p_reattempt boolean DEFAULT false).
            if (reattempt) 'p_reattempt': true,
          },
        );
        AppLogger.rpcShape('rpc_start_attempt', response);
        return parseStarted(response);
      }, TestErrorContext.start);

  @override
  Future<StartedAttempt> startByCode(String code, {bool reattempt = false}) =>
      _guard(() async {
        final trimmed = code.trim();
        if (trimmed.isEmpty) {
          throw const ValidationError(message: 'Enter a test code.');
        }
        final response = await _client.rpc(
          'rpc_start_attempt_by_code',
          params: {'p_code': trimmed, if (reattempt) 'p_reattempt': true},
        );
        AppLogger.rpcShape('rpc_start_attempt_by_code', response);
        return parseStarted(response);
      }, TestErrorContext.start);

  /// Explicit live columns; never `select *`.
  static const attemptColumns =
      'id, test_id, user_id, status, started_at, deadline_at, submitted_at, '
      'attempt_number, integrity_event_count, auto_submit_threshold';

  @override
  Future<List<Attempt>> mine(String testId) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthError(message: 'You must be logged in.');
    }
    final rows = await _client
        .from('attempts')
        .select(attemptColumns)
        .eq('test_id', testId)
        .eq('user_id', uid)
        .order('attempt_number', ascending: true);
    return [
      for (final r in rows as List) Attempt.fromJson(r as Map<String, dynamic>),
    ];
  }, TestErrorContext.load);

  @override
  Future<SubmitScorecard> submit(String attemptId, {required bool timedOut}) =>
      _guard(() async {
        final response = await _client.rpc(
          'rpc_submit_and_score_test',
          // Live signature: rpc_submit_and_score_test(p_attempt_id uuid) —
          // no p_auto; lateness is derived server-side from deadline_at.
          params: {'p_attempt_id': attemptId},
        );
        AppLogger.rpcShape('rpc_submit_and_score_test', response);
        return scorecardFromSubmitResponse(response);
      }, TestErrorContext.submit);

  @override
  Future<IntegrityEventOutcome> recordIntegrityEvent({
    required String attemptId,
    required String testId,
    required String eventType,
    Map<String, dynamic>? details,
  }) => _guard(() async {
    final response = await _client.rpc(
      'rpc_record_integrity_event',
      params: {
        'p_attempt': attemptId,
        'p_test_id': testId,
        'p_event_type': eventType,
        'p_details': details ?? const <String, dynamic>{},
      },
    );
    AppLogger.rpcShape('rpc_record_integrity_event', response);
    return integrityOutcomeFromResponse(response);
  }, TestErrorContext.submit);

  @override
  Future<void> recordDisclaimerAcceptance({
    required String attemptId,
    required String version,
    required String language,
  }) => _guard(() async {
    final response = await _client.rpc(
      'rpc_record_disclaimer_acceptance',
      params: {
        'p_attempt_id': attemptId,
        'p_version': version,
        'p_language': language,
      },
    );
    AppLogger.rpcShape('rpc_record_disclaimer_acceptance', response);
  }, TestErrorContext.save);

  /// The RPC returns a single jsonb object (never a list). Missing/malformed
  /// keys fail closed to "nothing happened" rather than fabricating a count.
  static IntegrityEventOutcome integrityOutcomeFromResponse(dynamic response) {
    final data = response is List && response.isNotEmpty
        ? response.first
        : response;
    if (data is! Map) {
      throw const DataError(message: 'Unexpected response from server.');
    }
    final json = Map<String, dynamic>.from(data);
    return (
      eventRecorded: json['event_recorded'] as bool? ?? false,
      integrityEventCount: (json['integrity_event_count'] as num?)?.toInt() ?? 0,
      autoSubmitThreshold: (json['auto_submit_threshold'] as num?)?.toInt(),
      autoSubmitted: json['auto_submitted'] as bool? ?? false,
    );
  }

  /// `rpc_submit_and_score_test` always returns one jsonb object (never a
  /// list, never null) on success — a missing/malformed shape is a real
  /// error, not a "nothing happened" case, so this throws rather than
  /// returning null (unlike the old `rpc_submit_attempt` parser it replaces).
  static SubmitScorecard scorecardFromSubmitResponse(dynamic response) {
    final data = response is List && response.isNotEmpty
        ? response.first
        : response;
    if (data is! Map) {
      throw const DataError(message: 'Unexpected response from server.');
    }
    return SubmitScorecard.fromJson(Map<String, dynamic>.from(data));
  }

  /// The ONE place the start RPCs' response is normalized. Accepts both
  /// shapes that exist in the repo history (live shape: see R4.1):
  ///  - jsonb `{attempt_id, test_id, status: started|resumed, started_at,
  ///    deadline_at[, attempt_number, test_title]}` (R4_3)
  ///  - an `attempts` row `{id, test_id, user_id, status, ...}` (R4_7_6)
  /// Anything without a usable attempt id + test id is rejected — never
  /// fabricated.
  static StartedAttempt parseStarted(dynamic response) {
    final data = response is List && response.isNotEmpty
        ? response.first
        : response;
    if (data is! Map) {
      throw const DataError(message: 'Unexpected response from server.');
    }
    final json = Map<String, dynamic>.from(data);
    final title = json['test_title'] is String
        ? json['test_title'] as String
        : null;

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
        message: 'The attempt could not be linked to a test. Please try again.',
      );
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
    Future<T> Function() body,
    TestErrorContext context,
  ) async {
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
