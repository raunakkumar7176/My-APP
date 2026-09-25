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

  bool get mayContainQuestion =>
      isQuestionLike || blockType == ContentType.question;
  bool get isEmpty => text.trim().isEmpty;
}

enum DocumentFormat { pdf, docx, xlsx, doc, txt, image, camera }

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
    this.confidence = 0.9,
    this.status = 'VALID',
  });

  final String questionText;
  final List<String> options;
  final String sourceLocation;
  final DocumentFormat sourceFormat;
  final int? detectedCorrectIndex;
  final String? explanation;
  final int? questionNumber;
  final double confidence;
  final String status;

  bool get hasValidStructure =>
      questionText.trim().isNotEmpty && options.length >= 2;

  bool get hasCorrectAnswer => detectedCorrectIndex != null;

  /// Convert to a QuestionDraft for the existing test creation flow.
  QuestionDraft toDraft({int marks = 1, String? explanation}) {
    return QuestionDraft(
      questionText: questionText,
      options: [for (final o in options) QuestionOptionDraft(text: o)],
      correctOptionIndex: detectedCorrectIndex,
      explanation: explanation ?? this.explanation,
      marks: marks,
    );
  }
}

/// Represents the confidence and quality metrics of deterministic document ingestion.
final class IngestionConfidence {
  const IngestionConfidence({
    required this.totalDetected,
    required this.validCount,
    required this.withAnswerCount,
    required this.score,
    required this.isHighConfidence,
    this.reason,
  });

  final int totalDetected;
  final int validCount;
  final int withAnswerCount;
  final double score; // 0.0 to 1.0 (validCount / totalDetected)
  final bool isHighConfidence;
  final String? reason;

  static const zero = IngestionConfidence(
    totalDetected: 0,
    validCount: 0,
    withAnswerCount: 0,
    score: 0.0,
    isHighConfidence: false,
    reason: 'No questions detected',
  );
}

/// Result of deterministic question detection including confidence and provenance.
final class IngestionDetectionResult {
  const IngestionDetectionResult({
    required this.questions,
    required this.confidence,
    this.answersDetected = 0,
    this.noiseLinesFiltered = 0,
    this.rawCharacterCount = 0,
  });

  final List<DetectedQuestion> questions;
  final IngestionConfidence confidence;
  final int answersDetected;
  final int noiseLinesFiltered;
  final int rawCharacterCount;
}
