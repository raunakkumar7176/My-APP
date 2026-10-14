/// One row from `fn_list_group_doubts` (migration 0122) — a top-level
/// doubt message plus its reply count and solved state, for the Group
/// Info Doubts section. Deliberately not a [GroupMessage]: the RPC
/// returns a flattened, pre-joined shape (sender name, reply count) that
/// a raw `group_messages` row doesn't carry, same reasoning as
/// `MessageReportGroup`.
final class GroupDoubtSummary {
  const GroupDoubtSummary({
    required this.id,
    required this.body,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
    required this.replyCount,
    required this.doubtSolved,
    this.solvedReplyId,
    this.solvedAt,
  });

  final String id;
  final String body;
  final String senderId;
  final String senderName;
  final DateTime createdAt;
  final int replyCount;
  final bool doubtSolved;
  final String? solvedReplyId;
  final DateTime? solvedAt;

  factory GroupDoubtSummary.fromJson(Map<String, dynamic> json) {
    return GroupDoubtSummary(
      id: json['id'] as String,
      body: json['body'] as String,
      senderId: json['sender_id'] as String,
      senderName: json['sender_name'] as String? ?? 'Member',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      replyCount: (json['reply_count'] as num).toInt(),
      doubtSolved: json['doubt_solved'] as bool? ?? false,
      solvedReplyId: json['solved_reply_id'] as String?,
      solvedAt: json['solved_at'] == null
          ? null
          : DateTime.parse(json['solved_at'] as String).toLocal(),
    );
  }
}

/// `{'open': n, 'solved': n}` from `fn_get_group_doubt_counts` (0122).
final class GroupDoubtCounts {
  const GroupDoubtCounts({required this.open, required this.solved});

  final int open;
  final int solved;

  factory GroupDoubtCounts.fromJson(Map<String, dynamic> json) =>
      GroupDoubtCounts(
        open: (json['open'] as num?)?.toInt() ?? 0,
        solved: (json['solved'] as num?)?.toInt() ?? 0,
      );

  static const zero = GroupDoubtCounts(open: 0, solved: 0);
}
