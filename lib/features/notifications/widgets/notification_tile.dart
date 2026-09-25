import 'package:flutter/material.dart';

import '../../../core/models/app_notification.dart';

/// Consistent notification tile used in both the global feed and per-group
/// notification screens. Shows icon, title, body, time, unread indicator,
/// and category chip.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.notification,
    this.onTap,
    this.onDismiss,
    this.isActing = false,
    this.showGroup = false,
    super.key,
  });

  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final bool isActing;
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    final theme = Theme.of(context);

    return ListTile(
      key: Key('notification_${notification.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: _CategoryIcon(
        category: notification.parsedCategory,
        unread: unread,
      ),
      title: Text(
        notification.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notification.body.isNotEmpty)
            Text(
              notification.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 2),
          Text(
            _formatTime(notification.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
      isThreeLine: notification.body.isNotEmpty,
      trailing: isActing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : unread
              ? Icon(
                  Icons.circle,
                  size: 10,
                  color: theme.colorScheme.primary,
                  key: Key('unread_dot_${notification.id}'),
                )
              : null,
      onTap: onTap,
    );
  }

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Category-specific icon with appropriate color.
class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.category, required this.unread});

  final NotificationCategory category;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = unread
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return CircleAvatar(
      radius: 18,
      backgroundColor: unread
          ? theme.colorScheme.primary.withValues(alpha: 0.1)
          : theme.colorScheme.surfaceContainerHighest,
      child: Icon(_icon, size: 18, color: color),
    );
  }

  IconData get _icon => switch (category) {
    NotificationCategory.groupMessage => Icons.chat_bubble_outline,
    NotificationCategory.groupAnnouncement => Icons.campaign_outlined,
    NotificationCategory.groupJoin => Icons.person_add_alt_1_outlined,
    NotificationCategory.testReminder => Icons.alarm_outlined,
    NotificationCategory.testLive => Icons.play_circle_outline,
    NotificationCategory.testCompleted => Icons.check_circle_outline,
    NotificationCategory.testInvitation => Icons.quiz_outlined,
    NotificationCategory.testScheduled => Icons.event_outlined,
    NotificationCategory.testStartingSoon => Icons.timer_outlined,
    NotificationCategory.testStarted => Icons.play_arrow_outlined,
    NotificationCategory.testEnded => Icons.stop_circle_outlined,
    NotificationCategory.resultsAvailable => Icons.assessment_outlined,
    NotificationCategory.leaderboardUpdated => Icons.leaderboard_outlined,
    NotificationCategory.routineReminder => Icons.schedule_outlined,
    NotificationCategory.routineDue => Icons.event_repeat_outlined,
    NotificationCategory.routineMissed => Icons.event_busy_outlined,
    NotificationCategory.routineCompleted => Icons.task_alt_outlined,
    NotificationCategory.streakMilestone => Icons.local_fire_department_outlined,
    NotificationCategory.groupTestAssigned => Icons.assignment_outlined,
    NotificationCategory.groupTestReminder => Icons.notification_important_outlined,
    NotificationCategory.contentReviewResult => Icons.rate_review_outlined,
    NotificationCategory.reportReady => Icons.insights_outlined,
    NotificationCategory.systemNotification => Icons.info_outline,
    NotificationCategory.groupJoinRequest => Icons.how_to_vote_outlined,
    NotificationCategory.joinAccepted => Icons.check_circle_outline,
    NotificationCategory.joinRejected => Icons.cancel_outlined,
    NotificationCategory.roleChanged => Icons.admin_panel_settings_outlined,
    NotificationCategory.memberRemoved => Icons.person_remove_outlined,
    NotificationCategory.unknown => Icons.notifications_none,
  };
}
