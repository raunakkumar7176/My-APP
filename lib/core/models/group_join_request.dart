/// One row of `public.group_join_requests` — exactly the live columns:
/// `id, group_id, user_id, status (pending|approved|declined), created_at`,
/// `UNIQUE(group_id, user_id)`. Nothing else exists on the table (no expiry,
/// no message, no updated_at), so nothing else is modelled.
///
/// A request is never membership: only a `group_members` row grants access.
final class GroupJoinRequest {
  const GroupJoinRequest({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.status,
    required this.createdAt,
  });

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusDeclined = 'declined';

  final String id;
  final String groupId;
  final String userId;
  final String status;
  final DateTime createdAt;

  bool get isPending => status == statusPending;
  bool get isApproved => status == statusApproved;
  bool get isDeclined => status == statusDeclined;

  factory GroupJoinRequest.fromJson(Map<String, dynamic> json) {
    return GroupJoinRequest(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      status: (json['status'] as String?) ?? statusPending,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'user_id': userId,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupJoinRequest &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, status);
}
