/// The JSONB payload stored in `public.test_ai_coach_reports.report_data`.
///
/// The database only enforces `jsonb_typeof(report_data) = 'object'`, so this
/// parser is deliberately tolerant. It reads the canonical keys this feature
/// writes — `summary`, `weak_topics`, `elimination_advice`,
/// `revision_priorities`, `coach_message` — and falls back to the richer
/// vocabulary used by the batch coach pipeline in `src/lib/ai/coach.ts`
/// (`weaknesses`, `mistake_patterns`, `revision_plan`,
/// `next_week_action_plan`). A row produced by either producer renders
/// instead of being thrown away.
final class CoachDiagnostic {
  const CoachDiagnostic({
    required this.summary,
    required this.weakTopics,
    required this.eliminationAdvice,
    required this.revisionPriorities,
    this.coachMessage,
  });

  final String summary;
  final List<String> weakTopics;
  final List<String> eliminationAdvice;
  final List<String> revisionPriorities;
  final String? coachMessage;

  /// True when the payload carries nothing this screen can show — a row that
  /// parsed but is effectively empty is treated like a cache miss so the
  /// generate CTA stays reachable.
  bool get isEmpty =>
      summary.isEmpty &&
      coachMessage == null &&
      weakTopics.isEmpty &&
      eliminationAdvice.isEmpty &&
      revisionPriorities.isEmpty;

  factory CoachDiagnostic.fromJson(Map<String, dynamic> json) {
    final summary = _text(json['summary']);
    final coachMessage = _text(json['coach_message']);
    return CoachDiagnostic(
      summary: summary ?? coachMessage ?? '',
      weakTopics: _lines(json['weak_topics'] ?? json['weaknesses']),
      eliminationAdvice:
          _lines(json['elimination_advice'] ?? json['mistake_patterns']),
      revisionPriorities: _lines(
        json['revision_priorities'] ??
            json['revision_plan'] ??
            json['next_week_action_plan'],
      ),
      coachMessage: coachMessage,
    );
  }

  /// Coerces one JSON value into a displayable line.
  ///
  /// Accepts a plain string, a number, or an object carrying its text under
  /// any of the key names the two producers use. Anything else (and any
  /// blank string) collapses to null so callers can skip it.
  static String? _text(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num) return value.toString();
    if (value is Map) {
      for (final key in const [
        'title',
        'text',
        'topic',
        'item',
        'name',
        'value',
        'step',
      ]) {
        final child = _text(value[key]);
        if (child != null) return child;
      }
      return null;
    }
    return _text(value.toString());
  }

  /// Coerces a JSON value into a list of non-empty displayable lines. A bare
  /// string is split on newlines so a producer that returned one blob still
  /// renders as separate bullets.
  static List<String> _lines(Object? value) {
    if (value == null) return const [];
    if (value is String) {
      final parts = <String>[];
      for (final raw in value.split(RegExp(r'\r?\n'))) {
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty) parts.add(trimmed);
      }
      return parts;
    }
    if (value is List) {
      final items = <String>[];
      for (final element in value) {
        final text = _text(element);
        if (text != null) items.add(text);
      }
      return items;
    }
    final single = _text(value);
    return single == null ? const [] : <String>[single];
  }
}
