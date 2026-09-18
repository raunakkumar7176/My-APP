/// One row of `public.group_invitations` — exactly the live columns:
/// `id, group_id, inviter_id, invitee_id, status (pending|accepted|declined|
/// expired), created_at`, `UNIQUE(group_id, invitee_id)`. There is **no
/// expiry column** live; `expired` is a status value nothing currently sets,
/// so it is parsed but never computed or dated here.
///
/// An invitation is never membership: only a `group_members` row grants
/// access, and only `fn_accept_group_invitation` creates one.
final class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.groupId,
    required this.inviterId,
    required this.inviteeId,
    required this.status,
    required this.createdAt,
  });

  static const statusPending = 'pending';
  static const statusAccepted = 'accepted';
  static const statusDeclined = 'declined';
  static const statusExpired = 'expired';

  final String id;
  final String groupId;
  final String inviterId;
  final String inviteeId;
  final String status;
  final DateTime createdAt;

  bool get isPending => status == statusPending;

  factory GroupInvitation.fromJson(Map<String, dynamic> json) {
    return GroupInvitation(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      inviterId: json['inviter_id'] as String,
      inviteeId: json['invitee_id'] as String,
      status: (json['status'] as String?) ?? statusPending,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'inviter_id': inviterId,
    'invitee_id': inviteeId,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupInvitation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, status);
}
