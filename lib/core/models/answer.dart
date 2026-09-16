/// One saved answer, mirroring the LIVE `public.answers` row
/// (verified 2026-09-16):
///   attempt_id uuid, question_id uuid, selected_option integer NULL,
///   marked_for_review boolean, updated_at timestamptz.
///
/// `selected_option` is the **index into the question's `options` array as
/// returned by `get_test_questions_safe`** (server order), not an option id.
/// There is no `text_answer` column: typed answers are a BACKEND GAP.
/// "Answered" is derived (`selected_option IS NOT NULL`); no flag exists.
final class Answer {
  const Answer({
    required this.attemptId,
    required this.questionId,
    this.selectedOption,
    this.markedForReview = false,
    this.updatedAt,
  });

  final String attemptId;
  final String questionId;
  final int? selectedOption;
  final bool markedForReview;
  final DateTime? updatedAt;

  bool get isAnswered => selectedOption != null;

  /// Copy with an explicit new selection (null clears it).
  Answer withSelection(int? selectedOption) => Answer(
        attemptId: attemptId,
        questionId: questionId,
        selectedOption: selectedOption,
        markedForReview: markedForReview,
        updatedAt: updatedAt,
      );

  Answer withMarkedForReview(bool marked) => Answer(
        attemptId: attemptId,
        questionId: questionId,
        selectedOption: selectedOption,
        markedForReview: marked,
        updatedAt: updatedAt,
      );

  /// Element of `p_answers` for `rpc_save_answers(uuid, jsonb)`. Only the
  /// fields the server validates/stores are sent.
  Map<String, dynamic> toRpcJson() => {
        'question_id': questionId,
        'selected_option': selectedOption,
        'marked_for_review': markedForReview,
      };

  /// Parses a live `answers` row.
  factory Answer.fromRow(Map<String, dynamic> row) {
    return Answer(
      attemptId: row['attempt_id'] as String,
      questionId: row['question_id'] as String,
      selectedOption: (row['selected_option'] as num?)?.toInt(),
      markedForReview: (row['marked_for_review'] as bool?) ?? false,
      updatedAt: row['updated_at'] != null
          ? DateTime.tryParse(row['updated_at'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Answer &&
          runtimeType == other.runtimeType &&
          attemptId == other.attemptId &&
          questionId == other.questionId &&
          selectedOption == other.selectedOption &&
          markedForReview == other.markedForReview;

  @override
  int get hashCode => Object.hash(attemptId, questionId, selectedOption, markedForReview);
}
