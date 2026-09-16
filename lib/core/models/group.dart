final class Group {
  const Group({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.memberCount,
    required this.userRole,
  });

  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;
  final String userRole;

  bool get isLeader => userRole == 'leader';
  bool get isMember => userRole == 'member';

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      userRole: (json['user_role'] as String?) ?? 'member',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
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
          createdBy == other.createdBy &&
          memberCount == other.memberCount &&
          userRole == other.userRole;

  @override
  int get hashCode => Object.hash(id, name, createdBy, memberCount, userRole);
}
