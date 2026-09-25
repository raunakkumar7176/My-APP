/// Domain model representing a high-level subject in the Study System.
final class StudySubject {
  const StudySubject({
    required this.id,
    required this.subjectKey,
    required this.name,
    this.description = '',
    this.icon,
    this.orderIndex = 0,
    this.chapterCount = 0,
    this.progressPercentage = 0.0,
  });

  final String id;
  final String subjectKey;
  final String name;
  final String description;
  final String? icon;
  final int orderIndex;
  final int chapterCount;
  final double progressPercentage;

  /// Resolves the subject using the requested [languageCode] (e.g. 'en', 'hi'),
  /// falling back gracefully to 'en', the first translation, or database name.
  factory StudySubject.fromMap(
    Map<String, dynamic> map, {
    String languageCode = 'en',
  }) {
    String name = (map['name'] as String?)?.trim() ?? '';
    String description = '';

    final translationsRaw = map['subject_translations'];
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
        final transName = (matching['name'] as String?)?.trim() ?? '';
        if (transName.isNotEmpty) {
          name = transName;
        }
        description = (matching['description'] as String?) ?? description;
      }
    }

    if (name.isEmpty) {
      final slug =
          (map['slug'] as String?)?.trim() ??
          (map['subject_key'] as String?)?.trim() ??
          '';
      if (slug.isNotEmpty) {
        name = slug
            .replaceAll('_', ' ')
            .split(' ')
            .map(
              (w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}',
            )
            .join(' ');
      } else {
        name = 'Subject';
      }
    }

    final chapterCount =
        (map['chapter_count'] as num?)?.toInt() ??
        (map['chapters'] is List ? (map['chapters'] as List).length : 0);
    final progress = (map['progress_percentage'] as num?)?.toDouble() ?? 0.0;

    return StudySubject(
      id: map['id'] as String,
      subjectKey:
          (map['slug'] as String?) ??
          (map['subject_key'] as String?) ??
          name.toLowerCase().replaceAll(' ', '_'),
      name: name,
      description: description,
      icon: map['icon'] as String?,
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      chapterCount: chapterCount,
      progressPercentage: progress,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject_key': subjectKey,
      'name': name,
      'description': description,
      'icon': icon,
      'order_index': orderIndex,
      'chapter_count': chapterCount,
      'progress_percentage': progressPercentage,
    };
  }

  StudySubject copyWith({
    String? id,
    String? subjectKey,
    String? name,
    String? description,
    String? icon,
    int? orderIndex,
    int? chapterCount,
    double? progressPercentage,
  }) {
    return StudySubject(
      id: id ?? this.id,
      subjectKey: subjectKey ?? this.subjectKey,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      orderIndex: orderIndex ?? this.orderIndex,
      chapterCount: chapterCount ?? this.chapterCount,
      progressPercentage: progressPercentage ?? this.progressPercentage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudySubject &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          subjectKey == other.subjectKey &&
          name == other.name;

  @override
  int get hashCode => Object.hash(id, subjectKey, name);
}
