import '../../../core/models/question.dart';

final class QuestionDraft {
  const QuestionDraft({
    this.id,
    required this.questionText,
    this.questionType = QuestionType.mcqSingle,
    this.options = const [],
    this.correctOptionIndex,
    this.explanation,
    this.subjectId,
    this.topicNodeId,
    this.difficulty = DifficultyLevel.medium,
    this.marks = 1,
    this.negativeMarks,
    this.language,
  });

  final String? id;
  final String questionText;
  final QuestionType questionType;
  final List<QuestionOptionDraft> options;
  final int? correctOptionIndex;
  final String? explanation;
  final String? subjectId;
  final String? topicNodeId;
  final DifficultyLevel difficulty;
  final int marks;
  final double? negativeMarks;
  final String? language;

  bool get hasValidOptions {
    if (questionType == QuestionType.mcqSingle ||
        questionType == QuestionType.mcqMultiple) {
      return options.length >= 2 &&
          options.every((o) => o.text.trim().isNotEmpty);
    }
    return true;
  }

  bool get hasCorrectOption {
    if (questionType == QuestionType.mcqSingle ||
        questionType == QuestionType.mcqMultiple) {
      return correctOptionIndex != null &&
          correctOptionIndex! >= 0 &&
          correctOptionIndex! < options.length;
    }
    return true;
  }

  bool get isValid {
    return questionText.trim().isNotEmpty &&
        marks > 0 &&
        hasValidOptions &&
        hasCorrectOption;
  }

  QuestionDraft copyWith({
    String? id,
    String? questionText,
    QuestionType? questionType,
    List<QuestionOptionDraft>? options,
    int? correctOptionIndex,
    String? explanation,
    String? subjectId,
    String? topicNodeId,
    DifficultyLevel? difficulty,
    int? marks,
    double? negativeMarks,
    String? language,
  }) {
    return QuestionDraft(
      id: id ?? this.id,
      questionText: questionText ?? this.questionText,
      questionType: questionType ?? this.questionType,
      options: options ?? this.options,
      correctOptionIndex: correctOptionIndex ?? this.correctOptionIndex,
      explanation: explanation ?? this.explanation,
      subjectId: subjectId ?? this.subjectId,
      topicNodeId: topicNodeId ?? this.topicNodeId,
      difficulty: difficulty ?? this.difficulty,
      marks: marks ?? this.marks,
      negativeMarks: negativeMarks ?? this.negativeMarks,
      language: language ?? this.language,
    );
  }

  Map<String, dynamic> toCreateParams({required String testId}) {
    final params = <String, dynamic>{
      'p_test_id': testId,
      'p_question': questionText,
    };

    params['p_question_type'] = _questionTypeToRpc(questionType);

    if (options.isNotEmpty) {
      params['p_options'] = options
          .map((o) => {'id': o.id ?? _generateOptionId(), 'text': o.text})
          .toList();
    }

    if (correctOptionIndex != null) {
      params['p_correct_option'] = correctOptionIndex;
    }

    if (explanation != null && explanation!.isNotEmpty) {
      params['p_explanation'] = explanation;
    }

    if (subjectId != null) params['p_subject_id'] = subjectId;
    if (topicNodeId != null) params['p_topic_node_id'] = topicNodeId;

    params['p_difficulty'] = _difficultyToRpc(difficulty);
    params['p_marks'] = marks;

    if (negativeMarks != null) {
      params['p_negative_marks'] = negativeMarks;
    }

    if (language != null && language!.isNotEmpty) {
      params['p_language'] = language;
    }

    return params;
  }

  Map<String, dynamic> toJson() {
    return {
      'questionText': questionText,
      'questionType': questionType.name,
      'options': options.map((o) => o.toJson()).toList(),
      'correctOptionIndex': correctOptionIndex,
      'explanation': explanation,
      'difficulty': difficulty.name,
      'marks': marks,
      'negativeMarks': negativeMarks,
      'language': language,
    };
  }

  static String _questionTypeToRpc(QuestionType type) {
    switch (type) {
      case QuestionType.mcqSingle:
      case QuestionType.mcqMultiple:
        return 'mcq';
      case QuestionType.trueFalse:
        return 'tf';
      case QuestionType.integer:
        return 'num';
      case QuestionType.shortAnswer:
        return 'short';
      case QuestionType.unknown:
        return 'mcq';
    }
  }

  static String _difficultyToRpc(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.easy:
        return 'easy';
      case DifficultyLevel.medium:
        return 'medium';
      case DifficultyLevel.hard:
        return 'hard';
      case DifficultyLevel.unknown:
        return 'medium';
    }
  }

  static String _generateOptionId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }
}

final class QuestionOptionDraft {
  const QuestionOptionDraft({
    this.id,
    required this.text,
  });

  final String? id;
  final String text;

  QuestionOptionDraft copyWith({
    String? id,
    String? text,
  }) {
    return QuestionOptionDraft(
      id: id ?? this.id,
      text: text ?? this.text,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
    };
  }
}
