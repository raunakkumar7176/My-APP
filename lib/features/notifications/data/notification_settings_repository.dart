import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';
import 'notification_settings.dart';

/// Repository for reading and writing the caller's `notification_settings`.
/// The server auto-creates a default row on signup via
/// `fn_ensure_notification_settings()`.
abstract interface class NotificationSettingsRepository {
  /// Fetch the caller's notification settings. Returns defaults if no row
  /// exists (should not happen after backfill).
  Future<NotificationSettings> get();

  /// Update the caller's notification settings. Merges with existing values.
  Future<NotificationSettings> update(NotificationSettings settings);
}

final class SupabaseNotificationSettingsRepository
    implements NotificationSettingsRepository {
  const SupabaseNotificationSettingsRepository();

  static SupabaseClient get _client => SupabaseService.client;
  static String? get _uid => AuthService.currentUser?.id;

  static String _requireUid() {
    final uid = _uid;
    if (uid == null) throw const AuthError(message: 'Please sign in again.');
    return uid;
  }

  @override
  Future<NotificationSettings> get() => _guard(() async {
        final uid = _requireUid();
        final row = await _client
            .from('notification_settings')
            .select()
            .eq('user_id', uid)
            .maybeSingle();
        if (row == null) {
          // Fallback: should not happen after backfill, but be safe.
          return NotificationSettings(userId: uid);
        }
        return NotificationSettings.fromJson(row);
      });

  @override
  Future<NotificationSettings> update(NotificationSettings settings) =>
      _guard(() async {
        final uid = _requireUid();
        final updated = await _client
            .from('notification_settings')
            .upsert(
              {'user_id': uid, ...settings.toUpdateMap()},
              onConflict: 'user_id',
            )
            .select()
            .single();
        return NotificationSettings.fromJson(updated);
      });

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'NotificationSettingsRepository PostgrestException: ${e.code} ${e.message}',
      );
      throw DataError(message: 'Settings error: ${e.message}');
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error(
        'NotificationSettingsRepository unexpected: $e',
        stackTrace: st,
      );
      throw DataError(message: 'Settings error: $e');
    }
  }
}
