/// The exact jsonb shape `rpc_submit_and_score_test(p_attempt_id)` returns
/// (see `My-Prepration/supabase/migrations/0060_test_ecosystem_foundation.sql`
/// §5). Deliberately a separate model from [Result]: this scorecard has no
/// `user_id` (the RPC always operates on the caller's own attempt) and uses
/// different key names (`incorrect_count`, not `wrong_count`) — forcing it
/// into `Result.fromJson` would throw on the missing `user_id`.
final class SubmitScorecard {
  const SubmitScorecard({
    required this.success,
    required this.attemptId,
    required this.pointsAwarded,
    required this.testId,
    this.attemptStatus,
    this.evaluated = false,
    this.score,
    this.maxScore,
    this.percentage,
    this.accuracy,
    this.correctCount,
    this.incorrectCount,
    this.unansweredCount,
    this.totalQuestions,
    this.marksPerQuestion,
    this.negativeMarks,
    required this.resultPublished,
    this.answers,
  });

  final bool success;
  final String attemptId;

  /// From the server's `rpc_award_study_points(15, 'test_completion')` call
  /// inside the RPC — 0 on a repeat/idempotent submit (never re-awarded) or
  /// if the daily points cap was already hit.
  final int pointsAwarded;
  final String testId;
  final String? attemptStatus;
  final bool evaluated;
  final double? score;
  final double? maxScore;
  final double? percentage;
  final double? accuracy;
  final int? correctCount;
  final int? incorrectCount;
  final int? unansweredCount;
  final int? totalQuestions;
  final double? marksPerQuestion;
  final double? negativeMarks;

  /// `tests.is_result_published` at submit time. False only for a group
  /// test whose result hasn't been published yet — [answers] is withheld
  /// by the server in that case (see [answers]'s own doc).
  final bool resultPublished;

  /// The per-question answer snapshot (`{question_id: {selected_option,
  /// marked_for_review, time_spent}}`), or null — the server withholds this
  /// entirely when [resultPublished] is false, never a partial/redacted copy.
  final Map<String, dynamic>? answers;

  factory SubmitScorecard.fromJson(Map<String, dynamic> json) {
    return SubmitScorecard(
      success: json['success'] as bool? ?? false,
      attemptId: json['attempt_id'] as String,
      pointsAwarded: (json['points_awarded'] as num?)?.toInt() ?? 0,
      testId: json['test_id'] as String,
      attemptStatus: json['attempt_status'] as String?,
      evaluated: json['evaluated'] as bool? ?? false,
      score: (json['score'] as num?)?.toDouble(),
      maxScore: (json['max_score'] as num?)?.toDouble(),
      percentage: (json['percentage'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      correctCount: (json['correct_count'] as num?)?.toInt(),
      incorrectCount: (json['incorrect_count'] as num?)?.toInt(),
      unansweredCount: (json['unanswered_count'] as num?)?.toInt(),
      totalQuestions: (json['total_questions'] as num?)?.toInt(),
      marksPerQuestion: (json['marks_per_question'] as num?)?.toDouble(),
      negativeMarks: (json['negative_marks'] as num?)?.toDouble(),
      // Default true on a missing key so a self/practice test (which never
      // sets is_result_published false) is never mistakenly gated.
      resultPublished: json['result_published'] as bool? ?? true,
      answers: json['answers'] != null
          ? Map<String, dynamic>.from(json['answers'] as Map)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubmitScorecard &&
          runtimeType == other.runtimeType &&
          attemptId == other.attemptId &&
          pointsAwarded == other.pointsAwarded &&
          resultPublished == other.resultPublished;

  @override
  int get hashCode => Object.hash(attemptId, pointsAwarded, resultPublished);
}
