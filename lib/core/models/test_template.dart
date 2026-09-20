/// G19 — Test Template V1.
///
/// A reusable test configuration snapshot. NOT a live test.
/// Creating a test from a template produces an independent entity.
/// Template edits never modify created tests.
final class TestTemplate {
  const TestTemplate({
    required this.id,
    required this.createdBy,
    this.groupId,
    required this.title,
    this.description = '',
    this.configuration = const {},
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String createdBy;
  final String? groupId;
  final String title;
  final String description;
  final Map<String, dynamic> configuration;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isGroupTemplate => groupId != null;

  /// Convenience accessors for configuration keys.
  String? get kind => configuration['kind'] as String?;
  int? get durationSec => (configuration['duration_sec'] as num?)?.toInt();
  double? get marksPerQuestion =>
      (configuration['marks_per_question'] as num?)?.toDouble();
  double? get negativeMarks =>
      (configuration['negative_marks'] as num?)?.toDouble();
  String? get testMode => configuration['test_mode'] as String?;
  Map<String, dynamic>? get settings =>
      configuration['settings'] as Map<String, dynamic>?;
  Map<String, dynamic>? get attemptSettings =>
      configuration['attempt_settings'] as Map<String, dynamic>?;
  Map<String, dynamic>? get lateJoin =>
      configuration['late_join'] as Map<String, dynamic>?;
  Map<String, dynamic>? get questionConfig =>
      configuration['question_config'] as Map<String, dynamic>?;

  factory TestTemplate.fromJson(Map<String, dynamic> json) {
    return TestTemplate(
      id: json['id'] as String,
      createdBy: json['created_by'] as String,
      groupId: json['group_id'] as String?,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      configuration: _asMap(json['configuration']),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_by': createdBy,
    'group_id': groupId,
    'title': title,
    'description': description,
    'configuration': configuration,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };

  TestTemplate copyWith({
    String? title,
    String? description,
    Map<String, dynamic>? configuration,
    String? groupId,
  }) {
    return TestTemplate(
      id: id,
      createdBy: createdBy,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      description: description ?? this.description,
      configuration: configuration ?? this.configuration,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestTemplate &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          createdBy == other.createdBy &&
          title == other.title;

  @override
  int get hashCode => Object.hash(id, createdBy, title);

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }
}

/// Input for creating/updating a test template.
class TestTemplateInput {
  const TestTemplateInput({
    required this.title,
    this.description = '',
    this.groupId,
    required this.configuration,
  });

  final String title;
  final String description;
  final String? groupId;
  final Map<String, dynamic> configuration;

  Map<String, dynamic> toInsertParams(String createdBy) => {
    'created_by': createdBy,
    'title': title,
    'description': description,
    if (groupId != null) 'group_id': groupId,
    'configuration': configuration,
  };

  Map<String, dynamic> toUpdateParams() => {
    'title': title,
    'description': description,
    'configuration': configuration,
  };
}
