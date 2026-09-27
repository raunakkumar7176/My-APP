/// Represents a single question in the question bank (maps to `question_bank` table).
///
/// SECURITY: This model intentionally excludes `correct_option` from the
/// safe listing/detail DTOs. The correct answer is only available through
/// server-side governance operations (REVIEW_QUESTIONS permission).
final class QuestionBankItem {
  const QuestionBankItem({
    required this.id,
    required this.question,
    required this.options,
    this.correctOption,
    this.explanation = '',
    this.subjectId,
    this.subjectName = '',
    this.chapter = '',
    this.topicNodeId,
    this.difficulty = 'medium',
    this.language = 'en',
    this.questionType = 'mcq',
    this.source = 'manual',
    this.createdBy,
    this.timesUsed = 0,
    this.status = 'pending_review',
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    this.updatedAt,
    this.archivedAt,
    this.duplicateKey,
    this.isPyq = false,
  });

  final String id;
  final String question;
  final List<QuestionBankOption> options;
  final int? correctOption;
  final String explanation;
  final String? subjectId;
  final String subjectName;
  final String chapter;
  final String? topicNodeId;
  final String difficulty;
  final String language;
  final String questionType;
  final String source;
  final String? createdBy;
  final int timesUsed;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? archivedAt;
  final String? duplicateKey;

  /// `question_bank.is_pyq` (migration 0064) — true for a Previous Year
  /// Question. Defaults false for any row from before that column existed.
  final bool isPyq;

  bool get isApproved => status == 'approved';
  bool get isPendingReview => status == 'pending_review';
  bool get isArchived => status == 'archived' || archivedAt != null;
  bool get hasExplanation => explanation.trim().isNotEmpty;

  factory QuestionBankItem.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'] as List<dynamic>?;
    final parsedOptions = rawOptions == null
        ? const <QuestionBankOption>[]
        : [
            for (var i = 0; i < rawOptions.length; i++)
              QuestionBankOption.fromJson(rawOptions[i], index: i),
          ];

    return QuestionBankItem(
      id: json['id'] as String,
      question: json['question'] as String? ?? '',
      options: parsedOptions,
      correctOption: (json['correct_option'] as num?)?.toInt(),
      explanation: json['explanation'] as String? ?? '',
      subjectId: json['subject_id'] as String?,
      subjectName: json['subject_name'] as String? ?? '',
      chapter: json['chapter'] as String? ?? '',
      topicNodeId: json['topic_node_id'] as String?,
      difficulty: json['difficulty'] as String? ?? 'medium',
      language: json['language'] as String? ?? 'en',
      questionType: json['question_type'] as String? ?? 'mcq',
      source: json['source'] as String? ?? 'manual',
      createdBy: json['created_by'] as String?,
      timesUsed: (json['times_used'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending_review',
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'] as String)
          : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      archivedAt: json['archived_at'] != null
          ? DateTime.tryParse(json['archived_at'] as String)
          : null,
      duplicateKey: json['duplicate_key'] as String?,
      isPyq: json['is_pyq'] as bool? ?? false,
    );
  }

  /// Creates a safe copy without correct_option for non-reviewer users.
  QuestionBankItem toSafeCopy() {
    return QuestionBankItem(
      id: id,
      question: question,
      options: options,
      correctOption: null,
      explanation: explanation,
      subjectId: subjectId,
      subjectName: subjectName,
      chapter: chapter,
      topicNodeId: topicNodeId,
      difficulty: difficulty,
      language: language,
      questionType: questionType,
      source: source,
      createdBy: createdBy,
      timesUsed: timesUsed,
      status: status,
      reviewedBy: reviewedBy,
      reviewedAt: reviewedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      archivedAt: archivedAt,
      duplicateKey: duplicateKey,
      isPyq: isPyq,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionBankItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          question == other.question;

  @override
  int get hashCode => Object.hash(id, question);
}

/// Represents an option in a bank question.
final class QuestionBankOption {
  const QuestionBankOption({
    required this.text,
    this.index = -1,
  });

  final String text;
  final int index;

  factory QuestionBankOption.fromJson(Object? json, {int index = -1}) {
    if (json is Map) {
      return QuestionBankOption(
        text: (json['text'] ?? '').toString(),
        index: index,
      );
    }
    return QuestionBankOption(text: json?.toString() ?? '', index: index);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionBankOption &&
          runtimeType == other.runtimeType &&
          text == other.text;

  @override
  int get hashCode => text.hashCode;
}

/// Filter parameters for querying the question bank.
class QuestionBankFilter {
  const QuestionBankFilter({
    this.search,
    this.status,
    this.subjectId,
    this.subjectName,
    this.chapter,
    this.topicNodeId,
    this.difficulty,
    this.language,
    this.questionType,
    this.source,
    this.pyqOnly = false,
    this.pageSize = 20,
    this.offset = 0,
  });

  final String? search;
  final String? status;
  final String? subjectId;
  final String? subjectName;
  final String? chapter;
  final String? topicNodeId;
  final String? difficulty;
  final String? language;
  final String? questionType;
  final String? source;

  /// `question_bank.is_pyq` filter (migration 0064). False (the default)
  /// means "no filter" — never excludes non-PYQ rows.
  final bool pyqOnly;
  final int pageSize;
  final int offset;

  bool get isEmpty =>
      search == null &&
      status == null &&
      subjectId == null &&
      subjectName == null &&
      chapter == null &&
      topicNodeId == null &&
      difficulty == null &&
      language == null &&
      questionType == null &&
      source == null &&
      !pyqOnly;

  QuestionBankFilter copyWith({
    String? search,
    String? status,
    String? subjectId,
    String? subjectName,
    String? chapter,
    String? topicNodeId,
    String? difficulty,
    String? language,
    String? questionType,
    String? source,
    bool? pyqOnly,
    int? pageSize,
    int? offset,
  }) {
    return QuestionBankFilter(
      search: search ?? this.search,
      status: status ?? this.status,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      chapter: chapter ?? this.chapter,
      topicNodeId: topicNodeId ?? this.topicNodeId,
      difficulty: difficulty ?? this.difficulty,
      language: language ?? this.language,
      questionType: questionType ?? this.questionType,
      source: source ?? this.source,
      pyqOnly: pyqOnly ?? this.pyqOnly,
      pageSize: pageSize ?? this.pageSize,
      offset: offset ?? this.offset,
    );
  }

  /// Returns a new filter with offset reset to 0 (for new searches).
  QuestionBankFilter resetOffset() => copyWith(offset: 0);
}

/// Paginated result from the question bank.
class QuestionBankPage {
  const QuestionBankPage({
    required this.items,
    required this.total,
    required this.offset,
    required this.pageSize,
  });

  final List<QuestionBankItem> items;
  final int total;
  final int offset;
  final int pageSize;

  bool get hasMore => offset + items.length < total;
  int get nextPageOffset => offset + pageSize;
}
