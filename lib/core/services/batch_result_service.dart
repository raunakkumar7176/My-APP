import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/result_batch.dart';
import 'supabase_service.dart';

final class BatchResultService {
  BatchResultService._();

  static SupabaseQueryBuilder get _db =>
      SupabaseService.client.from('result_batches');

  static Future<ResultBatch> generateResults(String testId) async {
    try {
      final response = await SupabaseService.client
          .rpc('rpc_generate_results', params: {'p_test_id': testId});

      if (response == null) {
        throw const DataError(
            message: 'No response from server when generating results.');
      }

      if (response is Map<String, dynamic>) {
        return ResultBatch.fromJson(response);
      }

      if (response is String) {
        final batch = await getLatestBatch(testId);
        if (batch != null) return batch;
        throw const DataError(
            message: 'Batch created but status could not be retrieved.');
      }

      if (response is List && response.isNotEmpty) {
        final first = response.first;
        if (first is Map<String, dynamic>) {
          return ResultBatch.fromJson(first);
        }
      }

      throw const DataError(
          message: 'Unexpected response format from server.');
    } on PostgrestException catch (e) {
      AppLogger.error('generateResults PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('generateResults unexpected error: $e');
      throw const DataError(
          message: 'Failed to generate results. Please try again.');
    }
  }

  static Future<ResultBatch?> getLatestBatch(String testId) async {
    try {
      final response = await _db
          .select()
          .eq('test_id', testId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return ResultBatch.fromJson(response);
    } on PostgrestException catch (e) {
      AppLogger.error('getLatestBatch PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getLatestBatch unexpected error: $e');
      throw const DataError(
          message: 'Failed to load batch status. Please try again.');
    }
  }

  static Future<List<ResultBatch>> getBatchesForTest(String testId) async {
    try {
      final response = await _db
          .select()
          .eq('test_id', testId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((json) => ResultBatch.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getBatchesForTest PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getBatchesForTest unexpected error: $e');
      throw const DataError(
          message: 'Failed to load batches. Please try again.');
    }
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to generate results.';
    }
    if (lower.contains('not_authenticated')) {
      return 'You must be signed in to generate results.';
    }
    if (lower.contains('not_found')) {
      return 'Test not found.';
    }
    if (lower.contains('already_processing') ||
        lower.contains('batch already in progress')) {
      return 'A batch is already processing. Please wait.';
    }
    if (lower.contains('already_completed') ||
        lower.contains('results already generated')) {
      return 'Results have already been generated for this test.';
    }
    if (lower.contains('no_eligible') || lower.contains('no eligible')) {
      return 'No eligible attempts found to process.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to generate results. Please try again.';
  }
}
