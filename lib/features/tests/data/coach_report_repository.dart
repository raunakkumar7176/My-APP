import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/app_config.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/coach_diagnostic.dart';

/// One `test_ai_coach_reports` row, in the envelope every coach RPC returns:
/// `{cached, attempt_id, report_id?, created_at?, report}`.
///
/// [cached] is the cache-first signal the result screen keys its UI on —
/// `true` means the row already exists (or was just persisted), `false` means
/// this payload has been generated but not yet stored.
final class CoachReportCache {
  const CoachReportCache({
    required this.cached,
    required this.attemptId,
    this.reportId,
    this.createdAt,
    this.report,
    this.rawReport,
  });

  final bool cached;
  final String attemptId;
  final String? reportId;
  final DateTime? createdAt;
  final CoachDiagnostic? report;

  /// The report exactly as it arrived, un-re-encoded, so what gets stored in
  /// `report_data` is the provider's own JSON rather than this client's
  /// interpretation of it.
  final Map<String, dynamic>? rawReport;

  /// A stored row whose payload renders nothing is no better than no row, so
  /// the screen shows the generate CTA for it too.
  bool get hasRenderableReport => report != null && !report!.isEmpty;

  factory CoachReportCache.fromJson(Map<String, dynamic> json) {
    final rawReport = json['report'] is Map
        ? Map<String, dynamic>.from(json['report'] as Map)
        : null;
    final createdAt = json['created_at'];
    return CoachReportCache(
      cached: json['cached'] as bool? ?? false,
      attemptId: (json['attempt_id'] as String?) ?? '',
      reportId: json['report_id'] as String?,
      createdAt: createdAt is String
          ? DateTime.tryParse(createdAt)
          : null,
      report: rawReport == null
          ? null
          : CoachDiagnostic.fromJson(rawReport),
      rawReport: rawReport,
    );
  }
}

/// Cache-first access to `public.test_ai_coach_reports`.
///
/// Reads and writes go through the SECURITY DEFINER RPCs shipped in 0060
/// (`rpc_get_ai_coach_report` / `rpc_save_ai_coach_report`) so authorization
/// and write-once live in one place; only the provider round-trip happens
/// outside Supabase.
abstract interface class CoachReportRepository {
  /// The current user's attempt for [testId], or null when there is none
  /// (or when [testId] is not a uuid — the result screen can be opened
  /// without a real test id).
  Future<String?> attemptIdForTest(String testId);

  /// Reads the cached row. A miss comes back as a non-cached envelope rather
  /// than an error, because "not generated yet" is a normal state.
  Future<CoachReportCache> fetch(String attemptId);

  /// Generates the diagnostic from the provider and stores it. On success the
  /// returned envelope is always `cached: true`.
  Future<CoachReportCache> generateAndSave(String attemptId);
}

class SupabaseCoachReportRepository implements CoachReportRepository {
  const SupabaseCoachReportRepository({http.Client? client})
    : _injectedClient = client;

  /// Injection point for tests (e.g. `http.testing.MockClient`); production
  /// leaves it null and each call uses a fresh auto-closed top-level client.
  final http.Client? _injectedClient;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  SupabaseClient get _client => SupabaseService.client;

  String get _apiBase => AppConfig.current.nextApiUrl;

  @override
  Future<String?> attemptIdForTest(String testId) => _guard(() async {
    if (!_uuid.hasMatch(testId)) return null;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AuthError(message: 'You must be logged in.');
    }
    // `attempts` is unique on (test_id, user_id), so at most one row exists
    // and maybeSingle is safe.
    final row = await _client
        .from('attempts')
        .select('id')
        .eq('test_id', testId)
        .eq('user_id', uid)
        .maybeSingle();
    return row?['id'] as String?;
  });

  @override
  Future<CoachReportCache> fetch(String attemptId) => _guard(() async {
    final response = await _client.rpc(
      'rpc_get_ai_coach_report',
      params: {'p_attempt_id': attemptId},
    );
    AppLogger.rpcShape('rpc_get_ai_coach_report', response);
    return _asEnvelope(response, attemptId);
  });

  @override
  Future<CoachReportCache> generateAndSave(String attemptId) => _guard(() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw const AuthError(message: 'You must be logged in.');
    }

    final generated = await _callProvider(attemptId, session.accessToken);
    if (generated.cached) {
      // The provider read through the cache — another device (or an earlier
      // visit) already stored it, so there is nothing to write.
      return generated;
    }
    if (generated.rawReport == null) {
      throw const DataError(
        message: 'The AI coach returned an empty report. Please try again.',
      );
    }

    final saved = await _client.rpc(
      'rpc_save_ai_coach_report',
      params: {
        'p_attempt_id': attemptId,
        'p_report_data': generated.rawReport,
      },
    );
    AppLogger.rpcShape('rpc_save_ai_coach_report', saved);
    final envelope = _asEnvelope(saved, attemptId);
    // The row is written (or a concurrent writer won the ON CONFLICT race);
    // either way the next visit reads it from the cache.
    return CoachReportCache(
      cached: true,
      attemptId: envelope.attemptId.isEmpty ? attemptId : envelope.attemptId,
      reportId: envelope.reportId,
      createdAt: envelope.createdAt,
      report: envelope.report ?? generated.report,
      rawReport: envelope.rawReport ?? generated.rawReport,
    );
  });

  /// POSTs to the Next.js AI provider route — same pattern as
  /// `AiGenerationRepository`: no API key ever ships in the client.
  Future<CoachReportCache> _callProvider(
    String attemptId,
    String accessToken,
  ) async {
    final uri = Uri.parse('$_apiBase/api/ai/coach-diagnostic');
    AppLogger.info('AI coach diagnostic request: attempt $attemptId');

    // Zone 1 — the request itself. Any failure here means the device could
    // not reach the network or host, so it is the only case reported as a
    // connectivity problem.
    http.Response response;
    try {
      response = await _post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'attempt_id': attemptId}),
      ).timeout(const Duration(seconds: 120));
    } on TimeoutException {
      AppLogger.error('AI coach diagnostic request timed out');
      throw const NetworkError(
        message: 'The AI request took too long and timed out. Please try again.',
      );
    } catch (e) {
      // Socket/DNS/TLS/ClientException all land here. Reported as a
      // connectivity problem because the request never round-tripped.
      AppLogger.error('AI coach diagnostic transport error: $e');
      throw const NetworkError(
        message:
            'No internet connection. Please check your network and try again.',
      );
    }

    // Zone 2 — we got an answer, so anything wrong from here is the service
    // or its configuration, never the user's connection.
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 401) {
        throw AuthError(
          message: data['error'] as String? ?? 'Authentication failed',
        );
      }
      if (response.statusCode != 200) {
        throw DataError(
          message: data['error'] as String? ?? 'AI generation failed',
        );
      }
      return _asEnvelope(data, attemptId);
    } on AppError {
      rethrow;
    } on FormatException catch (e) {
      AppLogger.error(
        'AI coach diagnostic returned a non-JSON body '
        '(${response.statusCode}): $e',
      );
      throw const DataError(
        message: 'AI service temporarily unavailable. Please try again.',
      );
    }
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) {
    final client = _injectedClient;
    if (client != null) return client.post(uri, headers: headers, body: body);
    return http.post(uri, headers: headers, body: body);
  }

  /// Normalises whatever the RPC or provider returned (a map, a jsonb string,
  /// or a one-element list) into the envelope.
  static CoachReportCache _asEnvelope(Object? value, String attemptId) {
    Object? decoded = value;
    if (decoded is String) decoded = jsonDecode(decoded);
    if (decoded is List && decoded.isNotEmpty) decoded = decoded.first;
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      if (map['attempt_id'] == null) map['attempt_id'] = attemptId;
      return CoachReportCache.fromJson(map);
    }
    throw const DataError(
      message: 'The coach service returned an unexpected response.',
    );
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error('CoachReportRepository PostgrestException: ${e.message}');
      throw DataError(message: friendlyPostgrest(e.message));
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('CoachReportRepository unexpected: $e', stackTrace: st);
      throw const DataError(
        message: 'Could not load the AI coach report. Please try again.',
      );
    }
  }

  /// Translates the handful of errors the coach RPCs can raise into copy a
  /// learner can act on; anything else falls back to the generic message.
  static String friendlyPostgrest(String message) {
    final upper = message.toUpperCase();
    if (upper.contains('NOT_AUTHENTICATED')) {
      return 'You must be logged in to use the AI coach.';
    }
    if (upper.contains('NOT_AUTHORIZED')) {
      return 'You do not have access to this attempt.';
    }
    if (upper.contains('ATTEMPT_NOT_FOUND')) {
      return 'Attempt not found.';
    }
    return 'Could not load the AI coach report. Please try again.';
  }
}
