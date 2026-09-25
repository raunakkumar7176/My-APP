/// Domain model representing a study topic within a chapter.
final class StudyTopic {
  const StudyTopic({
    required this.id,
    required this.chapterId,
    required this.topicKey,
    required this.title,
    this.summary = '',
    this.orderIndex = 0,
    this.estimatedMinutes = 5,
    this.isCompleted = false,
  });

  final String id;
  final String chapterId;
  final String topicKey;
  final String title;
  final String summary;
  final int orderIndex;
  final int estimatedMinutes;
  final bool isCompleted;

  /// Resolves the topic details for the specified [languageCode] with
  /// automatic fallback to English or topic_key if translation is missing.
  factory StudyTopic.fromMap(
    Map<String, dynamic> map, {
    String languageCode = 'en',
    bool? isCompleted,
  }) {
    String title = (map['topic_key'] as String?) ?? '';
    String summary = '';

    final translationsRaw = map['topic_translations'];
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
        summary = (matching['summary'] as String?) ?? summary;
      }
    }

    bool completed = isCompleted ?? false;
    final progressRaw = map['user_study_progress'];
    if (progressRaw is List && progressRaw.isNotEmpty) {
      completed =
          (progressRaw.first as Map<String, dynamic>)['is_completed']
              as bool? ??
          false;
    } else if (map['is_completed'] is bool) {
      completed = map['is_completed'] as bool;
    }

    return StudyTopic(
      id: map['id'] as String,
      chapterId: map['chapter_id'] as String,
      topicKey: (map['topic_key'] as String?) ?? '',
      title: title,
      summary: summary,
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      estimatedMinutes: (map['estimated_minutes'] as num?)?.toInt() ?? 5,
      isCompleted: completed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chapter_id': chapterId,
      'topic_key': topicKey,
      'title': title,
      'summary': summary,
      'order_index': orderIndex,
      'estimated_minutes': estimatedMinutes,
      'is_completed': isCompleted,
    };
  }

  StudyTopic copyWith({
    String? id,
    String? chapterId,
    String? topicKey,
    String? title,
    String? summary,
    int? orderIndex,
    int? estimatedMinutes,
    bool? isCompleted,
  }) {
    return StudyTopic(
      id: id ?? this.id,
      chapterId: chapterId ?? this.chapterId,
      topicKey: topicKey ?? this.topicKey,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      orderIndex: orderIndex ?? this.orderIndex,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudyTopic &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          chapterId == other.chapterId &&
          topicKey == other.topicKey;

  @override
  int get hashCode => Object.hash(id, chapterId, topicKey);
}
