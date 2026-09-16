final class Result {
  const Result({
    required this.id,
    required this.attemptId,
    required this.testId,
    required this.userId,
    this.batchId,
    this.totalMarks,
    this.marksObtained,
    this.percentage,
    this.isPassed,
    this.correctCount,
    this.wrongCount,
    this.unansweredCount,
    this.partialCount,
    this.totalQuestions,
    this.score,
    this.maxScore,
    this.accuracy,
    this.rank,
    this.subjectBreakdown,
    this.topicBreakdown,
    this.computedAt,
    this.generationMethod,
  });

  final String id;
  final String attemptId;
  final String testId;
  final String userId;
  final String? batchId;
  final int? totalMarks;
  final double? marksObtained;
  final double? percentage;
  final bool? isPassed;
  final int? correctCount;
  final int? wrongCount;
  final int? unansweredCount;
  final int? partialCount;
  final int? totalQuestions;
  final double? score;
  final double? maxScore;
  final double? accuracy;
  final int? rank;
  final Map<String, dynamic>? subjectBreakdown;
  final Map<String, dynamic>? topicBreakdown;
  final DateTime? computedAt;
  final String? generationMethod;

  factory Result.fromJson(Map<String, dynamic> json) {
    return Result(
      id: json['id'] as String,
      attemptId: json['attempt_id'] as String,
      testId: json['test_id'] as String,
      userId: json['user_id'] as String,
      batchId: json['batch_id'] as String?,
      totalMarks: (json['total_marks'] as num?)?.toInt(),
      marksObtained: (json['marks_obtained'] as num?)?.toDouble(),
      percentage: (json['percentage'] as num?)?.toDouble(),
      isPassed: json['is_passed'] as bool?,
      correctCount: (json['correct_count'] as num?)?.toInt(),
      wrongCount: (json['wrong_count'] as num?)?.toInt(),
      unansweredCount: (json['unanswered_count'] as num?)?.toInt(),
      partialCount: (json['partial_count'] as num?)?.toInt(),
      totalQuestions: (json['total_questions'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toDouble(),
      maxScore: (json['max_score'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      rank: (json['rank'] as num?)?.toInt(),
      subjectBreakdown: json['subject_breakdown'] != null
          ? Map<String, dynamic>.from(json['subject_breakdown'] as Map)
          : null,
      topicBreakdown: json['topic_breakdown'] != null
          ? Map<String, dynamic>.from(json['topic_breakdown'] as Map)
          : null,
      computedAt: json['computed_at'] != null
          ? DateTime.parse(json['computed_at'] as String)
          : null,
      generationMethod: json['generation_method'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'attempt_id': attemptId,
      'test_id': testId,
      'user_id': userId,
      'batch_id': batchId,
      'total_marks': totalMarks,
      'marks_obtained': marksObtained,
      'percentage': percentage,
      'is_passed': isPassed,
      'correct_count': correctCount,
      'wrong_count': wrongCount,
      'unanswered_count': unansweredCount,
      'partial_count': partialCount,
      'total_questions': totalQuestions,
      'score': score,
      'max_score': maxScore,
      'accuracy': accuracy,
      'rank': rank,
      'subject_breakdown': subjectBreakdown,
      'topic_breakdown': topicBreakdown,
      'generation_method': generationMethod,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Result &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          attemptId == other.attemptId &&
          testId == other.testId;

  @override
  int get hashCode => Object.hash(id, attemptId, testId);
}
