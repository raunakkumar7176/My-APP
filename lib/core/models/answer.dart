final class Answer {
  const Answer({
    required this.attemptId,
    required this.questionId,
    this.selectedOptionId,
    this.textAnswer,
    this.isMarkedForReview = false,
    this.isAnswered = false,
  });

  final String attemptId;
  final String questionId;
  final String? selectedOptionId;
  final String? textAnswer;
  final bool isMarkedForReview;
  final bool isAnswered;

  Answer copyWith({
    String? selectedOptionId,
    String? textAnswer,
    bool? isMarkedForReview,
    bool? isAnswered,
  }) {
    return Answer(
      attemptId: attemptId,
      questionId: questionId,
      selectedOptionId: selectedOptionId ?? this.selectedOptionId,
      textAnswer: textAnswer ?? this.textAnswer,
      isMarkedForReview: isMarkedForReview ?? this.isMarkedForReview,
      isAnswered: isAnswered ?? this.isAnswered,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'attempt_id': attemptId,
      'question_id': questionId,
      'selected_option_id': selectedOptionId,
      'text_answer': textAnswer,
      'is_marked_for_review': isMarkedForReview,
      'is_answered': isAnswered,
    };
  }

  factory Answer.fromJson(Map<String, dynamic> json) {
    return Answer(
      attemptId: json['attempt_id'] as String,
      questionId: json['question_id'] as String,
      selectedOptionId: json['selected_option_id'] as String?,
      textAnswer: json['text_answer'] as String?,
      isMarkedForReview: (json['is_marked_for_review'] as bool?) ?? false,
      isAnswered: (json['is_answered'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Answer &&
          runtimeType == other.runtimeType &&
          attemptId == other.attemptId &&
          questionId == other.questionId &&
          selectedOptionId == other.selectedOptionId &&
          textAnswer == other.textAnswer &&
          isMarkedForReview == other.isMarkedForReview &&
          isAnswered == other.isAnswered;

  @override
  int get hashCode => Object.hash(
        attemptId,
        questionId,
        selectedOptionId,
        textAnswer,
        isMarkedForReview,
        isAnswered,
      );
}
