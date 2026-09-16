final class SyllabusNode {
  const SyllabusNode({
    required this.id,
    required this.subjectId,
    this.parentId,
    this.classLevel,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String subjectId;
  final String? parentId;
  final String? classLevel;
  final String name;
  final DateTime createdAt;

  bool get isRoot => parentId == null;

  factory SyllabusNode.fromJson(Map<String, dynamic> json) {
    return SyllabusNode(
      id: json['id'] as String,
      subjectId: json['subject_id'] as String,
      parentId: json['parent_id'] as String?,
      classLevel: json['class_level'] as String?,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject_id': subjectId,
      'parent_id': parentId,
      'class_level': classLevel,
      'name': name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyllabusNode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          subjectId == other.subjectId &&
          parentId == other.parentId &&
          classLevel == other.classLevel &&
          name == other.name &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        subjectId,
        parentId,
        classLevel,
        name,
        createdAt,
      );
}
