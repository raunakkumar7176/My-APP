/// 'week' | 'month' | 'all_time' — matches `rpc_get_performance_summary`'s
/// `p_filter` parameter (migration 0072) exactly; never translated.
enum TimeFilter {
  week,
  month,
  allTime;

  String get rpcValue => switch (this) {
        TimeFilter.week => 'week',
        TimeFilter.month => 'month',
        TimeFilter.allTime => 'all_time',
      };

  String get label => switch (this) {
        TimeFilter.week => 'This Week',
        TimeFilter.month => 'Monthly',
        TimeFilter.allTime => 'All Time',
      };
}

/// `rpc_get_performance_summary`'s return shape (migration 0072). Every
/// field is a real server-computed aggregate over the caller's own
/// `attempts`/`answers`/`routine_logs` rows — nothing here is estimated.
final class PerformanceSummary {
  const PerformanceSummary({
    required this.filter,
    required this.totalTestsCompleted,
    required this.totalQuestionsAttempted,
    required this.accuracyPercentage,
    required this.totalStudyMinutes,
    required this.speedAvgSecondsPerQ,
  });

  final String filter;
  final int totalTestsCompleted;
  final int totalQuestionsAttempted;
  final double accuracyPercentage;
  final double totalStudyMinutes;
  final double speedAvgSecondsPerQ;

  double get totalStudyHours => totalStudyMinutes / 60;

  static const empty = PerformanceSummary(
    filter: 'week',
    totalTestsCompleted: 0,
    totalQuestionsAttempted: 0,
    accuracyPercentage: 0,
    totalStudyMinutes: 0,
    speedAvgSecondsPerQ: 0,
  );

  factory PerformanceSummary.fromJson(Map<String, dynamic> json) {
    return PerformanceSummary(
      filter: json['filter'] as String? ?? 'week',
      totalTestsCompleted: (json['total_tests_completed'] as num?)?.toInt() ?? 0,
      totalQuestionsAttempted: (json['total_questions_attempted'] as num?)?.toInt() ?? 0,
      accuracyPercentage: (json['accuracy_percentage'] as num?)?.toDouble() ?? 0,
      totalStudyMinutes: (json['total_study_minutes'] as num?)?.toDouble() ?? 0,
      speedAvgSecondsPerQ: (json['speed_avg_seconds_per_q'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One row from `rpc_get_subject_wise_breakdown` (migration 0072) — real
/// per-subject counts aggregated directly from `answers`/`questions`, not
/// from the known-unreliable `results.subject_breakdown` column (see that
/// migration's D2 for why).
final class SubjectWiseBreakdown {
  const SubjectWiseBreakdown({
    required this.groupKey,
    required this.subjectName,
    required this.totalQuestions,
    required this.correctCount,
    required this.accuracyPct,
    required this.status,
  });

  /// Migration 0082: the real `subjects.id`, or `'test:<test id>'` when the
  /// question fell back to its parent test's title (0081) — pass this back
  /// to `rpc_get_subject_results` to drill into the underlying test results.
  final String groupKey;
  final String subjectName;
  final int totalQuestions;
  final int correctCount;
  final double accuracyPct;

  /// 'strong' | 'moderate' | 'weak'.
  final String status;

  bool get isStrong => status == 'strong';
  bool get isWeak => status == 'weak';

  factory SubjectWiseBreakdown.fromJson(Map<String, dynamic> json) {
    return SubjectWiseBreakdown(
      groupKey: json['group_key'] as String? ?? '',
      subjectName: json['subject_name'] as String? ?? '',
      totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
      correctCount: (json['correct_count'] as num?)?.toInt() ?? 0,
      accuracyPct: (json['accuracy_pct'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'moderate',
    );
  }
}

/// One row from `rpc_get_subject_results` (migration 0082) — a specific
/// scored test result that fed into a Subject Mastery row, so tapping the
/// subject card can show exactly which tests it came from.
final class SubjectResultEntry {
  const SubjectResultEntry({
    required this.attemptId,
    required this.testId,
    required this.testTitle,
    required this.score,
    required this.maxScore,
    required this.percentage,
    required this.accuracy,
    required this.correctCount,
    required this.wrongCount,
    required this.unansweredCount,
    required this.computedAt,
  });

  final String attemptId;
  final String testId;
  final String testTitle;
  final double score;
  final double maxScore;
  final double percentage;
  final double accuracy;
  final int correctCount;
  final int wrongCount;
  final int unansweredCount;
  final DateTime computedAt;

  factory SubjectResultEntry.fromJson(Map<String, dynamic> json) {
    return SubjectResultEntry(
      attemptId: json['attempt_id'] as String? ?? '',
      testId: json['test_id'] as String? ?? '',
      testTitle: json['test_title'] as String? ?? 'Test',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      maxScore: (json['max_score'] as num?)?.toDouble() ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      correctCount: (json['correct_count'] as num?)?.toInt() ?? 0,
      wrongCount: (json['wrong_count'] as num?)?.toInt() ?? 0,
      unansweredCount: (json['unanswered_count'] as num?)?.toInt() ?? 0,
      computedAt: DateTime.tryParse(json['computed_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// One day's real activity from `rpc_get_daily_activity` (migration 0072).
final class DailyActivity {
  const DailyActivity({
    required this.date,
    required this.questionsAttempted,
    required this.studyMinutes,
  });

  final DateTime date;
  final int questionsAttempted;
  final double studyMinutes;

  factory DailyActivity.fromJson(Map<String, dynamic> json) {
    return DailyActivity(
      date: DateTime.parse(json['day_date'] as String),
      questionsAttempted: (json['questions_attempted'] as num?)?.toInt() ?? 0,
      studyMinutes: (json['study_minutes'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// `weekly_performance_reports` row / `rpc_generate_my_weekly_report`'s
/// return shape (migration 0072).
final class WeeklyPerformanceReport {
  const WeeklyPerformanceReport({
    required this.weekStartDate,
    required this.weekEndDate,
    required this.totalHours,
    required this.accuracyPct,
    required this.testsCount,
    this.weakSubjectId,
  });

  final DateTime weekStartDate;
  final DateTime weekEndDate;
  final double totalHours;
  final double accuracyPct;
  final int testsCount;
  final String? weakSubjectId;

  factory WeeklyPerformanceReport.fromJson(Map<String, dynamic> json) {
    return WeeklyPerformanceReport(
      weekStartDate: DateTime.parse(json['week_start_date'] as String),
      weekEndDate: DateTime.parse(json['week_end_date'] as String),
      totalHours: (json['total_hours'] as num?)?.toDouble() ?? 0,
      accuracyPct: (json['accuracy_pct'] as num?)?.toDouble() ?? 0,
      testsCount: (json['tests_count'] as num?)?.toInt() ?? 0,
      weakSubjectId: json['weak_subject_id'] as String?,
    );
  }
}
