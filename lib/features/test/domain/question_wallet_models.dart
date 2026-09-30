/// One of the caller's own past tests, as listed for reuse.
final class PastTestSummary {
  const PastTestSummary({
    required this.testId,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.totalQuestions,
  });

  final String testId;
  final String title;
  final String status;
  final DateTime createdAt;
  final int totalQuestions;

  factory PastTestSummary.fromJson(Map<String, dynamic> json) {
    return PastTestSummary(
      testId: json['test_id'] as String,
      title: json['title'] as String? ?? 'Untitled Test',
      status: json['status'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single question available for reuse — either from a specific past
/// test (the checkbox picker) or from the Mistake Vault.
final class ReusableQuestion {
  const ReusableQuestion({
    required this.questionId,
    required this.question,
    required this.options,
    this.difficulty,
    this.sourceTestTitle,
    this.lastMissedAt,
  });

  final String questionId;
  final String question;
  final List<String> options;
  final String? difficulty;

  /// Only populated for Mistake Vault entries.
  final String? sourceTestTitle;
  final DateTime? lastMissedAt;

  factory ReusableQuestion.fromPickerJson(Map<String, dynamic> json) {
    return ReusableQuestion(
      questionId: json['question_id'] as String,
      question: json['question'] as String? ?? '',
      options: _parseOptions(json['options']),
      difficulty: json['difficulty'] as String?,
    );
  }

  factory ReusableQuestion.fromMistakeJson(Map<String, dynamic> json) {
    return ReusableQuestion(
      questionId: json['question_id'] as String,
      question: json['question'] as String? ?? '',
      options: _parseOptions(json['options']),
      sourceTestTitle: json['test_title'] as String?,
      lastMissedAt: DateTime.tryParse(json['last_missed_at'] as String? ?? ''),
    );
  }

  static List<String> _parseOptions(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) {
      if (e is Map) return (e['text'] ?? '').toString();
      return e.toString();
    }).toList();
  }
}
