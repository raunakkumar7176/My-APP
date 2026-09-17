/// One row of `rpc_get_user_groups()` — the live contract (R4 D):
/// `id, name, owner_id, logo_url, created_at, member_count, user_role`.
/// Only groups the caller owns or belongs to are ever returned.
final class Group {
  const Group({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.memberCount,
    this.logoUrl,
    this.userRole = 'member',
  });

  final String id;
  final String name;
  final String ownerId;
  final String? logoUrl;
  final DateTime createdAt;
  final int memberCount;

  /// Caller's role in the group: owner | leader | moderator | member
  /// (`public.group_role`); 'owner' when the caller owns the group without a
  /// membership row.
  final String userRole;

  bool get isOwner => userRole == 'owner';
  bool get isLeader => userRole == 'leader';
  bool get isModerator => userRole == 'moderator';
  bool get isMember => userRole == 'member';

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['owner_id'] as String,
      logoUrl: json['logo_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      userRole: (json['user_role'] as String?) ?? 'member',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'owner_id': ownerId,
      'logo_url': logoUrl,
      'created_at': createdAt.toIso8601String(),
      'member_count': memberCount,
      'user_role': userRole,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          ownerId == other.ownerId &&
          memberCount == other.memberCount &&
          userRole == other.userRole;

  @override
  int get hashCode => Object.hash(id, name, ownerId, memberCount, userRole);
}
