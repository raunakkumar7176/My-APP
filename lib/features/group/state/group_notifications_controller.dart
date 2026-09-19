import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/services/auth_service.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../data/notification_repository.dart';
import '../domain/group_errors.dart';

/// G16 — one group's notification inbox for the caller: newest first,
/// finite pages, live `read_at` read state, group mute. Reads only on load
/// (`groupForMember` membership guard, one page, one unread count, one mute
/// row); the only mutations are the explicit read-state / mute actions,
/// each single-flight and followed by a server re-read. Nothing here calls
/// an RPC that generates, scores or queues anything.
class GroupNotificationsController extends DisposableNotifier {
  GroupNotificationsController({
    required this.groupId,
    NotificationRepository? notifications,
    GroupRepository? groups,
    String? currentUserId,
  }) : _notifications = notifications ?? const SupabaseNotificationRepository(),
       _groups = groups ?? const SupabaseGroupRepository(),
       _currentUserId = currentUserId ?? AuthService.currentUser?.id;

  final String groupId;
  final NotificationRepository _notifications;
  final GroupRepository _groups;
  final String? _currentUserId;

  List<AppNotification> _items = const [];
  int _unread = 0;
  bool _muted = false;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _olderLoading = false;
  bool _hasOlder = false;
  bool _busy = false;
  bool _accessDenied = false;
  String? _error;
  String? _actingId;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _unread;
  bool get isMuted => _muted;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  bool get olderLoading => _olderLoading;
  bool get hasOlder => _hasOlder;
  bool get isBusy => _busy;
  bool get accessDenied => _accessDenied;
  String? get error => _error;
  String? get currentUserId => _currentUserId;

  /// The notification currently being marked (row-level spinner).
  String? get actingId => _actingId;
  bool get isEmpty => _loadedOnce && !_loading && _items.isEmpty;
  bool get hasUnread => _unread > 0;

  /// Membership first (the hub's rule: a non-member never sees a group
  /// screen, even though their own old rows stay readable under RLS), then
  /// one page + unread count + mute state. Single-flight.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final group = await _groups.groupForMember(groupId);
      if (group == null) {
        _accessDenied = true;
        _items = const [];
        _unread = 0;
      } else {
        _accessDenied = false;
        final page = await _notifications.forGroup(groupId);
        _items = page;
        _hasOlder = page.length >= notificationPageSize;
        _unread = await _notifications.unreadCount(groupId);
        _muted = await _notifications.isMuted(groupId);
      }
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Group notifications load failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.notification,
      );
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  /// Next page strictly before the oldest loaded row. Single-flight; a short
  /// page ends pagination.
  Future<void> loadOlder() async {
    if (_olderLoading || !_hasOlder || _items.isEmpty || _accessDenied) return;
    _olderLoading = true;
    notifyListeners();
    try {
      final older = await _notifications.forGroup(
        groupId,
        before: _items.last.createdAt,
      );
      final known = _items.map((n) => n.id).toSet();
      _items = [
        ..._items,
        for (final n in older)
          if (!known.contains(n.id)) n,
      ];
      _hasOlder = older.length >= notificationPageSize;
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Older notifications failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.notification,
      );
    }
    _olderLoading = false;
    notifyListeners();
  }

  /// Marks one own row read (live `read_at`). No-op for an already-read row.
  Future<bool> markRead(String notificationId) async {
    if (_accessDenied) return false;
    final target = _items.where((n) => n.id == notificationId).firstOrNull;
    if (target == null || target.isRead) return true;
    _actingId = notificationId;
    return _run(() => _notifications.markRead(notificationId));
  }

  /// Marks every own unread row of this group read.
  Future<bool> markAllRead() async {
    if (_accessDenied) return false;
    if (_unread == 0 && _items.every((n) => n.isRead)) return true;
    return _run(() => _notifications.markAllRead(groupId));
  }

  /// Toggles the caller's `group_mutes` row for this group. Existing
  /// semantics preserved: muted ⇒ `fn_notify_group` skips the caller.
  Future<bool> setMuted(bool muted) async {
    if (_accessDenied) return false;
    if (muted == _muted) return true;
    return _run(() => _notifications.setMuted(groupId, muted: muted));
  }

  /// Single-flight mutation; the page, count and mute state are re-read from
  /// the server afterwards whatever the outcome (no optimistic state).
  Future<bool> _run(Future<void> Function() body) async {
    if (_busy || _accessDenied) {
      _actingId = null;
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    var ok = false;
    try {
      await body();
      ok = true;
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Notification mutation failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.notification,
      );
    } finally {
      _busy = false;
      _actingId = null;
      notifyListeners();
    }
    // Re-read clears the error field; keep the mutation's message visible.
    final failure = _error;
    await load();
    if (failure != null && _error == null) {
      _error = failure;
      notifyListeners();
    }
    return ok;
  }
}
