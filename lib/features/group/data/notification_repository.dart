import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/group_errors.dart';

/// One page of group notifications (finite pagination, newest first).
const notificationPageSize = 30;

/// G16 — the client side of the EXISTING live notification infrastructure
/// (audited 2026-09-20): `public.notifications` (own rows: SELECT `own
/// notifications`, UPDATE `mark own read`; no INSERT/DELETE policy — rows
/// are written only by `fn_notify_group` from the group triggers) and
/// `public.group_mutes` (own rows, FOR ALL; honoured by `fn_notify_group`
/// and `fn_is_notification_allowed`). Read state is the live `read_at`
/// column; group scope is the live `data->>'group_id'` key. No mark-read RPC
/// exists live, so the direct own-row UPDATE is the sanctioned path.
///
/// Nothing here creates a table, an unread counter or a preference store;
/// the chat unread system (`message_reads` / `fn_get_group_unread_counts`)
/// is a separate live mechanism and is not touched.
abstract interface class NotificationRepository {
  /// The caller's notifications for one group, newest first, `limit` rows,
  /// optionally strictly before [before] (keyset on `created_at`). RLS
  /// returns the caller's own rows only.
  Future<List<AppNotification>> forGroup(
    String groupId, {
    int limit = notificationPageSize,
    DateTime? before,
  });

  /// `count(*)` of the caller's unread (`read_at IS NULL`) rows for one
  /// group — one HEAD request, never a row fetch.
  Future<int> unreadCount(String groupId);

  /// Sets `read_at = now()` on one own unread row. Idempotent: returns true
  /// when a row changed, false when it was already read or is not the
  /// caller's (RLS matches 0 rows — the server never says which).
  Future<bool> markRead(String notificationId);

  /// Sets `read_at = now()` on every own unread row of one group. Returns the
  /// number of rows changed.
  Future<int> markAllRead(String groupId);

  /// The caller's `group_mutes.is_muted` for the group (false when no row).
  Future<bool> isMuted(String groupId);

  /// Upserts the caller's `group_mutes` row (PK `(user_id, group_id)`).
  Future<void> setMuted(String groupId, {required bool muted});
}

final class SupabaseNotificationRepository implements NotificationRepository {
  const SupabaseNotificationRepository();

  static SupabaseClient get _client => SupabaseService.client;
  static String? get _uid => AuthService.currentUser?.id;

  static const _columns =
      'id, user_id, category, title, body, data, read_at, created_at, priority';

  static String _requireUid() {
    final uid = _uid;
    if (uid == null) throw const AuthError(message: 'Please sign in again.');
    return uid;
  }

  @override
  Future<List<AppNotification>> forGroup(
    String groupId, {
    int limit = notificationPageSize,
    DateTime? before,
  }) => _guard(() async {
    final uid = _requireUid();
    // `user_id = uid` is redundant with RLS but keeps the query on the live
    // `(user_id, created_at DESC)` index and never asks for more than own rows.
    var query = _client
        .from('notifications')
        .select(_columns)
        .eq('user_id', uid)
        .eq('data->>group_id', groupId);
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    AppLogger.rpcShape('notifications.select', rows);
    return [
      for (final r in rows as List)
        AppNotification.fromJson(r as Map<String, dynamic>),
    ];
  });

  @override
  Future<int> unreadCount(String groupId) => _guard(() async {
    final uid = _requireUid();
    return _client
        .from('notifications')
        .count(CountOption.exact)
        .eq('user_id', uid)
        .eq('data->>group_id', groupId)
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
  Future<int> markAllRead(String groupId) => _guard(() async {
    final uid = _requireUid();
    final updated = await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', uid)
        .eq('data->>group_id', groupId)
        .isFilter('read_at', null)
        .select('id');
    return (updated as List).length;
  });

  @override
  Future<bool> isMuted(String groupId) => _guard(() async {
    final uid = _requireUid();
    final row = await _client
        .from('group_mutes')
        .select('is_muted')
        .eq('user_id', uid)
        .eq('group_id', groupId)
        .maybeSingle();
    return row?['is_muted'] == true;
  });

  @override
  Future<void> setMuted(String groupId, {required bool muted}) =>
      _guard(() async {
        final uid = _requireUid();
        await _client.from('group_mutes').upsert({
          'user_id': uid,
          'group_id': groupId,
          'is_muted': muted,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,group_id');
      });

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      AppLogger.error(
        'NotificationRepository PostgrestException: ${e.code} ${e.message}',
      );
      throw DataError(
        message: GroupErrors.map(
          e.message,
          context: GroupErrorContext.notification,
        ),
      );
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('NotificationRepository unexpected: $e', stackTrace: st);
      throw DataError(
        message: GroupErrors.map(
          e.toString(),
          context: GroupErrorContext.notification,
        ),
      );
    }
  }
}
