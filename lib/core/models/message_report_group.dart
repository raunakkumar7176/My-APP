/// One message's aggregated reports from `public.group_message_reports`
/// (migration 0120), joined with the reported message's current state.
/// Read access is admin/owner-only server-side (RLS "admins view message
/// reports") — this model is purely a display aggregation; the client
/// never decides who gets to see one of these.
final class MessageReportGroup {
  const MessageReportGroup({
    required this.messageId,
    required this.groupId,
    required this.messageBody,
    required this.messageDeleted,
    required this.messageSenderId,
    required this.reasonCounts,
    required this.reporterCount,
    required this.latestReportAt,
  });

  final String messageId;
  final String groupId;

  /// Null if the message row itself is gone (shouldn't normally happen —
  /// `group_message_reports.message_id` cascades on delete — kept nullable
  /// defensively rather than assuming the join always resolves).
  final String? messageBody;
  final bool messageDeleted;
  final String? messageSenderId;

  /// `reason -> count`, e.g. `{'spam': 2, 'abuse': 1}`.
  final Map<String, int> reasonCounts;

  /// Distinct reporters, not total report rows (a user can only report a
  /// message once — server-enforced, 0120 — so these are equal in practice).
  final int reporterCount;
  final DateTime latestReportAt;

  /// The most common reason, for a compact summary label.
  String get topReason {
    if (reasonCounts.isEmpty) return 'other';
    final sorted = reasonCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  int get totalReports => reasonCounts.values.fold(0, (a, b) => a + b);
}
