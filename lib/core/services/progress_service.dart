import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/progress_snapshot.dart';
import 'supabase_service.dart';

final class ProgressService {
  ProgressService._();

  static SupabaseQueryBuilder get _db =>
      SupabaseService.client.from('progress_snapshots');

  static Future<List<ProgressSnapshot>> loadUserProgress() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      return [];
    }

    try {
      final response = await _db
          .select('id, user_id, period_type, period_start, stats, computed_at')
          .eq('user_id', userId)
          .order('period_start', ascending: false)
          .limit(10);

      final snapshots = (response as List<dynamic>)
          .map((json) => ProgressSnapshot.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Loaded ${snapshots.length} progress snapshots.');
      return snapshots;
    } on PostgrestException catch (e) {
      AppLogger.error('Progress load PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Progress load unexpected error: $e');
      throw const DataError(message: 'Failed to load progress. Please try again.');
    }
  }

  static ProgressSnapshot? getLatestProgress(List<ProgressSnapshot> snapshots) {
    if (snapshots.isEmpty) return null;
    return snapshots.first;
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to view progress.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to load progress. Please try again.';
  }
}
