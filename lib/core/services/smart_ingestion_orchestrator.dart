import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../features/test/data/ai_generation_repository.dart';
import '../../features/test/models/question_draft.dart';
import '../logging/app_logger.dart';
import '../models/extracted_content.dart';
import 'document_service.dart';

/// Source of ingested questions: deterministic zero-token extraction vs Gemini AI synthesis.
enum SmartIngestionSource { deterministic, aiFallback }

/// Lifecycle stages during smart ingestion for real-time progress indicators.
enum SmartIngestionStage {
  extracting,
  analyzing,
  deterministicSuccess,
  routingToAi,
  aiGenerating,
  completed,
  failed,
}

/// Progress event emitted during smart document ingestion.
class SmartIngestionEvent {
  const SmartIngestionEvent({
    required this.stage,
    required this.message,
    this.progress,
  });

  final SmartIngestionStage stage;
  final String message;
  final double? progress;

  @override
  String toString() =>
      'SmartIngestionEvent(stage: $stage, progress: $progress, message: $message)';
}

/// Final result produced by [SmartIngestionOrchestrator].
class SmartIngestionResult {
  const SmartIngestionResult({
    required this.source,
    required this.questions,
    required this.confidence,
    required this.extractedText,
    required this.tokensUsed,
    this.aiSummary,
    this.reason,
    this.rawContent,
  });

  final SmartIngestionSource source;
  final List<QuestionDraft> questions;
  final IngestionConfidence confidence;
  final String extractedText;
  final int tokensUsed;
  final AiGenerationSummary? aiSummary;
  final String? reason;
  final ExtractedContent? rawContent;

  bool get isDeterministic => source == SmartIngestionSource.deterministic;
  bool get isAiGenerated => source == SmartIngestionSource.aiFallback;
  int get questionCount => questions.length;
}

/// Orchestrates smart document ingestion with deterministic MCQ preference and
/// automatic fallback to Gemini AI for theory/unstructured study material.
///
/// Execution Strategy:
/// 1. Extract content from document bytes or uploaded records (PDF/DOCX/TXT/Images).
/// 2. Run deterministic detection (with noise filtering and answer key pairing):
///    - If >= 2 valid questions are detected with high confidence: Return questions
///      immediately with zero AI token consumption.
///    - If text is readable (>150 characters) but 0 or low-confidence questions exist:
///      Route to Gemini AI generation pipeline using extracted text as `sourceText`.
///    - Otherwise, return low-confidence/empty result honestly for creator manual editing.
class SmartIngestionOrchestrator {
  SmartIngestionOrchestrator({
    DocumentService? documentService,
    AiGenerationRepository? aiRepository,
  }) : _docService = documentService ?? SupabaseDocumentService(),
       _aiRepo = aiRepository ?? const AiGenerationRepository();

  final DocumentService _docService;
  final AiGenerationRepository _aiRepo;

  /// Process in-memory document bytes directly.
  Future<SmartIngestionResult> processBytes({
    required Uint8List bytes,
    required String fileName,
    String? subject,
    String? topic,
    String? chapter,
    int targetQuestionCount = 5,
    String difficulty = 'medium',
    String language = 'en',
    void Function(SmartIngestionEvent)? onProgress,
  }) async {
    onProgress?.call(
      const SmartIngestionEvent(
        stage: SmartIngestionStage.extracting,
        message: 'Extracting content from file...',
        progress: 0.15,
      ),
    );

    final content = _docService.extractFromBytes(bytes, fileName);
    return _analyzeAndRoute(
      content: content,
      fileName: fileName,
      subject: subject,
      topic: topic,
      chapter: chapter,
      targetQuestionCount: targetQuestionCount,
      difficulty: difficulty,
      language: language,
      onProgress: onProgress,
    );
  }

  /// Process an uploaded document record from Supabase Storage.
  Future<SmartIngestionResult> processUploadedDocument({
    required UploadedDocumentRecord doc,
    String? subject,
    String? topic,
    String? chapter,
    int targetQuestionCount = 5,
    String difficulty = 'medium',
    String language = 'en',
    void Function(SmartIngestionEvent)? onProgress,
  }) async {
    onProgress?.call(
      const SmartIngestionEvent(
        stage: SmartIngestionStage.extracting,
        message: 'Downloading and reading document...',
        progress: 0.15,
      ),
    );

    final content = await _docService.extractContent(doc);
    return _analyzeAndRoute(
      content: content,
      fileName: doc.fileName,
      subject: subject,
      topic: topic,
      chapter: chapter,
      targetQuestionCount: targetQuestionCount,
      difficulty: difficulty,
      language: language,
      onProgress: onProgress,
    );
  }

  /// Evaluates extracted content and decides whether to accept deterministic MCQs
  /// or route to Gemini AI.
  Future<SmartIngestionResult> _analyzeAndRoute({
    required ExtractedContent content,
    required String fileName,
    String? subject,
    String? topic,
    String? chapter,
    required int targetQuestionCount,
    required String difficulty,
    required String language,
    void Function(SmartIngestionEvent)? onProgress,
  }) async {
    onProgress?.call(
      const SmartIngestionEvent(
        stage: SmartIngestionStage.analyzing,
        message: 'Analyzing document structure for MCQs...',
        progress: 0.35,
      ),
    );

    // Step 2: Deterministic detection pass
    final detection = _docService.detectQuestionsWithConfidence(content);
    final validQuestions = detection.questions
        .where((q) => q.hasValidStructure)
        .toList();
    final allText = content.blocks.map((b) => b.text).join('\n').trim();

    AppLogger.info(
      'SmartIngestion analysis for "$fileName": '
      'validCount=${validQuestions.length}, '
      'isHighConfidence=${detection.confidence.isHighConfidence}, '
      'textLength=${allText.length}',
    );

    // Branch A: Deterministic High-Confidence MCQ Match
    // If >= 2 valid questions detected with high confidence -> Return immediately (Zero AI tokens used).
    if (validQuestions.length >= 2 && detection.confidence.isHighConfidence) {
      onProgress?.call(
        SmartIngestionEvent(
          stage: SmartIngestionStage.deterministicSuccess,
          message:
              'Found ${validQuestions.length} MCQs deterministically (0 AI tokens used)',
          progress: 1.0,
        ),
      );

      final drafts = detection.questions.map((q) => q.toDraft()).toList();
      return SmartIngestionResult(
        source: SmartIngestionSource.deterministic,
        questions: drafts,
        confidence: detection.confidence,
        extractedText: allText,
        tokensUsed: 0,
        reason:
            'Deterministic engine detected ${drafts.length} MCQs with high confidence (${(detection.confidence.score * 100).toInt()}%). Zero AI tokens consumed.',
        rawContent: content,
      );
    }

    // Branch B: Theory Reading / Low-Confidence Questions -> Route to Gemini AI
    // If text is readable (>150 characters) but 0 or low-confidence questions exist.
    if (allText.length > 150) {
      onProgress?.call(
        const SmartIngestionEvent(
          stage: SmartIngestionStage.routingToAi,
          message: 'Document contains theory/study material. Routing to Gemini AI...',
          progress: 0.55,
        ),
      );

      onProgress?.call(
        SmartIngestionEvent(
          stage: SmartIngestionStage.aiGenerating,
          message:
              'Gemini AI generating $targetQuestionCount questions from text...',
          progress: 0.75,
        ),
      );

      try {
        final resolvedTopic =
            topic ??
            (chapter?.isNotEmpty == true
                ? chapter!
                : p.basenameWithoutExtension(fileName));

        final aiResult = await _aiRepo.generateQuestions(
          subject: subject ?? 'General',
          topic: resolvedTopic,
          chapter: chapter,
          questionCount: targetQuestionCount,
          difficulty: difficulty,
          language: language,
          sourceText: allText.length > 25000
              ? allText.substring(0, 25000)
              : allText,
          title: fileName,
        );

        final drafts = aiResult.questions
            .map((q) => q.toQuestionDraft(marks: 1))
            .toList();

        onProgress?.call(
          SmartIngestionEvent(
            stage: SmartIngestionStage.completed,
            message:
                'Generated ${drafts.length} questions from text via Gemini AI',
            progress: 1.0,
          ),
        );

        return SmartIngestionResult(
          source: SmartIngestionSource.aiFallback,
          questions: drafts,
          confidence: detection.confidence,
          extractedText: allText,
          tokensUsed: aiResult.tokensIn + aiResult.tokensOut,
          aiSummary: aiResult.summary,
          reason:
              'Low MCQ structure detected (${detection.questions.length} candidates). Routed to Gemini AI for theory comprehension.',
          rawContent: content,
        );
      } catch (e) {
        onProgress?.call(
          SmartIngestionEvent(
            stage: SmartIngestionStage.failed,
            message: 'AI Generation failed: $e',
            progress: 1.0,
          ),
        );
        rethrow;
      }
    }

    // Branch C: Insufficient readable text (< 150 chars) and no/low questions
    onProgress?.call(
      const SmartIngestionEvent(
        stage: SmartIngestionStage.completed,
        message: 'Document processing complete',
        progress: 1.0,
      ),
    );

    final drafts = detection.questions.map((q) => q.toDraft()).toList();
    return SmartIngestionResult(
      source: SmartIngestionSource.deterministic,
      questions: drafts,
      confidence: detection.confidence,
      extractedText: allText,
      tokensUsed: 0,
      reason: drafts.isEmpty
          ? 'No questions found and document text is too short for AI comprehension (${allText.length} characters).'
          : 'Found ${drafts.length} question(s) with low confidence.',
      rawContent: content,
    );
  }
}
