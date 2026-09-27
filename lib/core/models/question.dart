enum QuestionType { mcqSingle, mcqMultiple, trueFalse, integer, shortAnswer, unknown }

QuestionType _parseQuestionType(String? value) {
  switch (value) {
    case 'mcq_single':
    case 'mcq':
      return QuestionType.mcqSingle;
    case 'mcq_multiple':
      return QuestionType.mcqMultiple;
    case 'true_false':
    case 'tf':
      return QuestionType.trueFalse;
    case 'integer':
    case 'num':
      return QuestionType.integer;
    case 'short_answer':
    case 'short':
      return QuestionType.shortAnswer;
    default:
      return QuestionType.unknown;
  }
}

enum DifficultyLevel { easy, medium, hard, unknown }

DifficultyLevel _parseDifficulty(String? value) {
  switch (value) {
    case 'easy':
      return DifficultyLevel.easy;
    case 'medium':
      return DifficultyLevel.medium;
    case 'hard':
      return DifficultyLevel.hard;
    default:
      return DifficultyLevel.unknown;
  }
}

final class QuestionOption {
  const QuestionOption({
    required this.id,
    required this.text,
    this.index = -1,
  });

  /// Option id as stored in the `options` jsonb (may be empty for options
  /// created by the client). Not used to identify answers.
  final String id;
  final String text;

  /// Position in the server's `options` array. This is what the live
  /// `answers.selected_option` / `questions.correct_option` refer to, so it
  /// must survive display shuffling.
  final int index;

  /// Parses one element of the safe RPC's `options` array at [index].
  /// Elements are `{id, text}` objects; a bare string is tolerated.
  factory QuestionOption.fromJson(Object? json, {int index = -1}) {
    if (json is Map) {
      return QuestionOption(
        id: (json['id'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        index: index,
      );
    }
    return QuestionOption(id: '', text: json?.toString() ?? '', index: index);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'text': text};
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionOption &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text;

  @override
  int get hashCode => Object.hash(id, text);
}

final class Question {
  const Question({
    required this.id,
    required this.testId,
    this.ordinal,
    required this.question,
    this.options,
    this.explanation,
    this.subjectId,
    this.topicNodeId,
    required this.difficulty,
    required this.marks,
    this.negativeMarks,
    required this.status,
    this.sourceBatch,
    this.bankId,
    this.language,
    this.questionType,
    this.questionSource,
  });

  final String id;
  final String testId;
  final int? ordinal;
  final String question;
  final List<QuestionOption>? options;
  final String? explanation;
  final String? subjectId;
  final String? topicNodeId;
  final DifficultyLevel difficulty;
  final int marks;
  final double? negativeMarks;
  final String status;
  final String? sourceBatch;
  final String? bankId;
  final String? language;
  final QuestionType? questionType;

  /// Extension point only: no live `question_source` column is confirmed
  /// today (this is distinct from [sourceBatch], which is the live AI
  /// generation-batch integer). Pass-through from JSON if a future
  /// migration adds one; null until then — never fabricated.
  final String? questionSource;

  /// Returns a copy with [status] replaced; every other field is kept as-is
  /// (no answer-key data exists on this model to copy).
  Question copyWith({String? status}) {
    return Question(
      id: id,
      testId: testId,
      ordinal: ordinal,
      question: question,
      options: options,
      explanation: explanation,
      subjectId: subjectId,
      topicNodeId: topicNodeId,
      difficulty: difficulty,
      marks: marks,
      negativeMarks: negativeMarks,
      status: status ?? this.status,
      sourceBatch: sourceBatch,
      bankId: bankId,
      language: language,
      questionType: questionType,
      questionSource: questionSource,
    );
  }

  bool get isActive => status == 'active';
  bool get isMcq => questionType == QuestionType.mcqSingle || questionType == QuestionType.mcqMultiple;
  bool get isTrueFalse => questionType == QuestionType.trueFalse;
  bool get isTyped => questionType == QuestionType.integer || questionType == QuestionType.shortAnswer;
  bool get hasOptions => options != null && options!.isNotEmpty;

  factory Question.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'] as List<dynamic>?;
    final parsedOptions = rawOptions == null
        ? null
        : [
            for (var i = 0; i < rawOptions.length; i++)
              QuestionOption.fromJson(rawOptions[i], index: i),
          ];

    return Question(
      id: json['id'] as String,
      testId: json['test_id'] as String? ?? '',
      ordinal: (json['ordinal'] as num?)?.toInt(),
      question: json['question'] as String? ?? json['question_text'] as String? ?? '',
      options: parsedOptions,
      explanation: json['explanation'] as String?,
      subjectId: json['subject_id'] as String?,
      topicNodeId: json['topic_node_id'] as String?,
      difficulty: _parseDifficulty(json['difficulty'] as String?),
      marks: (json['marks'] as num?)?.toInt() ?? 1,
      negativeMarks: (json['negative_marks'] as num?)?.toDouble(),
      status: (json['status'] as String?) ?? 'active',
      // Live column is an integer; keep the model's string identity.
      sourceBatch: json['source_batch']?.toString(),
      bankId: json['bank_id'] as String?,
      language: json['language'] as String?,
      questionType: _parseQuestionType(json['question_type'] as String?),
      questionSource: json['question_source'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'test_id': testId,
      'ordinal': ordinal,
      'question': question,
      'options': options?.map((e) => e.toJson()).toList(),
      'explanation': explanation,
      'subject_id': subjectId,
      'topic_node_id': topicNodeId,
      'difficulty': difficulty.name,
      'marks': marks,
      'negative_marks': negativeMarks,
      'status': status,
      'source_batch': sourceBatch,
      'bank_id': bankId,
      'language': language,
      'question_type': questionType?.name,
      'question_source': questionSource,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Question &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          testId == other.testId &&
          question == other.question &&
          marks == other.marks;

  @override
  int get hashCode => Object.hash(id, testId, question, marks);
}
