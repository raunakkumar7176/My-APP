import '../../../core/models/result.dart';
import '../../../core/models/test.dart';

/// AI Coach Report, parsed from `public.ai_reports` (live columns: id,
/// test_id, user_id, batch_id, payload jsonb, model, created_at). The payload
/// keys are the ones the only live producer writes (legacy coach generator,
/// `reportBatchSchema`): summary, strengths, weaknesses, mistake_patterns,
/// subject_analysis[{subject, performance, note}], revision_plan,
/// practice_plan, next_week_action_plan, coach_message. Missing keys read as
/// empty; nothing is invented client-side. AI never runs when this is read.
final class AiCoachReport {
  const AiCoachReport({
    required this.id,
    required this.testId,
    required this.userId,
    required this.batchId,
    required this.model,
    this.createdAt,
    this.summary,
    this.strengths = const [],
    this.weaknesses = const [],
    this.mistakePatterns = const [],
    this.subjectAnalysis = const [],
    this.revisionPlan = const [],
    this.practicePlan = const [],
    this.nextWeekActionPlan = const [],
    this.coachMessage,
    this.rawPayload = const {},
  });

  final String id;
  final String testId;
  final String userId;
  final String batchId;
  final String model;
  final DateTime? createdAt;
  final String? summary;
  final List<String> strengths;
  final List<String> weaknesses;
  final List<String> mistakePatterns;
  final List<SubjectAnalysis> subjectAnalysis;
  final List<String> revisionPlan;
  final List<String> practicePlan;
  final List<String> nextWeekActionPlan;
  final String? coachMessage;
  final Map<String, dynamic> rawPayload;

  bool get isEmpty =>
      (summary ?? '').isEmpty &&
      strengths.isEmpty &&
      weaknesses.isEmpty &&
      mistakePatterns.isEmpty &&
      subjectAnalysis.isEmpty &&
      revisionPlan.isEmpty &&
      practicePlan.isEmpty &&
      nextWeekActionPlan.isEmpty &&
      (coachMessage ?? '').isEmpty;

  factory AiCoachReport.fromJson(Map<String, dynamic> json) {
    final raw = json['payload'];
    final payload = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    return AiCoachReport(
      id: json['id'] as String,
      testId: json['test_id'] as String,
      userId: json['user_id'] as String,
      batchId: json['batch_id'] as String,
      model: (json['model'] as String?) ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String).toLocal(),
      summary: payload['summary'] as String?,
      strengths: _strings(payload['strengths']),
      weaknesses: _strings(payload['weaknesses']),
      mistakePatterns: _strings(payload['mistake_patterns']),
      subjectAnalysis: _subjects(payload['subject_analysis']),
      revisionPlan: _strings(payload['revision_plan']),
      practicePlan: _strings(payload['practice_plan']),
      nextWeekActionPlan: _strings(payload['next_week_action_plan']),
      coachMessage: payload['coach_message'] as String?,
      rawPayload: payload,
    );
  }

  static List<String> _strings(dynamic v) => v is List
      ? [for (final x in v) if (x is String && x.trim().isNotEmpty) x]
      : const [];

  static List<SubjectAnalysis> _subjects(dynamic v) => v is List
      ? [
          for (final x in v)
            if (x is Map && x['subject'] is String)
              SubjectAnalysis(
                subject: x['subject'] as String,
                performance: (x['performance'] as String?) ?? '',
                note: (x['note'] as String?) ?? '',
              ),
        ]
      : const [];
}

final class SubjectAnalysis {
  const SubjectAnalysis({
    required this.subject,
    required this.performance,
    required this.note,
  });
  final String subject;
  final String performance;
  final String note;
}

/// State of the queued coach-report job for a test, as returned by the
/// proposed `rpc_request_coach_reports` (see migrations/G11_*). The client
/// never reads `ai_jobs` directly (live RLS: no direct access).
final class CoachReportJob {
  const CoachReportJob({
    required this.jobId,
    required this.status,
    required this.reportsDone,
    required this.reportsTotal,
    required this.created,
  });

  final String jobId;

  /// `job_status`: pending | processing | completed | failed.
  final String status;
  final int reportsDone;
  final int reportsTotal;

  /// True when this call created the job; false when an identical request
  /// already existed (idempotency key) — never a second AI run.
  final bool created;

  bool get isDone => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isQueued => status == 'pending' || status == 'processing';

  factory CoachReportJob.fromJson(Map<String, dynamic> json) => CoachReportJob(
    jobId: (json['job_id'] ?? json['id']).toString(),
    status: (json['status'] as String?) ?? 'pending',
    reportsDone: (json['reports_done'] as num?)?.toInt() ?? 0,
    reportsTotal: (json['reports_total'] as num?)?.toInt() ?? 0,
    created: json['created'] == true,
  );
}

/// Deterministic, non-AI insights derived from one stored `results` row and
/// its test. Everything here is arithmetic over server data — the "weak
/// areas / mistakes / improvement points" a participant sees without any AI.
final class ResultInsights {
  const ResultInsights({
    required this.strongSubjects,
    required this.weakSubjects,
    required this.improvementPoints,
    required this.negativeMarksLost,
    required this.attemptedCount,
  });

  /// Subjects at or above [strongThreshold] % (from `subject_breakdown`).
  final List<MapEntry<String, double>> strongSubjects;

  /// Subjects below [weakThreshold] %, weakest first.
  final List<MapEntry<String, double>> weakSubjects;
  final List<String> improvementPoints;

  /// `wrong_count × negative_marks` when the test has negative marking.
  final double negativeMarksLost;
  final int attemptedCount;

  static const strongThreshold = 75.0;
  static const weakThreshold = 50.0;

  static ResultInsights from(Result r, {Test? test}) {
    final subjects = <MapEntry<String, double>>[
      for (final e in (r.subjectBreakdown ?? const {}).entries)
        if (e.value is num) MapEntry(e.key, (e.value as num).toDouble()),
    ]..sort((a, b) => a.value.compareTo(b.value));
    final weak = subjects.where((e) => e.value < weakThreshold).toList();
    final strong = subjects.where((e) => e.value >= strongThreshold).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final correct = r.correctCount ?? 0;
    final wrong = r.wrongCount ?? 0;
    final unanswered = r.unansweredCount ?? 0;
    final attempted = correct + wrong;
    final negative = (test?.negativeMarks ?? 0) > 0
        ? wrong * (test!.negativeMarks!)
        : 0.0;
    final points = <String>[
      if (weak.isNotEmpty)
        'Revise ${weak.map((e) => e.key).take(3).join(', ')} — below '
            '${weakThreshold.toStringAsFixed(0)}% in this test.',
      if (unanswered > 0)
        '$unanswered question${unanswered == 1 ? '' : 's'} left unanswered — '
            'practise pacing so every question gets an attempt.',
      if (negative > 0)
        'Negative marking cost ${negative.toStringAsFixed(1)} marks over $wrong '
            'wrong answer${wrong == 1 ? '' : 's'} — skip when unsure.',
      if (attempted > 0 && wrong > correct)
        'More wrong than correct among attempted questions — slow down on '
            'accuracy before speed.',
      if (weak.isEmpty && unanswered == 0 && wrong == 0 && correct > 0)
        'Clean run — keep this consistency on harder sets.',
    ];
    return ResultInsights(
      strongSubjects: strong,
      weakSubjects: weak,
      improvementPoints: points,
      negativeMarksLost: negative,
      attemptedCount: attempted,
    );
  }
}

/// Group-level summary over the `results` rows the server returned to this
/// caller (members get only their own row; VIEW_GROUP_ANALYTICS holders get
/// every participant). Pure arithmetic — no pass mark exists live, so none
/// is invented.
final class GroupTestResultsSummary {
  const GroupTestResultsSummary({
    required this.participants,
    this.averagePercentage,
    this.medianPercentage,
    this.highestPercentage,
    this.lowestPercentage,
  });

  final int participants;
  final double? averagePercentage;
  final double? medianPercentage;
  final double? highestPercentage;
  final double? lowestPercentage;

  static GroupTestResultsSummary from(List<Result> results) {
    final pcts = [
      for (final r in results)
        if (r.percentage != null) r.percentage!,
    ]..sort();
    if (pcts.isEmpty) return GroupTestResultsSummary(participants: results.length);
    final n = pcts.length;
    final median = n.isOdd ? pcts[n ~/ 2] : (pcts[n ~/ 2 - 1] + pcts[n ~/ 2]) / 2;
    return GroupTestResultsSummary(
      participants: results.length,
      averagePercentage: pcts.reduce((a, b) => a + b) / n,
      medianPercentage: median,
      highestPercentage: pcts.last,
      lowestPercentage: pcts.first,
    );
  }
}

/// UX gates mirroring the live server rules (the server re-checks each).
abstract final class GroupResultsAccess {
  /// `rpc_generate_results`: creator OR GENERATE_RESULTS in the test's group
  /// (owner passes through `fn_has_permission`).
  static bool canGenerate({
    required bool isCreator,
    required bool hasGenerateResults,
    required bool isOwner,
  }) => isCreator || hasGenerateResults || isOwner;

  /// `results` SELECT: own row always; every row with VIEW_GROUP_ANALYTICS.
  static bool canSeeAllResults({
    required bool hasViewAnalytics,
    required bool isOwner,
  }) => hasViewAnalytics || isOwner;

  /// `ai_reports` / `result_batches` SELECT: own report always; all reports
  /// and the batch row with GENERATE_RESULTS.
  static bool canSeeAllReports({
    required bool hasGenerateResults,
    required bool isOwner,
  }) => hasGenerateResults || isOwner;

  /// Results exist only once a test is over (the live sweep ends tests;
  /// `rpc_generate_results` itself does not check status).
  static bool isResultsPhase(TestStatus s) =>
      s == TestStatus.completed ||
      s == TestStatus.ended ||
      s == TestStatus.evaluated;

  /// Leaderboard access mirrors result visibility: any group member may
  /// view the leaderboard (the leaderboard shows only the same result data
  /// RLS already authorises). The server re-checks membership.
  static bool canSeeLeaderboard({
    required bool isMember,
    required bool isOwner,
  }) => isMember || isOwner;
}

/// One row on the leaderboard, derived entirely from a stored `Result`.
/// No score is computed client-side — every field comes from the server.
final class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.label,
    required this.score,
    required this.maxScore,
    this.percentage,
    this.accuracy,
    this.correctCount,
    this.wrongCount,
    this.unansweredCount,
    this.isCurrentUser = false,
  });

  /// Display rank (1-based). Tied participants share the same rank.
  final int rank;

  /// The participant's user id.
  final String userId;

  /// Display name resolved from the roster: "You", full name, or
  /// "Former member".
  final String label;

  final double? score;
  final double? maxScore;
  final double? percentage;
  final double? accuracy;
  final int? correctCount;
  final int? wrongCount;
  final int? unansweredCount;

  /// Whether this entry belongs to the signed-in user.
  final bool isCurrentUser;

  /// Build a deterministic leaderboard from stored results.
  ///
  /// **Ranking rule**: primary = `score` descending, secondary =
  /// `computed_at` ascending (earlier submission wins ties — a proxy for
  /// "submitted first" when the schema provides no attempt-order column).
  ///
  /// **Tie handling**: participants with the same `score` receive the same
  /// rank. The next distinct score receives rank = 1 + count of entries
  /// above it (dense rank is NOT used — this matches the conventional
  /// competition leaderboard).
  ///
  /// If a result has no `score`, it is placed at the bottom.
  static List<LeaderboardEntry> fromResults(
    List<Result> results, {
    required String currentUserId,
    required String Function(String userId) labelFor,
  }) {
    if (results.isEmpty) return const [];

    final sorted = List<Result>.from(results)..sort((a, b) {
      final sa = a.score ?? double.negativeInfinity;
      final sb = b.score ?? double.negativeInfinity;
      final byScore = sb.compareTo(sa);
      if (byScore != 0) return byScore;
      // Secondary: earlier computed_at is "better" (submitted first).
      final ta = a.computedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.computedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });

    final entries = <LeaderboardEntry>[];
    int currentRank = 0;
    double? prevScore;

    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      final s = r.score ?? double.negativeInfinity;
      if (prevScore == null || s != prevScore) {
        currentRank = i + 1;
        prevScore = s;
      }
      entries.add(LeaderboardEntry(
        rank: currentRank,
        userId: r.userId,
        label: labelFor(r.userId),
        score: r.score,
        maxScore: r.maxScore,
        percentage: r.percentage,
        accuracy: r.accuracy,
        correctCount: r.correctCount,
        wrongCount: r.wrongCount,
        unansweredCount: r.unansweredCount,
        isCurrentUser: r.userId == currentUserId,
      ));
    }

    return entries;
  }
}
