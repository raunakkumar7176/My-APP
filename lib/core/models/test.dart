enum TestStatus { draft, scheduled, live, ready, published, completed, ended, evaluated, cancelled, archived, expired, unknown }

TestStatus _parseTestStatus(String? value) {
  switch (value) {
    case 'draft':
      return TestStatus.draft;
    case 'scheduled':
      return TestStatus.scheduled;
    case 'live':
      return TestStatus.live;
    case 'ready':
      return TestStatus.ready;
    case 'published':
      return TestStatus.published;
    case 'completed':
      return TestStatus.completed;
    case 'ended':
      return TestStatus.ended;
    case 'evaluated':
      return TestStatus.evaluated;
    case 'cancelled':
      return TestStatus.cancelled;
    case 'archived':
      return TestStatus.archived;
    case 'expired':
      return TestStatus.expired;
    default:
      return TestStatus.unknown;
  }
}

/// jsonb columns arrive as `Map<String, dynamic>`; anything else (null, a
/// string, a list) is treated as absent.
Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

final class Test {
  const Test({
    required this.id,
    required this.createdBy,
    required this.title,
    this.description,
    this.instructions,
    this.subjectId,
    this.classLevel,
    required this.status,
    this.durationSec,
    this.marksPerQuestion,
    this.negativeMarks,
    this.startsAt,
    this.endsAt,
    this.groupId,
    this.accessCode,
    this.joinCode,
    this.testMode,
    this.maxParticipants,
    this.allowLateJoin = false,
    this.isSoftDeleted = false,
    this.deletedAt,
    this.archivedAt,
    this.tags,
    this.language,
    this.difficulty,
    this.totalMarks,
    this.passingMarks,
    this.totalQuestions,
    this.shuffleQuestions = false,
    this.showAnswersAfter = false,
    this.isPublic = true,
    this.createdAt,
    this.updatedAt,
    this.config,
    this.settings,
  });

  final String id;
  final String createdBy;
  final String title;
  final String? description;
  final String? instructions;
  final String? subjectId;
  final String? classLevel;
  final TestStatus status;
  final int? durationSec;
  final double? marksPerQuestion;
  final double? negativeMarks;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? groupId;
  final String? accessCode;
  final String? joinCode;
  final String? testMode;
  final int? maxParticipants;
  final bool allowLateJoin;
  final bool isSoftDeleted;
  final DateTime? deletedAt;
  final DateTime? archivedAt;
  final List<String>? tags;
  final String? language;
  final String? difficulty;
  final int? totalMarks;
  final int? passingMarks;
  final int? totalQuestions;
  final bool shuffleQuestions;
  final bool showAnswersAfter;
  final bool isPublic;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Raw `config` / `settings` jsonb from the row. Kept as maps so an
  /// update can round-trip every key the client does not know about.
  final Map<String, dynamic>? config;
  final Map<String, dynamic>? settings;

  bool get isScheduled => status == TestStatus.scheduled;
  bool get isLive => status == TestStatus.live;
  bool get isCompleted => status == TestStatus.completed || status == TestStatus.ended;
  bool get isActive => status == TestStatus.scheduled || status == TestStatus.live || status == TestStatus.ready || status == TestStatus.published;
  bool get isCoded => accessCode != null || joinCode != null;

  factory Test.fromJson(Map<String, dynamic> json) {
    return Test(
      id: json['id'] as String,
      createdBy: json['created_by'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      instructions: json['instructions'] as String?,
      subjectId: json['subject_id'] as String?,
      classLevel: json['class_level'] as String?,
      status: _parseTestStatus(json['status'] as String?),
      durationSec: (json['duration_sec'] as num?)?.toInt(),
      marksPerQuestion: (json['marks_per_question'] as num?)?.toDouble(),
      negativeMarks: (json['negative_marks'] as num?)?.toDouble(),
      startsAt: json['starts_at'] != null ? DateTime.parse(json['starts_at'] as String) : null,
      endsAt: json['ends_at'] != null ? DateTime.parse(json['ends_at'] as String) : null,
      groupId: json['group_id'] as String?,
      accessCode: json['access_code'] as String?,
      joinCode: json['join_code'] as String?,
      testMode: json['test_mode'] as String?,
      maxParticipants: (json['max_participants'] as num?)?.toInt(),
      allowLateJoin: (json['allow_late_join'] as bool?) ?? false,
      isSoftDeleted: (json['is_soft_deleted'] as bool?) ?? false,
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at'] as String) : null,
      archivedAt: json['archived_at'] != null ? DateTime.parse(json['archived_at'] as String) : null,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
      language: json['language'] as String?,
      difficulty: json['difficulty'] as String?,
      totalMarks: (json['total_marks'] as num?)?.toInt(),
      passingMarks: (json['passing_marks'] as num?)?.toInt(),
      totalQuestions: (json['total_questions'] as num?)?.toInt(),
      shuffleQuestions: (json['shuffle_questions'] as bool?) ?? false,
      showAnswersAfter: (json['show_answers_after'] as bool?) ?? false,
      isPublic: (json['is_public'] as bool?) ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      config: _asMap(json['config']),
      settings: _asMap(json['settings']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_by': createdBy,
      'title': title,
      'description': description,
      'instructions': instructions,
      'subject_id': subjectId,
      'class_level': classLevel,
      'status': status.name,
      'duration_sec': durationSec,
      'marks_per_question': marksPerQuestion,
      'negative_marks': negativeMarks,
      'starts_at': startsAt?.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
      'group_id': groupId,
      'test_mode': testMode,
      'max_participants': maxParticipants,
      'allow_late_join': allowLateJoin,
      'is_soft_deleted': isSoftDeleted,
      'tags': tags,
      'language': language,
      'difficulty': difficulty,
      'total_marks': totalMarks,
      'passing_marks': passingMarks,
      'total_questions': totalQuestions,
      'shuffle_questions': shuffleQuestions,
      'show_answers_after': showAnswersAfter,
      'is_public': isPublic,
      'config': config,
      'settings': settings,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Test &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          createdBy == other.createdBy &&
          title == other.title &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, createdBy, title, status);
}
