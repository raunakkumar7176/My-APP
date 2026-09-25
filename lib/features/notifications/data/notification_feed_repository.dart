import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';

/// Page size for the global notification feed. Kept finite to avoid
/// unbounded downloads.
const notificationFeedPageSize = 30;

/// Global notification feed repository — fetches ALL of the caller's
/// notifications across all groups, newest first. Uses keyset pagination
/// on `created_at` for stable, efficient paging. RLS ensures only own
/// rows are returned.
abstract interface class NotificationFeedRepository {
  /// Page of the caller's notifications, newest first.
  Future<List<AppNotification>> feed({
    int limit = notificationFeedPageSize,
    DateTime? before,
  });

  /// Total unread count across all groups (server-side count, not row fetch).
  Future<int> totalUnreadCount();

  /// Unread count for a specific notification category.
  Future<int> unreadCountByCategory(NotificationCategory category);

  /// Mark one own notification as read. Idempotent.
  Future<bool> markRead(String notificationId);

  /// Mark all own notifications as read. Returns count of rows changed.
  Future<int> markAllRead();

  /// Mark all own unread notifications of a specific category as read.
  Future<int> markAllReadForCategory(NotificationCategory category);

  /// Delete/dismiss a single own notification. Idempotent.
  Future<bool> dismiss(String notificationId);

  /// Read a single notification by ID (for deep-link validation).
  Future<AppNotification?> getById(String notificationId);
}

final class SupabaseNotificationFeedRepository
    implements NotificationFeedRepository {
  const SupabaseNotificationFeedRepository();

  static SupabaseClient get _client => SupabaseService.client;
  static String? get _uid => AuthService.currentUser?.id;

  static const _columns =
      'id, user_id, category, title, body, data, read_at, created_at, priority, dedupe_key';

  static String _requireUid() {
    final uid = _uid;
    if (uid == null) throw const AuthError(message: 'Please sign in again.');
    return uid;
  }

  @override
  Future<List<AppNotification>> feed({
    int limit = notificationFeedPageSize,
    DateTime? before,
  }) =>
      _guard(() async {
        final uid = _requireUid();
        var query = _client
            .from('notifications')
            .select(_columns)
            .eq('user_id', uid);
        if (before != null) {
          query = query.lt('created_at', before.toUtc().toIso8601String());
        }
        final rows = await query
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .limit(limit);
        AppLogger.rpcShape('notifications.feed', rows);
        return [
          for (final r in rows as List)
            AppNotification.fromJson(r as Map<String, dynamic>),
        ];
      });

  @override
  Future<int> totalUnreadCount() => _guard(() async {
        final uid = _requireUid();
        return _client
            .from('notifications')
            .count(CountOption.exact)
            .eq('user_id', uid)
            .isFilter('read_at', null);
      });

  @override
  Future<int> unreadCountByCategory(NotificationCategory category) =>
      _guard(() async {
        final uid = _requireUid();
        return _client
            .from('notifications')
            .count(CountOption.exact)
            .eq('user_id', uid)
            .eq('category', category.label)
            .isFilter('read_at', null);
      });

  @override
  Future<bool> markRead(String notificationId) => _guard(() async {
        final uid = _requireUid();
        final updated = await _client
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', notificationId)
            .eq('user_id', uid)
            .isFilter('read_at', null)
            .select('id');
        return (updated as List).isNotEmpty;
      });

  @override
  Future<int> markAllRead() => _guard(() async {
        final uid = _requireUid();
        final updated = await _client
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', uid)
            .isFilter('read_at', null)
            .select('id');
        return (updated as List).length;
      });

  @override
  Future<int> markAllReadForCategory(NotificationCategory category) =>
      _guard(() async {
        final uid = _requireUid();
        final updated = await _client
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('user_id', uid)
            .eq('category', category.label)
            .isFilter('read_at', null)
            .select('id');
        return (updated as List).length;
      });

  @override
  Future<bool> dismiss(String notificationId) => _guard(() async {
        final uid = _requireUid();
        final deleted = await _client
            .from('notifications')
            .delete()
            .eq('id', notificationId)
            .eq('user_id', uid)
            .select('id');
        return (deleted as List).isNotEmpty;
      });

  @override
  Future<AppNotification?> getById(String notificationId) => _guard(() async {
        final uid = _requireUid();
        final row = await _client
            .from('notifications')
            .select(_columns)
            .eq('id', notificationId)
            .eq('user_id', uid)
            .maybeSingle();
        if (row == null) return null;
        return AppNotification.fromJson(row);
      });

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'NotificationFeedRepository PostgrestException: ${e.code} ${e.message}',
      );
      throw DataError(message: 'Notification error: ${e.message}');
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error(
        'NotificationFeedRepository unexpected: $e',
        stackTrace: st,
      );
      throw DataError(message: 'Notification error: $e');
    }
  }
}
