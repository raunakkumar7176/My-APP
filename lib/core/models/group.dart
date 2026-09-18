/// One row of `rpc_get_user_groups()` — the live contract (R4 D):
/// `id, name, owner_id, logo_url, created_at, member_count, user_role`.
/// Only groups the caller owns or belongs to are ever returned.
///
/// The same class also carries a group's basic profile when it is read from
/// the `groups` table directly (G1): `description` and `privacy` are then
/// non-null. `invite_code` is deliberately absent from this model — it is a
/// sharing secret and is never selected by the list or hub reads.
final class Group {
  const Group({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.memberCount,
    this.logoUrl,
    this.userRole = 'member',
    this.description,
    this.privacy,
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

  /// `groups.description` (NOT NULL DEFAULT '' live). Null when the row came
  /// from the list RPC, which does not select it.
  final String? description;

  /// `groups.privacy` ∈ public | private | restricted. Null when unknown.
  final String? privacy;

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
      description: json['description'] as String?,
      privacy: json['privacy'] as String?,
    );
  }

  Group copyWith({
    String? name,
    String? description,
    String? privacy,
    int? memberCount,
    String? userRole,
  }) {
    return Group(
      id: id,
      name: name ?? this.name,
      ownerId: ownerId,
      logoUrl: logoUrl,
      createdAt: createdAt,
      memberCount: memberCount ?? this.memberCount,
      userRole: userRole ?? this.userRole,
      description: description ?? this.description,
      privacy: privacy ?? this.privacy,
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
      if (description != null) 'description': description,
      if (privacy != null) 'privacy': privacy,
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
