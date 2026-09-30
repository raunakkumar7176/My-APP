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

  /// Per-category "template": every notification TYPE gets its own icon so
  /// a test-starting alert, a group announcement and a new-follower ping
  /// are visually distinct at a glance, not just generically bucketed.
  /// The pill/border color still follows the broad bucket (so the 6 filter
  /// chips stay visually consistent), except results/leaderboard which
  /// keep a green trophy treatment even though they file under "Tests".
  static const _urgentRed = Color(0xFFDC2626);

  static Color _iconColorFor(NotificationCategory category, NotificationBroadCategory broad) {
    if (category == NotificationCategory.resultsAvailable ||
        category == NotificationCategory.leaderboardUpdated) {
      return const Color(0xFF2B9B62); // green trophy
    }
    if (category == NotificationCategory.streakAtRisk) {
      return _urgentRed;
    }
    return _pillColorFor(broad);
  }

  static IconData _iconFor(NotificationCategory category, NotificationBroadCategory broad) {
    switch (category) {
      case NotificationCategory.resultsAvailable:
      case NotificationCategory.leaderboardUpdated:
        return Icons.emoji_events_outlined;
      case NotificationCategory.testInvitation:
        return Icons.sports_kabaddi_outlined; // "challenge" swords-style
      case NotificationCategory.testLive:
      case NotificationCategory.testStarted:
      case NotificationCategory.testStartingSoon:
        return Icons.timer_outlined;
      case NotificationCategory.testEnded:
      case NotificationCategory.testCompleted:
        return Icons.stop_circle_outlined;
      case NotificationCategory.testReminder:
      case NotificationCategory.testScheduled:
      case NotificationCategory.groupTestAssigned:
      case NotificationCategory.groupTestReminder:
        return Icons.assignment_outlined;
      case NotificationCategory.groupJoin:
      case NotificationCategory.groupJoinRequest:
      case NotificationCategory.joinAccepted:
      case NotificationCategory.joinRejected:
        return Icons.person_add_outlined;
      case NotificationCategory.groupAnnouncement:
        return Icons.campaign_outlined;
      case NotificationCategory.groupMessage:
        return Icons.chat_bubble_outline;
      case NotificationCategory.roleChanged:
      case NotificationCategory.memberRemoved:
        return Icons.admin_panel_settings_outlined;
      case NotificationCategory.routineReminder:
      case NotificationCategory.routineDue:
      case NotificationCategory.routineMissed:
      case NotificationCategory.routineCompleted:
        return Icons.menu_book_outlined;
      case NotificationCategory.streakMilestone:
        return Icons.local_fire_department_outlined;
      case NotificationCategory.streakAtRisk:
        return Icons.local_fire_department;
      case NotificationCategory.reportReady:
        return Icons.bar_chart_outlined;
      case NotificationCategory.levelUp:
        return Icons.military_tech_outlined;
      case NotificationCategory.newFollower:
        return Icons.person_outline;
      case NotificationCategory.contentReviewResult:
        return Icons.fact_check_outlined;
      case NotificationCategory.systemNotification:
      case NotificationCategory.unknown:
        return Icons.info_outline;
    }
  }

  static Color _pillColorFor(NotificationBroadCategory broad) => switch (broad) {
    NotificationBroadCategory.tests => const Color(0xFF2457D6),
    NotificationBroadCategory.routine => const Color(0xFFE59A2F),
    NotificationBroadCategory.groups => const Color(0xFF0F9F92),
    NotificationBroadCategory.performance => const Color(0xFF2B9B62),
    NotificationBroadCategory.social => const Color(0xFF8B5CF6),
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
    // Urgent categories (a live/imminent test, an at-risk streak) get a
    // stronger filled-card treatment instead of the standard subtle tint,
    // so they stand out from routine background chatter even when read.
    final urgent = category.isUrgent;

    return Container(
      key: Key('notification_${notification.id}'),
      decoration: BoxDecoration(
        color: urgent
            ? iconColor.withValues(alpha: unread ? 0.1 : 0.05)
            : (unread ? pillColor.withValues(alpha: 0.05) : null),
        border: Border(
          left: BorderSide(
            color: urgent
                ? iconColor
                : (unread ? theme.colorScheme.primary : Colors.transparent),
            width: urgent ? 4 : 3,
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
