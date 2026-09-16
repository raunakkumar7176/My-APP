import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/subject.dart';
import 'supabase_service.dart';

final class SubjectService {
  SubjectService._();

  static SupabaseQueryBuilder get _db => SupabaseService.client.from('subjects');

  static Future<List<Subject>> loadSubjects() async {
    try {
      final response = await _db.select('id, name');

      final subjects = (response as List<dynamic>)
          .map((json) => Subject.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Loaded ${subjects.length} subjects.');
      return subjects;
    } on PostgrestException catch (e) {
      AppLogger.error('Subject load PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('Subject load unexpected error: $e');
      throw const DataError(message: 'Failed to load subjects. Please try again.');
    }
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to view subjects.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to load subjects. Please try again.';
  }
}
