import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/result.dart';
import '../models/result_analytics.dart';
import 'subject_service.dart';
import 'supabase_service.dart';

final class ResultService {
  ResultService._();

  static SupabaseQueryBuilder get _db => SupabaseService.client.from('results');

  static Future<Result?> getResultByAttemptId(String attemptId) async {
    try {
      final response = await _db
          .select()
          .eq('attempt_id', attemptId)
          .maybeSingle();

      if (response == null) return null;
      return Result.fromJson(response);
    } on PostgrestException catch (e) {
      AppLogger.error('getResultByAttemptId PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getResultByAttemptId unexpected error: $e');
      throw const DataError(
        message: 'Failed to load result. Please try again.',
      );
    }
  }

  /// The current user's results for [testId] (attempt history / comparison
  /// with the previous attempt). Filtered by user on the client as well so
  /// history never mixes in other participants' rows, whatever the live
  /// `results` policy permits.
  static Future<List<Result>> getResultsForTest(String testId) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be logged in to view results.');
    }
    try {
      final response = await _db
          .select()
          .eq('test_id', testId)
          .eq('user_id', userId)
          .order('computed_at', ascending: false);

      return (response as List<dynamic>)
          .map((json) => Result.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getResultsForTest PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getResultsForTest unexpected error: $e');
      throw const DataError(
        message: 'Failed to load results. Please try again.',
      );
    }
  }

  static Future<List<Result>> getMyResults() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to view results.');
    }

    try {
      final response = await _db
          .select()
          .eq('user_id', userId)
          .order('computed_at', ascending: false);

      return (response as List<dynamic>)
          .map((json) => Result.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getMyResults PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getMyResults unexpected error: $e');
      throw const DataError(
        message: 'Failed to load your results. Please try again.',
      );
    }
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to view these results.';
    }
    if (lower.contains('not found')) {
      return 'Results not found.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to load results. Please try again.';
  }

  static Future<List<SubjectBreakdownItem>> parseSubjectBreakdown(
    Map<String, dynamic>? rawBreakdown,
  ) async {
    if (rawBreakdown == null || rawBreakdown.isEmpty) return [];

    // Attempt to load subject names
    final Map<String, String> subjectNames = {};
    try {
      final subjects = await SubjectService.loadSubjects();
      for (final s in subjects) {
        subjectNames[s.id] = s.name;
      }
    } catch (_) {
      // Subject names unavailable — use IDs as fallback
    }

    final items = <SubjectBreakdownItem>[];
    for (final entry in rawBreakdown.entries) {
      final data = entry.value;
      if (data is! Map<String, dynamic>) continue;
      items.add(
        SubjectBreakdownItem.fromRaw(
          subjectId: entry.key,
          subjectName:
              subjectNames[entry.key] ??
              'Subject ${entry.key.substring(0, entry.key.length > 8 ? 8 : entry.key.length)}',
          data: data,
        ),
      );
    }
    return items;
  }

  static List<TopicBreakdownItem> parseTopicBreakdown(
    Map<String, dynamic>? rawBreakdown,
  ) {
    if (rawBreakdown == null || rawBreakdown.length < 2) return [];

    final items = <TopicBreakdownItem>[];
    for (final entry in rawBreakdown.entries) {
      final data = entry.value;
      if (data is! Map<String, dynamic>) continue;
      items.add(
        TopicBreakdownItem.fromRaw(
          topicId: entry.key,
          topicName: entry.key.length > 20
              ? '${entry.key.substring(0, 20)}...'
              : entry.key,
          data: data,
        ),
      );
    }
    // Sort by wrong count descending
    items.sort((a, b) => b.wrong.compareTo(a.wrong));
    return items;
  }

  static List<DifficultyBreakdownItem> parseDifficultyBreakdown({
    required int? correctCount,
    required int? wrongCount,
    required int? unansweredCount,
  }) {
    // Difficulty breakdown requires per-question data.
    // Without question-level correct/wrong info from server,
    // we cannot produce authoritative difficulty breakdown.
    // Return empty — the extended card handles this gracefully.
    return [];
  }

  static Result? getPreviousResult({
    required List<Result> allResults,
    required String currentResultId,
  }) {
    if (allResults.length < 2) return null;
    final sorted = List<Result>.from(allResults)
      ..sort(
        (a, b) => (b.computedAt ?? DateTime(0)).compareTo(
          a.computedAt ?? DateTime(0),
        ),
      );
    final currentIndex = sorted.indexWhere((r) => r.id == currentResultId);
    if (currentIndex < 0 || currentIndex >= sorted.length - 1) return null;
    return sorted[currentIndex + 1];
  }
}
