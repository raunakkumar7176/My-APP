import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/challenge_session.dart';
import '../../../core/services/supabase_service.dart';

/// Live subscription handle to a session's participant roster.
abstract interface class ChallengeRosterSubscription {
  Future<void> cancel();
}

/// Wraps the four `rpc_*` functions from migration 0061
/// (`0061_challenge_sessions_and_merit_list.sql`) plus the direct
/// `challenge_participants` writes RLS already permits the caller to make on
/// their own row ("Participants can update their own submission details").
/// No new schema is invented here — every read/write targets exactly what
/// that migration created.
abstract interface class ChallengeRepository {
  /// Host action: mints a session + 6-digit PIN via `rpc_create_challenge_session`.
  Future<ChallengeSession> createSession({
    required String? testId,
    required String title,
    required String subject,
    required int durationMinutes,
  });

  /// Candidate action: joins by PIN via `rpc_join_challenge_session`.
  Future<ChallengeSession> joinByPin(String pinCode);

  /// Host action: broadcasts a synchronized start (+5s lead) via
  /// `rpc_commence_challenge_session`.
  Future<ChallengeSession> commence(String sessionId);

  /// Re-fetches one session row (e.g. to pick up a status change a realtime
  /// event already announced).
  Future<ChallengeSession?> getSession(String sessionId);

  /// Current roster for a session (host + all joined candidates).
  Future<List<ChallengeParticipant>> getRoster(String sessionId);

  /// Ranked results via `rpc_get_challenge_merit_list`.
  Future<List<ChallengeMeritRow>> getMeritList(String sessionId);

  /// Binds the caller's own participant row to the real attempt they just
  /// started for this session's test, so the taking screen and later the
  /// merit list can be traced back to this session. RLS: caller updates only
  /// their own row (`user_id = auth.uid()`).
  Future<void> bindAttempt({
    required String sessionId,
    required String attemptId,
  });

  /// Writes the caller's own result back once their attempt is scored. RLS:
  /// caller updates only their own row.
  Future<void> reportResult({
    required String sessionId,
    required double score,
    required double accuracy,
    required int timeTakenSeconds,
  });

  /// Live updates to a session's roster (INSERT/UPDATE on
  /// `challenge_participants` filtered to this session).
  ChallengeRosterSubscription subscribeToRoster({
    required String sessionId,
    required void Function(ChallengeParticipant participant) onChange,
  });

  /// Live updates to the session row itself (status / commence_at changes —
  /// how a candidate's waiting room learns the host commenced).
  ChallengeRosterSubscription subscribeToSession({
    required String sessionId,
    required void Function(ChallengeSession session) onChange,
  });
}

class SupabaseChallengeRepository implements ChallengeRepository {
  const SupabaseChallengeRepository();

  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<ChallengeSession> createSession({
    required String? testId,
    required String title,
    required String subject,
    required int durationMinutes,
  }) => _guard(() async {
    final res = await _client.rpc(
      'rpc_create_challenge_session',
      params: {
        'p_test_id': testId,
        'p_title': title,
        'p_subject': subject,
        'p_duration_minutes': durationMinutes,
      },
    );
    final data = _asMap(res);
    if (data['success'] != true) {
      throw DataError(
        message: data['error'] as String? ?? 'Could not create the session.',
      );
    }
    final session = await getSession(data['session_id'] as String);
    if (session == null) {
      throw const DataError(message: 'Session created but could not be loaded.');
    }
    return session;
  });

  @override
  Future<ChallengeSession> joinByPin(String pinCode) => _guard(() async {
    final res = await _client.rpc(
      'rpc_join_challenge_session',
      params: {'p_pin_code': pinCode},
    );
    final data = _asMap(res);
    if (data['success'] != true) {
      throw ValidationError(
        message: data['error'] as String? ?? 'Invalid examination PIN.',
      );
    }
    return ChallengeSession(
      id: data['session_id'] as String,
      pinCode: data['pin_code'] as String? ?? pinCode,
      hostUserId: '', // not returned by this RPC; refreshed by getSession
      testId: null,
      title: data['title'] as String? ?? 'Academic Peer Challenge',
      subject: data['subject'] as String? ?? 'General Studies',
      durationMinutes: (data['duration_minutes'] as num?)?.toInt() ?? 30,
      status: data['status'] as String? ?? 'waiting_room',
      commenceAt: data['commence_at'] != null
          ? DateTime.parse(data['commence_at'] as String)
          : null,
      createdAt: DateTime.now(),
    );
  });

  @override
  Future<ChallengeSession> commence(String sessionId) => _guard(() async {
    final res = await _client.rpc(
      'rpc_commence_challenge_session',
      params: {'p_session_id': sessionId},
    );
    final data = _asMap(res);
    if (data['success'] != true) {
      throw DataError(
        message: data['error'] as String? ?? 'Could not commence the session.',
      );
    }
    final session = await getSession(sessionId);
    if (session == null) {
      throw const DataError(message: 'Session not found after commence.');
    }
    return session;
  });

  @override
  Future<ChallengeSession?> getSession(String sessionId) => _guard(() async {
    final row = await _client
        .from('challenge_sessions')
        .select()
        .eq('id', sessionId)
        .maybeSingle();
    return row == null ? null : ChallengeSession.fromJson(row);
  });

  @override
  Future<List<ChallengeParticipant>> getRoster(String sessionId) =>
      _guard(() async {
        final rows = await _client
            .from('challenge_participants')
            .select()
            .eq('session_id', sessionId)
            .order('joined_at', ascending: true);
        return (rows as List)
            .map((r) => ChallengeParticipant.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList();
      });

  @override
  Future<List<ChallengeMeritRow>> getMeritList(String sessionId) =>
      _guard(() async {
        final rows = await _client.rpc(
          'rpc_get_challenge_merit_list',
          params: {'p_session_id': sessionId},
        );
        return (rows as List)
            .map((r) => ChallengeMeritRow.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList();
      });

  @override
  Future<void> bindAttempt({
    required String sessionId,
    required String attemptId,
  }) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthError(message: 'You must be signed in.');
    await _client
        .from('challenge_participants')
        .update({'attempt_id': attemptId})
        .eq('session_id', sessionId)
        .eq('user_id', uid);
  });

  @override
  Future<void> reportResult({
    required String sessionId,
    required double score,
    required double accuracy,
    required int timeTakenSeconds,
  }) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthError(message: 'You must be signed in.');
    await _client
        .from('challenge_participants')
        .update({
          'score': score,
          'accuracy': accuracy,
          'time_taken_seconds': timeTakenSeconds,
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('session_id', sessionId)
        .eq('user_id', uid);
  });

  @override
  ChallengeRosterSubscription subscribeToRoster({
    required String sessionId,
    required void Function(ChallengeParticipant participant) onChange,
  }) {
    final channel = _client.channel('challenge_participants:$sessionId');
    void handle(PostgresChangePayload payload) {
      try {
        onChange(ChallengeParticipant.fromJson(payload.newRecord));
      } catch (e, st) {
        AppLogger.error(
          'Realtime challenge_participants decode failed: $e',
          stackTrace: st,
        );
      }
    }

    channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'challenge_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'session_id',
          value: sessionId,
        ),
        callback: handle,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'challenge_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'session_id',
          value: sessionId,
        ),
        callback: handle,
      )
      ..subscribe();

    return _ChannelSubscription(_client, channel);
  }

  @override
  ChallengeRosterSubscription subscribeToSession({
    required String sessionId,
    required void Function(ChallengeSession session) onChange,
  }) {
    final channel = _client.channel('challenge_sessions:$sessionId');
    channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'challenge_sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: sessionId,
        ),
        callback: (payload) {
          try {
            onChange(ChallengeSession.fromJson(payload.newRecord));
          } catch (e, st) {
            AppLogger.error(
              'Realtime challenge_sessions decode failed: $e',
              stackTrace: st,
            );
          }
        },
      )
      ..subscribe();

    return _ChannelSubscription(_client, channel);
  }

  static Map<String, dynamic> _asMap(Object? res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    throw const DataError(message: 'Unexpected response from server.');
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('ChallengeRepository PostgrestException: ${e.message}');
      throw DataError(message: e.message);
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('ChallengeRepository unexpected: $e', stackTrace: st);
      throw const DataError(message: 'Something went wrong. Please try again.');
    }
  }
}

class _ChannelSubscription implements ChallengeRosterSubscription {
  _ChannelSubscription(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> cancel() async {
    await _client.removeChannel(_channel);
  }
}
