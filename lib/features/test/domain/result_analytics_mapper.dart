import '../../../core/models/result.dart';
import '../../../core/models/result_analytics.dart';

/// Pure mapping from the server's `subject_breakdown` / `topic_breakdown`
/// jsonb to display items. No analytics are fabricated: if the server sends
/// nothing, the lists are empty. Subject names are looked up from a map the
/// controller provides (R3 subjects), never fetched here.
abstract final class ResultAnalyticsMapper {
  static List<SubjectBreakdownItem> subjects(
    Map<String, dynamic>? raw, {
    Map<String, String> subjectNames = const {},
  }) {
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final e in raw.entries)
        if (e.value is Map<String, dynamic>)
          SubjectBreakdownItem.fromRaw(
            subjectId: e.key,
            subjectName: subjectNames[e.key] ?? _short(e.key),
            data: e.value as Map<String, dynamic>,
          ),
    ];
  }

  static List<TopicBreakdownItem> topics(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final items = [
      for (final e in raw.entries)
        if (e.value is Map<String, dynamic>)
          TopicBreakdownItem.fromRaw(
            topicId: e.key,
            topicName: e.key.length > 20 ? '${e.key.substring(0, 20)}…' : e.key,
            data: e.value as Map<String, dynamic>,
          ),
    ]..sort((a, b) => b.wrong.compareTo(a.wrong));
    return items;
  }

  /// The attempt scored just before [currentResultId] in [history]
  /// (history is the current user's results, newest first).
  static Result? previous(List<Result> history, String currentResultId) {
    final sorted = List<Result>.from(history)
      ..sort(
        (a, b) => (b.computedAt ?? DateTime(0)).compareTo(
          a.computedAt ?? DateTime(0),
        ),
      );
    final i = sorted.indexWhere((r) => r.id == currentResultId);
    if (i < 0 || i >= sorted.length - 1) return null;
    return sorted[i + 1];
  }

  static String _short(String id) =>
      'Subject ${id.substring(0, id.length > 8 ? 8 : id.length)}';
}
