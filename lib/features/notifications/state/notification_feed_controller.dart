import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_notification.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/notification_feed_repository.dart';

/// Global notification feed state: all notifications for the caller,
/// newest first, with unread count, pagination, and mark-read actions.
class NotificationFeedController extends DisposableNotifier {
  NotificationFeedController({
    NotificationFeedRepository? feed,
  }) : _feed = feed ?? const SupabaseNotificationFeedRepository();

  final NotificationFeedRepository _feed;

  List<AppNotification> _items = const [];
  int _unreadCount = 0;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _olderLoading = false;
  bool _hasOlder = false;
  bool _busy = false;
  String? _error;
  String? _actingId;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  bool get olderLoading => _olderLoading;
  bool get hasOlder => _hasOlder;
  bool get isBusy => _busy;
  String? get error => _error;
  String? get actingId => _actingId;
  bool get isEmpty => _loadedOnce && !_loading && _items.isEmpty;
  bool get hasUnread => _unreadCount > 0;

  /// Load the first page + unread count. Single-flight.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _feed.feed();
      _items = page;
      _hasOlder = page.length >= notificationFeedPageSize;
      _unreadCount = await _feed.totalUnreadCount();
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Notification feed load failed: $e', stackTrace: st);
      _error = 'Failed to load notifications.';
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  /// Next page strictly before the oldest loaded row. Single-flight.
  Future<void> loadOlder() async {
    if (_olderLoading || !_hasOlder || _items.isEmpty) return;
    _olderLoading = true;
    notifyListeners();
    try {
      final older = await _feed.feed(before: _items.last.createdAt);
      final known = _items.map((n) => n.id).toSet();
      _items = [
        ..._items,
        for (final n in older)
          if (!known.contains(n.id)) n,
      ];
      _hasOlder = older.length >= notificationFeedPageSize;
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Older notifications failed: $e', stackTrace: st);
      _error = 'Failed to load older notifications.';
    }
    _olderLoading = false;
    notifyListeners();
  }

  /// Mark one notification read. Idempotent. Updates unread count.
  Future<bool> markRead(String notificationId) async {
    final target = _items.where((n) => n.id == notificationId).firstOrNull;
    if (target == null || target.isRead) return true;
    _actingId = notificationId;
    return _mutation(() => _feed.markRead(notificationId));
  }

  /// Mark all notifications read. Updates unread count.
  Future<bool> markAllRead() async {
    if (_unreadCount == 0 && _items.every((n) => n.isRead)) return true;
    return _mutation(() => _feed.markAllRead());
  }

  /// Dismiss (delete) a notification. Idempotent.
  /// Unlike markRead/markAllRead, this returns false when RLS blocks the
  /// delete (another user's row or forged ID), so we bypass _mutation to
  /// preserve the return value from the repository.
  Future<bool> dismiss(String notificationId) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    var ok = false;
    try {
      ok = await _feed.dismiss(notificationId);
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Notification dismiss failed: $e', stackTrace: st);
      _error = 'Action failed. Please try again.';
    } finally {
      _busy = false;
      _actingId = null;
      notifyListeners();
    }
    final failure = _error;
    await load();
    if (failure != null && _error == null) {
      _error = failure;
      notifyListeners();
    }
    return ok;
  }

  /// Single-flight mutation; re-reads page + count afterwards.
  Future<bool> _mutation(Future<void> Function() body) async {
    if (_busy) {
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
      _error = 'Action failed. Please try again.';
    } finally {
      _busy = false;
      _actingId = null;
      notifyListeners();
    }
    final failure = _error;
    await load();
    if (failure != null && _error == null) {
      _error = failure;
      notifyListeners();
    }
    return ok;
  }
}
