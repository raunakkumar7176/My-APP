import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/group.dart';
import 'supabase_service.dart';

final class GroupService {
  GroupService._();

  static Future<List<Group>> getUserGroups() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(
          message: 'You must be signed in to view groups.');
    }

    try {
      final response =
          await SupabaseService.client.rpc('rpc_get_user_groups');

      if (response == null) return [];

      final list = response is List ? response : [response];
      return (list)
          .map((json) => Group.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getUserGroups PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getUserGroups unexpected error: $e');
      throw const DataError(
          message: 'Failed to load groups. Please try again.');
    }
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to view groups.';
    }
    if (lower.contains('not found')) {
      return 'Groups not found.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to load groups. Please try again.';
  }
}
