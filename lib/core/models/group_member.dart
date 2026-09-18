/// One row of `public.group_members` (live PK is `(group_id, user_id)` —
/// there is no `id` column, so nothing here may key on one), optionally
/// embedded with the member's `profiles` row.
final class GroupMember {
  const GroupMember({
    required this.groupId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.fullName,
    this.avatarUrl,
  });

  final String groupId;
  final String userId;

  /// `public.group_role`: owner | leader | moderator | member.
  final String role;
  final DateTime joinedAt;

  /// From the embedded `profiles` row (readable under the live
  /// "fellow members read profiles" policy). Null when it was not selected.
  final String? fullName;
  final String? avatarUrl;

  String get displayName => (fullName != null && fullName!.trim().isNotEmpty)
      ? fullName!.trim()
      : 'Member';

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'];
    final p = profile is Map<String, dynamic>
        ? profile
        : (profile is List &&
              profile.isNotEmpty &&
              profile.first is Map<String, dynamic>)
        ? profile.first as Map<String, dynamic>
        : const <String, dynamic>{};
    return GroupMember(
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      role: (json['role'] as String?) ?? 'member',
      joinedAt: DateTime.parse(json['joined_at'] as String).toLocal(),
      fullName: p['full_name'] as String?,
      avatarUrl: p['avatar_url'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupMember &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          userId == other.userId &&
          role == other.role;

  @override
  int get hashCode => Object.hash(groupId, userId, role);
}
