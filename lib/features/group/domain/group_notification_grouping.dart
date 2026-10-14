import '../../../core/models/app_notification.dart';

/// Pure presentation grouping for [GroupNotificationsScreen] (R4.11 item 3):
/// test notifications pulled into their own section at the top regardless
/// of day, everything else bucketed by day (Today / Yesterday / date), and
/// consecutive runs of `group_message` notifications within a day collapsed
/// into one expandable row. No network/state here — testable in isolation.
sealed class NotificationRow {
  const NotificationRow();
}

final class SingleNotificationRow extends NotificationRow {
  const SingleNotificationRow(this.notification);
  final AppNotification notification;
}

/// A collapsed run of 2+ consecutive `group_message` notifications.
final class MessageGroupRow extends NotificationRow {
  const MessageGroupRow(this.messages) : assert(messages.length >= 2);
  final List<AppNotification> messages;
  String get label => '${messages.length} new messages';
  bool get anyUnread => messages.any((m) => !m.isRead);
}

class NotificationDaySection {
  const NotificationDaySection({required this.label, required this.rows});
  final String label;
  final List<NotificationRow> rows;
}

class GroupedNotifications {
  const GroupedNotifications({
    required this.testNotifications,
    required this.daySections,
  });
  final List<AppNotification> testNotifications;
  final List<NotificationDaySection> daySections;
  bool get isEmpty => testNotifications.isEmpty && daySections.isEmpty;
}

bool isTestNotification(AppNotification n) {
  if (n.type == 'group_test') return true;
  return n.parsedCategory.isTestRelated;
}

String dayLabel(DateTime createdAt, DateTime now) {
  final d = createdAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${d.day}/${d.month}/${d.year}';
}

/// [items] must be newest-first (the live load order); grouping and
/// collapsing both assume that order and preserve it.
GroupedNotifications groupNotifications(
  List<AppNotification> items, {
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final testNotifications = <AppNotification>[];
  final byDay = <String, List<AppNotification>>{};
  final dayOrder = <String>[];

  for (final n in items) {
    if (isTestNotification(n)) {
      testNotifications.add(n);
      continue;
    }
    final label = dayLabel(n.createdAt, effectiveNow);
    if (!byDay.containsKey(label)) {
      byDay[label] = [];
      dayOrder.add(label);
    }
    byDay[label]!.add(n);
  }

  final daySections = <NotificationDaySection>[
    for (final label in dayOrder)
      NotificationDaySection(label: label, rows: _collapseMessages(byDay[label]!)),
  ];

  return GroupedNotifications(
    testNotifications: testNotifications,
    daySections: daySections,
  );
}

List<NotificationRow> _collapseMessages(List<AppNotification> dayItems) {
  final rows = <NotificationRow>[];
  var i = 0;
  while (i < dayItems.length) {
    final n = dayItems[i];
    if (n.type == 'group_message') {
      final run = <AppNotification>[n];
      var j = i + 1;
      while (j < dayItems.length && dayItems[j].type == 'group_message') {
        run.add(dayItems[j]);
        j++;
      }
      rows.add(run.length >= 2 ? MessageGroupRow(run) : SingleNotificationRow(n));
      i = j;
    } else {
      rows.add(SingleNotificationRow(n));
      i++;
    }
  }
  return rows;
}
