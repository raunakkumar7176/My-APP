/// Represents a user's most recent learning position.
final class ContinueLearningSnapshot {
  const ContinueLearningSnapshot({
    required this.subjectId,
    required this.subjectName,
    required this.chapterId,
    required this.chapterTitle,
    required this.topicId,
    required this.topicTitle,
    required this.progressPercentage,
    this.lastStudiedAt,
  });

  final String subjectId;
  final String subjectName;
  final String chapterId;
  final String chapterTitle;
  final String topicId;
  final String topicTitle;
  final double progressPercentage;
  final DateTime? lastStudiedAt;
}

/// Represents the high-level study counts for the user dashboard.
final class StudyProgressSummary {
  const StudyProgressSummary({
    this.completedTopicsCount = 0,
    this.completedChaptersCount = 0,
    this.activeSubjectsCount = 0,
  });

  final int completedTopicsCount;
  final int completedChaptersCount;
  final int activeSubjectsCount;
}
