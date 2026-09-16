import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/ai_report.dart';
import 'supabase_service.dart';

final class AiReportService {
  AiReportService._();

  static SupabaseQueryBuilder get _db =>
      SupabaseService.client.from('ai_reports');

  static Future<AiReport?> getReportByResultId(String resultId) async {
    try {
      final response = await _db
          .select()
          .eq('result_id', resultId)
          .maybeSingle();

      if (response == null) return null;
      return AiReport.fromJson(response);
    } on PostgrestException catch (e) {
      AppLogger.error('getReportByResultId PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getReportByResultId unexpected error: $e');
      throw const DataError(message: 'Failed to load AI report. Please try again.');
    }
  }

  static Future<List<AiReport>> getMyReports() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to view reports.');
    }

    try {
      final response = await _db
          .select()
          .eq('user_id', userId)
          .order('generated_at', ascending: false);

      return (response as List<dynamic>)
          .map((json) => AiReport.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getMyReports PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getMyReports unexpected error: $e');
      throw const DataError(message: 'Failed to load AI reports. Please try again.');
    }
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to view this report.';
    }
    if (lower.contains('not found')) {
      return 'AI report not found.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to load AI report. Please try again.';
  }
}
