import '../../features/test/models/question_draft.dart';

/// Represents the full extracted content from a document.
///
/// Contains structured content blocks parsed from PDF/DOCX/XLSX,
/// with enough metadata to trace questions back to their source.
final class ExtractedContent {
  const ExtractedContent({
    required this.blocks,
    required this.sourceFormat,
    this.totalPages,
    this.totalSheets,
  });

  final List<ContentBlock> blocks;
  final DocumentFormat sourceFormat;
  final int? totalPages;
  final int? totalSheets;

  int get blockCount => blocks.length;

  /// All blocks that look like they contain questions.
  List<ContentBlock> get questionLikeBlocks =>
      blocks.where((b) => b.mayContainQuestion).toList();
}

/// A single block of extracted content (page, sheet, section, or row).
final class ContentBlock {
  const ContentBlock({
    required this.text,
    required this.sourceLocation,
    this.blockType = ContentType.unknown,
    this.isQuestionLike = false,
  });

  final String text;
  final String sourceLocation;
  final ContentType blockType;
  final bool isQuestionLike;

  bool get mayContainQuestion => isQuestionLike || blockType == ContentType.question;
  bool get isEmpty => text.trim().isEmpty;
}

enum DocumentFormat { pdf, docx, xlsx }

enum ContentType {
  unknown,
  question,
  option,
  header,
  table,
  paragraph,
  sheet,
  row,
}

/// A question detected from document content.
///
/// This is an intermediate representation before becoming a QuestionDraft.
/// It carries source provenance information.
final class DetectedQuestion {
  const DetectedQuestion({
    required this.questionText,
    this.options = const [],
    this.sourceLocation = '',
    this.sourceFormat = DocumentFormat.pdf,
    this.detectedCorrectIndex,
    this.explanation,
    this.questionNumber,
  });

  final String questionText;
  final List<String> options;
  final String sourceLocation;
  final DocumentFormat sourceFormat;
  final int? detectedCorrectIndex;
  final String? explanation;
  final int? questionNumber;

  bool get hasValidStructure =>
      questionText.trim().isNotEmpty && options.length >= 2;

  bool get hasCorrectAnswer => detectedCorrectIndex != null;

  /// Convert to a QuestionDraft for the existing test creation flow.
  QuestionDraft toDraft({
    int marks = 1,
    String? explanation,
  }) {
    return QuestionDraft(
      questionText: questionText,
      options: [
        for (final o in options) QuestionOptionDraft(text: o),
      ],
      correctOptionIndex: detectedCorrectIndex,
      explanation: explanation ?? this.explanation,
      marks: marks,
    );
  }
}
