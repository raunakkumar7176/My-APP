import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_notification.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/push_notification_service.dart' show SystemPermissionStatus;
import '../group/data/notification_repository.dart';
import '../group/data/group_repository.dart';
import 'data/notification_feed_repository.dart';
import 'state/notification_deep_link_handler.dart';
import 'state/notification_feed_controller.dart';
import 'widgets/notification_tile.dart';

/// Global notification center. Shows ALL of the caller's notifications
/// across all groups in a unified chronological feed with:
/// - All / Unread tabs
/// - Paginated keyset loading
/// - Mark all read
/// - Per-notification tap to navigate (deep link)
/// - Empty / error / loading states
/// - Pull-to-refresh
class NotificationsHubScreen extends StatefulWidget {
  const NotificationsHubScreen({
    this.feedRepository,
    this.groupRepository,
    this.notificationRepository,
    super.key,
  });

  final NotificationFeedRepository? feedRepository;
  final GroupRepository? groupRepository;
  final NotificationRepository? notificationRepository;

  @override
  State<NotificationsHubScreen> createState() => _NotificationsHubScreenState();
}

class _NotificationsHubScreenState extends State<NotificationsHubScreen>
    with SingleTickerProviderStateMixin {
  late final NotificationFeedController _feedController;
  late final TabController _tabController;
  bool _ownsFeed = false;
  NotificationBroadCategory? _categoryFilter;
  bool _notificationsDisabled = false;
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _feedController = NotificationFeedController(feed: widget.feedRepository);
    _ownsFeed = true;
    _feedController.addListener(_onChanged);
    _feedController.load();
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    final granted = await PermissionService.hasNotificationPermission();
    if (mounted) setState(() => _notificationsDisabled = !granted);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _feedController.removeListener(_onChanged);
    if (_ownsFeed) _feedController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  List<AppNotification> get _filteredItems {
    var items = _tabController.index == 0
        ? _feedController.items
        : _feedController.items.where((n) => !n.isRead).toList();
    final category = _categoryFilter;
    if (category != null) {
      items = items.where((n) => n.parsedCategory.broadCategory == category).toList();
    }
    return items;
  }

  Future<void> _markAllRead() async {
    final ok = await _feedController.markAllRead();
    if (!mounted) return;
    if (!ok) {
      _snack(_feedController.error ?? 'Could not mark all read.', error: true);
    }
  }

  Future<void> _onNotificationTap(AppNotification n) async {
    // Mark read first.
    if (!n.isRead) {
      final ok = await _feedController.markRead(n.id);
      if (!mounted) return;
      if (!ok) {
        _snack(
          _feedController.error ?? 'Could not mark notification read.',
          error: true,
        );
      }
    }
    // Navigate via deep link handler.
    if (!mounted) return;
    NotificationDeepLinkHandler.handleTap(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreadCount = _feedController.unreadCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          unreadCount > 0
              ? 'Notifications ($unreadCount unread)'
              : 'Notifications',
        ),
        actions: [
          if (_feedController.hasUnread)
            IconButton(
              key: const Key('mark_all_read'),
              tooltip: 'Mark all read',
              icon: const Icon(Icons.done_all),
              onPressed: _feedController.isBusy ? null : _markAllRead,
            ),
          IconButton(
            key: const Key('notification_settings_button'),
            tooltip: 'Notification settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/notification-settings'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          tabs: [
            const Tab(text: 'All'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unread'),
                  if (unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('$unreadCount'),
                      backgroundColor: theme.colorScheme.error,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_notificationsDisabled && !_bannerDismissed) _permissionBanner(),
          _categoryFilterChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _permissionBanner() {
    return MaterialBanner(
      key: const Key('notification_permission_banner'),
      backgroundColor: Colors.amber.withValues(alpha: 0.15),
      leading: const Text('🔔', style: TextStyle(fontSize: 20)),
      content: const Text('Enable phone notifications to never miss a live test'),
      actions: [
        TextButton(
          key: const Key('notification_permission_turn_on'),
          onPressed: () async {
            final granted = await PermissionService.requestNotificationPermission(context);
            if (mounted) {
              setState(() => _notificationsDisabled = granted != SystemPermissionStatus.granted);
            }
          },
          child: const Text('Turn On'),
        ),
        TextButton(
          onPressed: () => setState(() => _bannerDismissed = true),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  Widget _categoryFilterChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: const Key('notif_filter_all'),
              label: const Text('All'),
              selected: _categoryFilter == null,
              onSelected: (_) => setState(() => _categoryFilter = null),
            ),
          ),
          for (final c in NotificationBroadCategory.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('notif_filter_${c.name}'),
                label: Text(c.label),
                selected: _categoryFilter == c,
                onSelected: (_) => setState(() => _categoryFilter = c),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_feedController.isLoading && !_feedController.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_feedController.error != null && _feedController.isEmpty) {
      return _errorWidget();
    }

    final items = _filteredItems;

    if (items.isEmpty) {
      return _emptyWidget();
    }

    return RefreshIndicator(
      onRefresh: _feedController.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length + (_feedController.hasOlder ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == items.length) {
            return _loadOlderButton();
          }
          final n = items[index];
          return Column(
            children: [
              NotificationTile(
                notification: n,
                isActing: _feedController.actingId == n.id,
                onActionTap: _feedController.isBusy ? null : () => _onNotificationTap(n),
                onTap: _feedController.isBusy
                    ? null
                    : () => _onNotificationTap(n),
              ),
              const Divider(height: 1, indent: 56),
            ],
          );
        },
      ),
    );
  }

  Widget _loadOlderButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Center(
        child: _feedController.olderLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                key: const Key('load_older_notifications'),
                onPressed: _feedController.loadOlder,
                child: const Text('Load older'),
              ),
      ),
    );
  }

  Widget _errorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _feedController.error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('notifications_retry'),
              onPressed: _feedController.load,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyWidget() {
    final isUnreadTab = _tabController.index == 1;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUnreadTab
                  ? Icons.mark_email_read_outlined
                  : Icons.notifications_none,
              size: 56,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              isUnreadTab ? 'All caught up!' : 'No notifications yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              isUnreadTab
                  ? 'You have no unread notifications.'
                  : 'Join or create a group to start receiving notifications.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
