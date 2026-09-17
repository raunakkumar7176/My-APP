import '../../../core/models/attempt.dart';
import '../../../core/models/result.dart';

/// One completed attempt joined with its stored result. Nothing here is
/// computed beyond what the `results` and `attempts` rows contain.
final class AttemptHistoryEntry {
  const AttemptHistoryEntry({
    required this.result,
    this.attempt,
  });

  final Result result;

  /// The matching `attempts` row (own-rows read); null when unavailable.
  final Attempt? attempt;

  /// Server-allocated number; falls back to null (never guessed) when the
  /// attempts row is missing.
  int? get attemptNumber => attempt?.attemptNumber;

  DateTime? get completedAt => attempt?.submittedAt ?? result.computedAt;

  /// Only when both timestamps are stored; null otherwise.
  Duration? get duration {
    final a = attempt;
    if (a == null || a.submittedAt == null) return null;
    final d = a.submittedAt!.difference(a.startedAt);
    return d.isNegative ? null : d;
  }
}

/// Difference between two stored results; every field is nullable and is
/// null whenever either side lacks the value (no fabrication).
final class ResultDelta {
  const ResultDelta({
    this.score,
    this.percentage,
    this.accuracy,
    this.correct,
    this.wrong,
    this.unanswered,
    this.time,
  });

  final double? score;
  final double? percentage;
  final double? accuracy;
  final int? correct;
  final int? wrong;
  final int? unanswered;
  final Duration? time;

  static ResultDelta between(AttemptHistoryEntry current, AttemptHistoryEntry previous) {
    double? d(double? a, double? b) => (a == null || b == null) ? null : a - b;
    int? i(int? a, int? b) => (a == null || b == null) ? null : a - b;
    final ct = current.duration;
    final pt = previous.duration;
    return ResultDelta(
      score: d(current.result.score, previous.result.score),
      percentage: d(current.result.percentage, previous.result.percentage),
      accuracy: d(current.result.accuracy, previous.result.accuracy),
      correct: i(current.result.correctCount, previous.result.correctCount),
      wrong: i(current.result.wrongCount, previous.result.wrongCount),
      unanswered: i(current.result.unansweredCount, previous.result.unansweredCount),
      time: (ct == null || pt == null) ? null : ct - pt,
    );
  }

  bool get isEmpty =>
      score == null &&
      percentage == null &&
      accuracy == null &&
      correct == null &&
      wrong == null &&
      unanswered == null &&
      time == null;
}

/// Builds the per-user history for one test from the stored rows.
abstract final class AttemptHistory {
  /// Joins results to attempts by `attempt_id`; ordered oldest → newest by
  /// attempt_number when known, else by computed_at.
  static List<AttemptHistoryEntry> build(List<Result> results, List<Attempt> attempts) {
    final byId = {for (final a in attempts) a.id: a};
    final entries = [
      for (final r in results) AttemptHistoryEntry(result: r, attempt: byId[r.attemptId]),
    ]..sort((x, y) {
        final nx = x.attemptNumber;
        final ny = y.attemptNumber;
        if (nx != null && ny != null) return nx.compareTo(ny);
        return (x.result.computedAt ?? DateTime(0))
            .compareTo(y.result.computedAt ?? DateTime(0));
      });
    return entries;
  }

  static AttemptHistoryEntry? latest(List<AttemptHistoryEntry> h) => h.isEmpty ? null : h.last;

  /// Highest score; ties resolved to the earliest attempt. Null when no
  /// entry carries a score (never derived from other fields).
  static AttemptHistoryEntry? best(List<AttemptHistoryEntry> h) {
    AttemptHistoryEntry? best;
    for (final e in h) {
      final s = e.result.score;
      if (s == null) continue;
      if (best == null || s > best.result.score!) best = e;
    }
    return best;
  }

  /// The entry immediately before [current] in history order.
  static AttemptHistoryEntry? previousOf(List<AttemptHistoryEntry> h, String attemptId) {
    final i = h.indexWhere((e) => e.result.attemptId == attemptId);
    return i <= 0 ? null : h[i - 1];
  }
}
