import 'package:flutter/material.dart';

import '../../../core/models/app_notification.dart';

/// Consistent notification card used in both the global feed and per-group
/// notification screens. Shows a category-colored leading icon, category tag
/// + relative time, bold title, short body, an optional action-preview
/// button, and an unread left-border + tinted background.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.notification,
    this.onTap,
    this.onDismiss,
    this.onActionTap,
    this.isActing = false,
    this.showGroup = false,
    super.key,
  });

  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  /// Called when the action-preview button (e.g. "Start Test") is tapped.
  final VoidCallback? onActionTap;
  final bool isActing;
  final bool showGroup;

  static const _navyInk = Color(0xFF172033);

  /// Filter/pill color follows the broad bucket (Tests/Routine/Groups/
  /// System), but the leading ICON keeps a finer distinction the task's
  /// design calls for: results/leaderboard get a green trophy even though
  /// they still file under the "Tests" filter chip.
  static Color _iconColorFor(NotificationCategory category, NotificationBroadCategory broad) {
    if (category == NotificationCategory.resultsAvailable ||
        category == NotificationCategory.leaderboardUpdated) {
      return const Color(0xFF2B9B62); // green trophy
    }
    return _pillColorFor(broad);
  }

  static IconData _iconFor(NotificationCategory category, NotificationBroadCategory broad) {
    if (category == NotificationCategory.resultsAvailable ||
        category == NotificationCategory.leaderboardUpdated) {
      return Icons.emoji_events_outlined;
    }
    return switch (broad) {
      NotificationBroadCategory.tests => Icons.assignment_outlined,
      NotificationBroadCategory.routine => Icons.schedule_outlined,
      NotificationBroadCategory.groups => Icons.groups_outlined,
      NotificationBroadCategory.system => Icons.info_outline,
    };
  }

  static Color _pillColorFor(NotificationBroadCategory broad) => switch (broad) {
    NotificationBroadCategory.tests => const Color(0xFF2457D6),
    NotificationBroadCategory.routine => const Color(0xFFE59A2F),
    NotificationBroadCategory.groups => const Color(0xFF0F9F92),
    NotificationBroadCategory.system => const Color(0xFF64748B),
  };

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    final theme = Theme.of(context);
    final category = notification.parsedCategory;
    final broad = category.broadCategory;
    final iconColor = _iconColorFor(category, broad);
    final pillColor = _pillColorFor(broad);
    final actionLabel = category.actionLabel;

    return Container(
      key: Key('notification_${notification.id}'),
      decoration: BoxDecoration(
        color: unread ? pillColor.withValues(alpha: 0.05) : null,
        border: Border(
          left: BorderSide(
            color: unread ? theme.colorScheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: iconColor.withValues(alpha: 0.12),
          child: Icon(_iconFor(category, broad), size: 18, color: iconColor),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: pillColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    broad.label,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: pillColor),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(notification.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              notification.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, color: _navyInk),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notification.body.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                notification.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (actionLabel != null && onActionTap != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: Key('notification_action_${notification.id}'),
                onPressed: onActionTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: iconColor,
                  side: BorderSide(color: iconColor),
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text('$actionLabel ➔'),
              ),
            ],
          ],
        ),
        isThreeLine: notification.body.isNotEmpty || actionLabel != null,
        trailing: isActing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
