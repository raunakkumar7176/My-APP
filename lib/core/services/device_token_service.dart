import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import 'supabase_service.dart';

/// CRUD against `public.user_device_tokens` — the FCM token registry.
///
/// SECURITY: every write is scoped to the authenticated session's own uid
/// (RLS also enforces this server-side); no method here accepts a
/// caller-supplied user id.
abstract interface class DeviceTokenService {
  /// Registers (or refreshes) this device's FCM token for the current
  /// user. Upserts on (user_id, fcm_token) — a token refresh on the SAME
  /// device updates the same row; a different device gets its own row, so
  /// logging in elsewhere never evicts this one.
  Future<void> registerToken({
    required String fcmToken,
    String? deviceId,
    String? appVersion,
  });

  /// Deactivates (does not delete — keeps history for debugging) this
  /// device's token, e.g. on logout. Idempotent.
  Future<void> deactivateToken(String fcmToken);

  /// Deactivates every token for the current user, regardless of device —
  /// used only for an explicit "sign out everywhere" action, never for a
  /// normal single-device logout (see [deactivateToken]).
  Future<void> deactivateAllTokensForCurrentUser();
}

class SupabaseDeviceTokenService implements DeviceTokenService {
  SupabaseDeviceTokenService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;
  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;

  String get _userId {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthError(message: 'You must be logged in.');
    return uid;
  }

  @override
  Future<void> registerToken({
    required String fcmToken,
    String? deviceId,
    String? appVersion,
  }) async {
    final uid = _userId;
    try {
      await _client.from('user_device_tokens').upsert(
        {
          'user_id': uid,
          'fcm_token': fcmToken,
          'platform': 'android',
          'device_id': deviceId,
          'app_version': appVersion,
          'is_active': true,
          'last_seen_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,fcm_token',
      );
    } on PostgrestException catch (e) {
      AppLogger.error('Device token register failed: ${e.message}');
      throw DataError(message: 'Could not register for notifications: ${e.message}');
    }
  }

  @override
  Future<void> deactivateToken(String fcmToken) async {
    final uid = _userId;
    try {
      await _client
          .from('user_device_tokens')
          .update({'is_active': false})
          .eq('user_id', uid)
          .eq('fcm_token', fcmToken);
    } on PostgrestException catch (e) {
      // Best-effort — a failed deactivate on logout should never block
      // sign-out itself.
      AppLogger.warning('Device token deactivate failed: ${e.message}');
    }
  }

  @override
  Future<void> deactivateAllTokensForCurrentUser() async {
    final uid = _userId;
    try {
      await _client.from('user_device_tokens').update({'is_active': false}).eq('user_id', uid);
    } on PostgrestException catch (e) {
      AppLogger.warning('Device token bulk-deactivate failed: ${e.message}');
    }
  }
}
