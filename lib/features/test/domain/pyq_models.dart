/// One exam entry in the PYQ catalog, with its available years.
final class PyqCatalogEntry {
  const PyqCatalogEntry({
    required this.examName,
    required this.years,
    required this.totalQuestions,
  });

  final String examName;
  final List<int> years;
  final int totalQuestions;

  factory PyqCatalogEntry.fromJson(Map<String, dynamic> json) {
    final rawYears = json['years'] as List<dynamic>?;
    return PyqCatalogEntry(
      examName: json['exam_name'] as String? ?? '',
      years: rawYears == null
          ? const []
          : rawYears.map((y) => (y as num).toInt()).toList(),
      totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single PYQ question. [correctOption] and [explanation] are only
/// populated in Practice Mode (rpc_get_pyq_questions_practice); Test Mode
/// (rpc_get_pyq_questions_test) never receives them from the server.
final class PyqQuestion {
  const PyqQuestion({
    required this.id,
    required this.question,
    this.questionHi,
    required this.options,
    this.optionsHi,
    this.correctOption,
    this.explanation,
    this.explanationHi,
    this.examSubject,
    this.difficulty = 'medium',
  });

  final String id;
  final String question;
  final String? questionHi;
  final List<String> options;
  final List<String>? optionsHi;
  final int? correctOption;
  final String? explanation;
  final String? explanationHi;
  final String? examSubject;
  final String difficulty;

  String displayQuestion(bool isHindi) =>
      (isHindi && (questionHi?.isNotEmpty ?? false)) ? questionHi! : question;

  List<String> displayOptions(bool isHindi) =>
      (isHindi && (optionsHi?.isNotEmpty ?? false)) ? optionsHi! : options;

  String? displayExplanation(bool isHindi) =>
      (isHindi && (explanationHi?.isNotEmpty ?? false)) ? explanationHi : explanation;

  factory PyqQuestion.fromJson(Map<String, dynamic> json) {
    return PyqQuestion(
      id: json['id'] as String,
      question: json['question'] as String? ?? '',
      questionHi: json['question_text_hi'] as String?,
      options: _stringList(json['options']),
      optionsHi: json['options_hi'] != null ? _stringList(json['options_hi']) : null,
      correctOption: (json['correct_option'] as num?)?.toInt(),
      explanation: json['explanation'] as String?,
      explanationHi: json['explanation_hi'] as String?,
      examSubject: json['exam_subject'] as String?,
      difficulty: json['difficulty'] as String? ?? 'medium',
    );
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) {
      if (e is Map) return (e['text'] ?? '').toString();
      return e.toString();
    }).toList();
  }
}

/// One graded answer inside a [PyqTestResult].
final class PyqAnswerResult {
  const PyqAnswerResult({
    required this.questionId,
    required this.selectedOption,
    required this.correctOption,
    required this.isCorrect,
    this.explanation,
    this.explanationHi,
  });

  final String questionId;
  final int? selectedOption;
  final int? correctOption;
  final bool isCorrect;
  final String? explanation;
  final String? explanationHi;

  factory PyqAnswerResult.fromJson(Map<String, dynamic> json) {
    return PyqAnswerResult(
      questionId: json['question_id'] as String? ?? '',
      selectedOption: (json['selected_option'] as num?)?.toInt(),
      correctOption: (json['correct_option'] as num?)?.toInt(),
      isCorrect: json['is_correct'] as bool? ?? false,
      explanation: json['explanation'] as String?,
      explanationHi: json['explanation_hi'] as String?,
    );
  }
}

/// Server-graded outcome of a Test Mode session (rpc_submit_pyq_test).
final class PyqTestResult {
  const PyqTestResult({
    required this.total,
    required this.correct,
    required this.scorePercentage,
    required this.results,
  });

  final int total;
  final int correct;
  final double scorePercentage;
  final List<PyqAnswerResult> results;

  factory PyqTestResult.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'] as List<dynamic>?;
    return PyqTestResult(
      total: (json['total'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      scorePercentage: (json['score_percentage'] as num?)?.toDouble() ?? 0,
      results: rawResults == null
          ? const []
          : rawResults
              .map((r) => PyqAnswerResult.fromJson(Map<String, dynamic>.from(r as Map)))
              .toList(),
    );
  }
}
