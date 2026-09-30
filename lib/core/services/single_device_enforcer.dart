import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import 'auth_service.dart';
import 'device_identity.dart';
import 'supabase_service.dart';

/// One user_id, one active device. Two layers:
///  - [registerThisDevice] — called right after login — tells the server
///    "I'm the active device now", which force-logs-out whichever device
///    was previously active (an instant push to that device, handled by
///    [handleForceLogoutPush] on its end).
///  - [checkStillActive] — called on every app resume/cold-start — is the
///    AUTHORITATIVE check: even if this device never received a push (it
///    was killed, offline, etc.), the next time it's opened this confirms
///    whether it's still the active device and signs out if not.
final class SingleDeviceEnforcer {
  SingleDeviceEnforcer._();

  static const _messageKey = 'force_logout_message';

  /// Call once, right after a successful login (mirrors where
  /// `PushNotificationService.registerCurrentDevice` is already called
  /// from `AuthService.initialize`'s auth-state listener). Best-effort —
  /// a failure here must never block login.
  static Future<void> registerThisDevice() async {
    try {
      final deviceId = await DeviceIdentity.current();
      await SupabaseService.client.rpc(
        'rpc_register_active_device',
        params: {'p_device_id': deviceId},
      );
    } catch (e) {
      AppLogger.warning('registerThisDevice failed: $e');
    }
  }

  /// Call on every app resume/cold-start while a session exists. Returns
  /// normally either way; if this device has been superseded, it signs
  /// itself out and stashes the message the login screen shows once.
  static Future<void> checkStillActive() async {
    if (!AuthService.isAuthenticated) return;
    try {
      final deviceId = await DeviceIdentity.current();
      final stillActive = await SupabaseService.client.rpc(
        'rpc_check_active_device',
        params: {'p_device_id': deviceId},
      ) as bool?;
      if (stillActive == false) {
        await _signOutWithMessage(
          'Is account se ek naye device par login hua hai. Suraksha ke liye ye device automatically logout ho gaya hai.',
        );
      }
    } catch (e) {
      AppLogger.warning('checkStillActive failed: $e');
    }
  }

  /// Called from the foreground FCM handler when a FORCE_LOGOUT push
  /// arrives while the app is open. Only acts if the push is actually
  /// targeted at THIS device (defense in depth — the server already scopes
  /// delivery to the one device's token, this is a second check).
  static Future<void> handleForceLogoutPush(Map<String, dynamic> data) async {
    final targetDeviceId = data['target_device_id'] as String?;
    if (targetDeviceId == null || targetDeviceId.isEmpty) return;
    final myDeviceId = await DeviceIdentity.current();
    if (targetDeviceId != myDeviceId) return;

    await _signOutWithMessage(
      'Is account se ek naye device par login hua hai. Suraksha ke liye ye device automatically logout ho gaya hai.',
    );
  }

  static Future<void> _signOutWithMessage(String message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_messageKey, message);
    } catch (_) {
      // Non-fatal — sign-out still proceeds even if the message can't be
      // stashed; the user just won't see the "why" banner.
    }
    try {
      await AuthService.signOut();
    } catch (e) {
      AppLogger.warning('Forced sign-out failed: $e');
    }
  }

  /// Read-once: the login screen calls this on build to show (and clear)
  /// a pending force-logout explanation, or null if there isn't one.
  static Future<String?> takePendingMessage() async {
    final prefs = await SharedPreferences.getInstance();
    final message = prefs.getString(_messageKey);
    if (message != null) await prefs.remove(_messageKey);
    return message;
  }
}
