import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import '../models/test_invitation.dart';
import 'supabase_service.dart';

final class InvitationService {
  InvitationService._();

  static SupabaseQueryBuilder get _db =>
      SupabaseService.client.from('test_invitations');

  static Future<List<TestInvitation>> getMyInvitations() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to view invitations.');
    }

    try {
      final response = await _db
          .select()
          .eq('user_id', userId)
          .order('invited_at', ascending: false);

      return (response as List<dynamic>)
          .map((json) => TestInvitation.fromJson(json as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      AppLogger.error('getMyInvitations PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('getMyInvitations unexpected error: $e');
      throw const DataError(message: 'Failed to load invitations. Please try again.');
    }
  }

  static Future<void> respondToInvitation({
    required String invitationId,
    required String status,
  }) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthError(message: 'You must be signed in to respond.');
    }

    try {
      await _db.update({
        'status': status,
        'responded_at': DateTime.now().toIso8601String(),
      }).eq('id', invitationId).eq('user_id', userId);

      AppLogger.info('Invitation $invitationId responded with: $status');
    } on PostgrestException catch (e) {
      AppLogger.error('respondToInvitation PostgrestException: ${e.message}');
      throw DataError(message: _mapErrorMessage(e.message));
    } catch (e) {
      if (e is AppError) rethrow;
      AppLogger.error('respondToInvitation unexpected error: $e');
      throw const DataError(message: 'Failed to respond to invitation. Please try again.');
    }
  }

  static String _mapErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      return 'You do not have permission to modify this invitation.';
    }
    if (lower.contains('not found')) {
      return 'Invitation not found.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    return 'Failed to process invitation. Please try again.';
  }
}
