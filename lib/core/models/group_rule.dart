/// One row of `public.group_rules` — the live columns:
/// `id, group_id, rule_text, position, created_at, updated_at`.
/// Rules belong to exactly one group; `group_id` is the scope.
final class GroupRule {
  const GroupRule({
    required this.id,
    required this.groupId,
    required this.ruleText,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String groupId;
  final String ruleText;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GroupRule.fromJson(Map<String, dynamic> json) {
    return GroupRule(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      ruleText: json['rule_text'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'rule_text': ruleText,
    'position': position,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupRule &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          ruleText == other.ruleText &&
          position == other.position;

  @override
  int get hashCode => Object.hash(id, ruleText, position);

  GroupRule copyWith({
    String? ruleText,
    int? position,
    DateTime? updatedAt,
  }) {
    return GroupRule(
      id: id,
      groupId: groupId,
      ruleText: ruleText ?? this.ruleText,
      position: position ?? this.position,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
