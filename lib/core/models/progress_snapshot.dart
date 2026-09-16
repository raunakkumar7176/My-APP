final class ProgressSnapshot {
  const ProgressSnapshot({
    required this.id,
    required this.userId,
    required this.periodType,
    required this.periodStart,
    required this.stats,
    required this.computedAt,
  });

  final String id;
  final String userId;
  final String periodType;
  final DateTime periodStart;
  final Map<String, dynamic> stats;
  final DateTime computedAt;

  int get completedTopics => (stats['completed_topics'] as num?)?.toInt() ?? 0;
  int get totalTopics => (stats['total_topics'] as num?)?.toInt() ?? 0;
  double get completionPercentage =>
      totalTopics > 0 ? (completedTopics / totalTopics * 100) : 0.0;
  int get studyMinutes => (stats['study_minutes'] as num?)?.toInt() ?? 0;

  factory ProgressSnapshot.fromJson(Map<String, dynamic> json) {
    return ProgressSnapshot(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      periodType: json['period_type'] as String,
      periodStart: DateTime.parse(json['period_start'] as String),
      stats: Map<String, dynamic>.from(
          (json['stats'] as Map<dynamic, dynamic>?) ?? {}),
      computedAt: DateTime.parse(json['computed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'period_type': periodType,
      'period_start': periodStart.toIso8601String(),
      'stats': stats,
      'computed_at': computedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressSnapshot &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          periodType == other.periodType &&
          periodStart == other.periodStart &&
          _mapEquals(stats, other.stats) &&
          computedAt == other.computedAt;

  @override
  int get hashCode => Object.hash(
        id,
        userId,
        periodType,
        periodStart,
        Object.hashAll(stats.entries),
        computedAt,
      );

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key].toString() != b[key].toString()) return false;
    }
    return true;
  }
}
