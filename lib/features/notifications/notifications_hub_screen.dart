import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_error.dart';
import '../../core/models/group.dart';
import '../group/data/group_repository.dart';
import '../group/data/notification_repository.dart';

/// Notification center. Notifications are stored per-group only (see
/// [NotificationRepository]) — there is no unified feed table — so this
/// screen lists the caller's own groups (a small, bounded list) with each
/// group's unread count, and hands off to the existing per-group
/// notification screen for the actual read/unread list.
class NotificationsHubScreen extends StatefulWidget {
  const NotificationsHubScreen({super.key, this.groupRepository, this.notificationRepository});

  final GroupRepository? groupRepository;
  final NotificationRepository? notificationRepository;

  @override
  State<NotificationsHubScreen> createState() => _NotificationsHubScreenState();
}

class _GroupUnread {
  const _GroupUnread(this.group, this.unread);
  final Group group;
  final int unread;
}

class _NotificationsHubScreenState extends State<NotificationsHubScreen> {
  late final GroupRepository _groups;
  late final NotificationRepository _notifications;

  bool _loading = true;
  String? _error;
  List<_GroupUnread> _items = [];

  @override
  void initState() {
    super.initState();
    _groups = widget.groupRepository ?? const SupabaseGroupRepository();
    _notifications = widget.notificationRepository ?? const SupabaseNotificationRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final myGroups = await _groups.myGroups();
      final items = <_GroupUnread>[];
      for (final g in myGroups) {
        final unread = await _notifications.unreadCount(g.id);
        items.add(_GroupUnread(g, unread));
      }
      items.sort((a, b) => b.unread.compareTo(a.unread));
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load notifications. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none,
                size: 48,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              const Text('No notifications'),
              const SizedBox(height: 4),
              Text(
                'Join or create a group to start receiving notifications.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final item = _items[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(Icons.groups, color: Theme.of(context).colorScheme.primary),
              ),
              title: Text(item.group.name),
              subtitle: Text('${item.group.memberCount} member${item.group.memberCount == 1 ? '' : 's'}'),
              trailing: item.unread > 0
                  ? Badge(label: Text('${item.unread}'))
                  : const Icon(Icons.chevron_right),
              onTap: () async {
                await context.push('/groups/${item.group.id}/notifications');
                if (mounted) _load();
              },
            ),
          );
        },
      ),
    );
  }
}
