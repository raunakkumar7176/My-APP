import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/app_notification.dart';
import '../../notifications/state/notification_deep_link_handler.dart';
import '../../test/widgets/test_formatters.dart';
import '../domain/group_notification_grouping.dart';
import '../state/group_notifications_controller.dart';

/// G16 — `/groups/:groupId/notifications`: the caller's own notifications
/// for one group (live `notifications` rows), newest first, finite pages,
/// read/unread distinction, mark one / mark all read, group mute switch.
/// Read-only apart from those explicit actions.
class GroupNotificationsScreen extends StatefulWidget {
  const GroupNotificationsScreen({
    required this.groupId,
    this.controller,
    super.key,
  });

  final String groupId;
  final GroupNotificationsController? controller;

  @override
  State<GroupNotificationsScreen> createState() =>
      _GroupNotificationsScreenState();
}

class _GroupNotificationsScreenState extends State<GroupNotificationsScreen> {
  late final GroupNotificationsController _c;
  late final bool _owns;

  /// Expanded message-group rows, keyed by the first message's id (stable
  /// across rebuilds as long as that notification stays in the list).
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c =
        widget.controller ??
        GroupNotificationsController(groupId: widget.groupId);
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _markAll() async {
    final ok = await _c.markAllRead();
    if (!mounted) return;
    if (!ok) _snack(_c.error ?? 'Could not mark notifications read.', error: true);
  }

  Future<void> _open(AppNotification n) async {
    // Reading is the mutation the user asked for by tapping; then follow the
    // payload to the existing screen for that entity (all inside this group).
    if (!n.isRead) {
      final ok = await _c.markRead(n.id);
      if (!ok && mounted) {
        _snack(_c.error ?? 'Could not mark that notification read.', error: true);
      }
    }
    // Follow the payload via deep link handler (validates path before navigation).
    if (!mounted || GoRouter.maybeOf(context) == null) return;
    NotificationDeepLinkHandler.handleTap(context, n);
  }

  Future<void> _toggleMute(bool muted) async {
    final ok = await _c.setMuted(muted);
    if (!mounted) return;
    if (!ok) _snack(_c.error ?? 'Could not update the mute setting.', error: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.hasLoaded && _c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_c.accessDenied) {
      return _message(
        icon: Icons.lock_outline,
        title: 'Group not available',
        body: 'This group does not exist, or you are not a member of it.',
      );
    }
    if (_c.error != null && _c.items.isEmpty) {
      return _message(
        icon: Icons.error_outline,
        title: 'Could not load notifications',
        body: _c.error!,
        action: FilledButton(
          key: const Key('notifications_retry'),
          onPressed: _c.load,
          child: const Text('Retry'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _c.hasUnread
              ? 'Notifications (${_c.unreadCount} unread)'
              : 'Notifications',
          key: const Key('notifications_title'),
        ),
        actions: [
          IconButton(
            key: const Key('mark_all_read'),
            tooltip: 'Mark all read',
            icon: const Icon(Icons.done_all),
            onPressed: _c.isBusy || !_c.hasUnread ? null : _markAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              key: const Key('mute_group_switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Mute this group'),
              subtitle: const Text(
                'No new notifications from this group while muted',
              ),
              value: _c.isMuted,
              onChanged: _c.isBusy ? null : _toggleMute,
            ),
            if (_c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _c.error!,
                  key: const Key('notifications_error'),
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            if (_c.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  key: const Key('notifications_empty'),
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    const Text('No notifications for this group yet.'),
                  ],
                ),
              ),
            ..._buildGrouped(context),
            if (_c.hasOlder)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OutlinedButton(
                  key: const Key('load_older_notifications'),
                  onPressed: _c.olderLoading ? null : _c.loadOlder,
                  child: _c.olderLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Load older'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGrouped(BuildContext context) {
    if (_c.items.isEmpty) return const [];
    final grouped = groupNotifications(_c.items);
    final widgets = <Widget>[];

    if (grouped.testNotifications.isNotEmpty) {
      widgets.add(_sectionHeader(context, 'Tests', key: 'section_tests'));
      for (final n in grouped.testNotifications) {
        widgets.add(_tile(context, n));
      }
    }

    for (final section in grouped.daySections) {
      widgets.add(
        _sectionHeader(
          context,
          section.label,
          key: 'section_day_${section.label}',
        ),
      );
      for (final row in section.rows) {
        widgets.add(switch (row) {
          SingleNotificationRow(notification: final n) => _tile(context, n),
          MessageGroupRow() => _messageGroupTile(context, row),
        });
      }
    }
    return widgets;
  }

  Widget _sectionHeader(BuildContext context, String label, {String? key}) {
    return Padding(
      key: key == null ? null : Key(key),
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _messageGroupTile(BuildContext context, MessageGroupRow group) {
    final groupKey = group.messages.first.id;
    final expanded = _expandedGroups.contains(groupKey);
    return Column(
      key: Key('message_group_$groupKey'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: Key('message_group_header_$groupKey'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.chat_bubble_outline,
            color: group.anyUnread
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          title: Text(
            group.label,
            style: TextStyle(
              fontWeight: group.anyUnread ? FontWeight.w600 : null,
            ),
          ),
          subtitle: Text(TestFormatters.dateTime(group.messages.first.createdAt)),
          trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() {
            if (expanded) {
              _expandedGroups.remove(groupKey);
            } else {
              _expandedGroups.add(groupKey);
            }
          }),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              children: [for (final n in group.messages) _tile(context, n)],
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, AppNotification n) {
    final unread = !n.isRead;
    final acting = _c.actingId == n.id;
    return ListTile(
      key: Key('notification_${n.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _icon(n),
        color: unread
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(
        n.title,
        style: TextStyle(fontWeight: unread ? FontWeight.w600 : null),
      ),
      subtitle: Text(
        '${n.body.isEmpty ? '' : '${n.body}\n'}${TestFormatters.dateTime(n.createdAt)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: n.body.isNotEmpty,
      trailing: acting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : unread
          ? Icon(
              Icons.circle,
              size: 10,
              color: Theme.of(context).colorScheme.primary,
              key: Key('unread_dot_${n.id}'),
            )
          : null,
      onTap: _c.isBusy ? null : () => _open(n),
    );
  }

  static IconData _icon(AppNotification n) {
    switch (n.type) {
      case 'group_message':
        return Icons.chat_bubble_outline;
      case 'group_announcement':
        return Icons.campaign_outlined;
      case 'group_join':
        return Icons.person_add_alt_1_outlined;
      case 'group_test':
        return Icons.quiz_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action ??
                  FilledButton(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/groups'),
                    child: const Text('Back to Groups'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
