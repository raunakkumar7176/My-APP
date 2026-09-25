/// Domain model representing a chapter belonging to a study subject.
final class StudyChapter {
  const StudyChapter({
    required this.id,
    required this.subjectId,
    required this.chapterKey,
    required this.title,
    this.description = '',
    this.orderIndex = 0,
    this.partKey,
    this.partTitle,
    this.partOrderIndex = 0,
    this.topicCount = 0,
    this.questionCount = 0,
    this.progressPercentage = 0.0,
  });

  final String id;
  final String subjectId;
  final String chapterKey;
  final String title;
  final String description;
  final int orderIndex;
  final String? partKey;
  final String? partTitle;
  final int partOrderIndex;
  final int topicCount;
  final int questionCount;
  final double progressPercentage;

  /// Resolves the chapter details for the given [languageCode], falling back
  /// to 'en' or chapter_key if specific translation is absent.
  factory StudyChapter.fromMap(
    Map<String, dynamic> map, {
    String languageCode = 'en',
  }) {
    String title = (map['chapter_key'] as String?) ?? '';
    String description = '';
    String? partTitle;

    final translationsRaw = map['chapter_translations'];
    if (translationsRaw is List && translationsRaw.isNotEmpty) {
      Map<dynamic, dynamic>? matching;
      for (final t in translationsRaw) {
        if (t is Map && t['language'] == languageCode) {
          matching = t;
          break;
        }
      }
      if (matching == null) {
        for (final t in translationsRaw) {
          if (t is Map && t['language'] == 'en') {
            matching = t;
            break;
          }
        }
      }
      matching ??= (translationsRaw.first is Map
          ? translationsRaw.first as Map
          : null);

      if (matching != null) {
        title = (matching['title'] as String?) ?? title;
        description = (matching['description'] as String?) ?? description;
        partTitle = matching['part_title'] as String?;
      }
    }

    final topicCount =
        (map['topic_count'] as num?)?.toInt() ??
        (map['topics'] is List ? (map['topics'] as List).length : 0);
    final questionCount = (map['question_count'] as num?)?.toInt() ?? 0;
    final progress = (map['progress_percentage'] as num?)?.toDouble() ?? 0.0;

    return StudyChapter(
      id: map['id'] as String,
      subjectId: map['subject_id'] as String,
      chapterKey: (map['chapter_key'] as String?) ?? '',
      title: title,
      description: description,
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      partKey: map['part_key'] as String?,
      partTitle: partTitle,
      partOrderIndex: (map['part_order_index'] as num?)?.toInt() ?? 0,
      topicCount: topicCount,
      questionCount: questionCount,
      progressPercentage: progress,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject_id': subjectId,
      'chapter_key': chapterKey,
      'title': title,
      'description': description,
      'order_index': orderIndex,
      'part_key': partKey,
      'part_title': partTitle,
      'part_order_index': partOrderIndex,
      'topic_count': topicCount,
      'question_count': questionCount,
      'progress_percentage': progressPercentage,
    };
  }

  StudyChapter copyWith({
    String? id,
    String? subjectId,
    String? chapterKey,
    String? title,
    String? description,
    int? orderIndex,
    String? partKey,
    String? partTitle,
    int? partOrderIndex,
    int? topicCount,
    int? questionCount,
    double? progressPercentage,
  }) {
    return StudyChapter(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      chapterKey: chapterKey ?? this.chapterKey,
      title: title ?? this.title,
      description: description ?? this.description,
      orderIndex: orderIndex ?? this.orderIndex,
      partKey: partKey ?? this.partKey,
      partTitle: partTitle ?? this.partTitle,
      partOrderIndex: partOrderIndex ?? this.partOrderIndex,
      topicCount: topicCount ?? this.topicCount,
      questionCount: questionCount ?? this.questionCount,
      progressPercentage: progressPercentage ?? this.progressPercentage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudyChapter &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          chapterKey == other.chapterKey &&
          subjectId == other.subjectId &&
          partKey == other.partKey;

  @override
  int get hashCode => Object.hash(id, subjectId, chapterKey, partKey);
}
