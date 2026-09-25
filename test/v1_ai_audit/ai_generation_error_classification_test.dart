// AI System Audit — error classification for the Via AI HTTP path
// (lib/features/test/data/ai_generation_repository.dart).
//
// Root cause of the "No Internet" misdiagnosis: every failure past the
// initial HTTP round-trip (bad status code, server error, malformed JSON)
// used to collapse into one generic "Network error. Please check your
// connection" message. These tests pin the corrected classification so a
// broken/misconfigured AI server is never reported as a connectivity issue.
//
// Pure Dart — no Supabase, no real network. `classifyHttpError` is the
// @visibleForTesting pure function extracted from the response-handling
// branch; the transport-level try/catch (timeout/socket/client-exception ->
// NetworkError) lives in the same method and is reviewed by inspection
// below rather than executed, since exercising it end-to-end requires a
// live Supabase session this test environment cannot fake (see the
// AI System Audit final report for what live/full-stack verification would
// still need).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/features/test/data/ai_generation_repository.dart';

void main() {
  group('AiGenerationRepository.classifyHttpError', () {
    test('401 maps to AuthError, not a generic/network error', () {
      final err = AiGenerationRepository.classifyHttpError(401, {});
      expect(err, isA<AuthError>());
      expect(err, isNot(isA<NetworkError>()));
    });

    test('403 maps to AuthError with the server-provided message', () {
      final err = AiGenerationRepository.classifyHttpError(
        403,
        {'error': 'You must belong to the selected group'},
      );
      expect(err, isA<AuthError>());
      expect(err.message, 'You must belong to the selected group');
    });

    test('429 (rate limited / quota) maps to DataError, not NetworkError', () {
      final err = AiGenerationRepository.classifyHttpError(
        429,
        {'error': 'Daily AI limit reached (3/day). Try again tomorrow or use Manual/Upload.'},
      );
      expect(err, isA<DataError>());
      expect(err, isNot(isA<NetworkError>()));
      expect(err.message, contains('Daily AI limit'));
    });

    test('429 with no server message still gets a rate-limit-specific message', () {
      final err = AiGenerationRepository.classifyHttpError(429, {});
      expect(err, isA<DataError>());
      expect(err.message, contains('rate-limited'));
    });

    test('503 (AI/model not configured) maps to DataError with a config-specific message', () {
      final err = AiGenerationRepository.classifyHttpError(
        503,
        {'error': 'AI is not configured on this environment.'},
      );
      expect(err, isA<DataError>());
      expect(err, isNot(isA<NetworkError>()));
      expect(err.message, contains('not configured'));
    });

    test('500 (server error) maps to DataError, never claims a connectivity problem', () {
      final err = AiGenerationRepository.classifyHttpError(500, {});
      expect(err, isA<DataError>());
      expect(err, isNot(isA<NetworkError>()));
      expect(err.message.toLowerCase(), isNot(contains('internet')));
    });

    test('500 with a server-provided message uses it verbatim', () {
      final err = AiGenerationRepository.classifyHttpError(
        500,
        {'error': 'Internal error: something exploded'},
      );
      expect(err, isA<DataError>());
      expect(err.message, 'Internal error: something exploded');
    });

    test('502/504 (gateway errors) still classify as DataError via the >=500 branch', () {
      expect(AiGenerationRepository.classifyHttpError(502, {}), isA<DataError>());
      expect(AiGenerationRepository.classifyHttpError(504, {}), isA<DataError>());
    });

    test('a plain 400 (invalid request) maps to DataError with the server reason', () {
      final err = AiGenerationRepository.classifyHttpError(
        400,
        {'error': 'Question count must be 1-30'},
      );
      expect(err, isA<DataError>());
      expect(err.message, 'Question count must be 1-30');
    });

    test('a 422 (validation failure, e.g. wrong question count from the model) maps to DataError', () {
      final err = AiGenerationRepository.classifyHttpError(
        422,
        {'error': 'AI generated an unexpected number of questions. Expected 5, got 3. Please regenerate.'},
      );
      expect(err, isA<DataError>());
      expect(err.message, contains('unexpected number of questions'));
    });

    test('none of the non-2xx classifications are ever NetworkError — only the transport catch clauses are', () {
      for (final code in [400, 401, 403, 404, 409, 422, 429, 500, 502, 503, 504]) {
        final err = AiGenerationRepository.classifyHttpError(code, {});
        expect(
          err,
          isNot(isA<NetworkError>()),
          reason: 'status $code round-tripped over the network successfully; '
              'it must never be reported as a connectivity failure',
        );
      }
    });
  });

  group('AppError taxonomy sanity (documents the classification contract)', () {
    test('NetworkError and DataError are distinct, non-overlapping AppError subtypes', () {
      const network = NetworkError(message: 'No internet connection.');
      const data = DataError(message: 'AI service temporarily unavailable.');
      expect(network, isA<AppError>());
      expect(data, isA<AppError>());
      expect(network.runtimeType, isNot(data.runtimeType));
    });
  });
}
