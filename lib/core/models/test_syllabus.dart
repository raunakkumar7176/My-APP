final class TestSyllabus {
  const TestSyllabus({
    required this.id,
    required this.testId,
    required this.syllabusNodeId,
    this.materialIds,
    required this.createdAt,
  });

  final String id;
  final String testId;
  final String syllabusNodeId;
  final List<String>? materialIds;
  final DateTime createdAt;

  factory TestSyllabus.fromJson(Map<String, dynamic> json) {
    return TestSyllabus(
      id: json['id'] as String,
      testId: json['test_id'] as String,
      syllabusNodeId: json['syllabus_node_id'] as String,
      materialIds: (json['material_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'test_id': testId,
      'syllabus_node_id': syllabusNodeId,
      'material_ids': materialIds,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestSyllabus &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          testId == other.testId &&
          syllabusNodeId == other.syllabusNodeId;

  @override
  int get hashCode => Object.hash(id, testId, syllabusNodeId);
}
