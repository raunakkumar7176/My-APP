// Unified Content-to-Test V1 — Phase 1/26: camera pages must converge into
// the SAME ExtractedContent -> detectQuestions -> review pipeline as
// PDF/DOCX/XLSX, never a second detection engine; and Phase 21: AI
// generation grounding (sourceText) plumbing.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/extracted_content.dart';
import 'package:my_praperation/core/services/document_service.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/screens/ai_generation_screen.dart';
import 'package:my_praperation/features/test/state/document_upload_controller.dart';

class _StubDocumentService implements DocumentService {
  ExtractedContent? nextImageContent;
  List<DetectedQuestion> detectResult = const [];
  final List<String> calls = [];

  @override
  Future<PickedFile> pickDocument() async => throw UnimplementedError();

  @override
  Future<PickedFile> pickImage() async => throw UnimplementedError();

  @override
  void validateFile(PickedFile file) {}

  @override
  Future<UploadedDocumentRecord> uploadFile({required PickedFile file, String? groupId}) async =>
  Future<UploadedDocumentRecord> uploadFile({
    required PickedFile file,
    String? groupId,
    bool isEphemeral = true,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteDocument(UploadedDocumentRecord doc) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteDocument(UploadedDocumentRecord doc) async => throw UnimplementedError();
  @override
  Future<void> purgeEphemeralDocument(UploadedDocumentRecord doc) async {}

  @override
  Future<List<UploadedDocumentRecord>> listMyDocuments() async => throw UnimplementedError();
  @override
  Future<int> purgeStaleEphemeralDocuments({int maxAgeMinutes = 120}) async =>
      0;

  @override
  Future<List<UploadedDocumentRecord>> listMyDocuments() async =>
      throw UnimplementedError();

  @override
  Future<int> cleanupOrphanedStorage() async => throw UnimplementedError();

  @override
  Future<ExtractedContent> extractContent(UploadedDocumentRecord doc) async =>
      throw UnimplementedError();

  @override
  ExtractedContent extractFromBytes(Uint8List bytes, String fileName) => throw UnimplementedError();
  @override
  ExtractedContent extractFromBytes(Uint8List bytes, String fileName) =>
      throw UnimplementedError();

  @override
  ExtractedContent extractFromImages(List<Uint8List> pages) {
    calls.add('extractFromImages:${pages.length}');
    return nextImageContent ??
        SupabaseDocumentService().extractFromImages(pages);
  }

  @override
  List<DetectedQuestion> detectQuestions(ExtractedContent content) {
    calls.add('detectQuestions:${content.sourceFormat.name}');
    return detectResult;
  }

  @override
  IngestionDetectionResult detectQuestionsWithConfidence(
    ExtractedContent content,
  ) {
    calls.add('detectQuestionsWithConfidence:${content.sourceFormat.name}');
    final questions = detectQuestions(content);
    return IngestionDetectionResult(
      questions: questions,
      confidence: IngestionConfidence(
        totalDetected: questions.length,
        validCount: questions.where((q) => q.hasValidStructure).length,
        withAnswerCount: questions.where((q) => q.hasCorrectAnswer).length,
        score: questions.isNotEmpty ? 1.0 : 0.0,
        isHighConfidence: questions.length >= 2,
      ),
    );
  }
}

void main() {
  group('DocumentService.extractFromImages (real implementation)', () {
    final service = SupabaseDocumentService();

    test('one block per page, camera format, no fabricated text', () {
      final pages = [Uint8List(10), Uint8List(10), Uint8List(10)];
      final content = service.extractFromImages(pages);

      expect(content.sourceFormat, DocumentFormat.camera);
      expect(content.totalPages, 3);
      expect(content.blocks.length, 3);
      expect(content.blocks[0].sourceLocation, 'Page 1');
      expect(content.blocks[2].sourceLocation, 'Page 3');
      for (final b in content.blocks) {
        expect(b.text, isEmpty, reason: 'no OCR — never invent text');
      }
    });

    test('empty page list is refused, not silently accepted', () {
      expect(() => service.extractFromImages([]), throwsA(isA<ValidationError>()));
      expect(
        () => service.extractFromImages([]),
        throwsA(isA<ValidationError>()),
      );
    });

    test('detectQuestions on camera-sourced content finds nothing (honest, not guessed)', () {
      final content = service.extractFromImages([Uint8List(5)]);
      expect(service.detectQuestions(content), isEmpty);
    });
  });

  group('DocumentUploadController.parseImages — shared pipeline entry point', () {
    test('camera pages flow through the exact same state machine as a file', () async {
      final stub = _StubDocumentService();
      final controller = DocumentUploadController(documentService: stub);
  group(
    'DocumentUploadController.parseImages — shared pipeline entry point',
    () {
      test(
        'camera pages flow through the exact same state machine as a file',
        () async {
          final stub = _StubDocumentService();
          final controller = DocumentUploadController(documentService: stub);

      await controller.parseImages([Uint8List(10), Uint8List(10)]);
          await controller.parseImages([Uint8List(10), Uint8List(10)]);

      expect(controller.state, DocumentFlowState.parsed);
      expect(controller.extractedContent!.sourceFormat, DocumentFormat.camera);
      expect(stub.calls, ['extractFromImages:2', 'detectQuestions:camera']);
      controller.dispose();
    });
          expect(controller.state, DocumentFlowState.parsed);
          expect(
            controller.extractedContent!.sourceFormat,
            DocumentFormat.camera,
          );
          expect(stub.calls, ['extractFromImages:2', 'detectQuestions:camera']);
          controller.dispose();
        },
      );

    test('an empty page list surfaces a clear error instead of a blank screen', () async {
      final controller = DocumentUploadController(documentService: _StubDocumentService());
      await controller.parseImages([]);
      expect(controller.state, DocumentFlowState.error);
      expect(controller.errorMessage, isNotNull);
      controller.dispose();
    });
      test(
        'an empty page list surfaces a clear error instead of a blank screen',
        () async {
          final controller = DocumentUploadController(
            documentService: _StubDocumentService(),
          );
          await controller.parseImages([]);
          expect(controller.state, DocumentFlowState.error);
          expect(controller.errorMessage, isNotNull);
          controller.dispose();
        },
      );

    test('addManualQuestion lets the creator add a question with zero auto-detection (camera path)', () async {
      final stub = _StubDocumentService()..detectResult = const [];
      final controller = DocumentUploadController(documentService: stub);
      await controller.parseImages([Uint8List(10)]);
      controller.startReview();
      test('addManualQuestion lets the creator add a question with zero auto-detection (camera path)', () async {
        final stub = _StubDocumentService()..detectResult = const [];
        final controller = DocumentUploadController(documentService: stub);
        await controller.parseImages([Uint8List(10)]);
        controller.startReview();

      expect(controller.detectedQuestions, isEmpty);
        expect(controller.detectedQuestions, isEmpty);

      controller.addManualQuestion(
        const QuestionDraft(
          questionText: 'What is shown on page 1?',
          options: [
            QuestionOptionDraft(text: 'A'),
            QuestionOptionDraft(text: 'B'),
            QuestionOptionDraft(text: 'C'),
            QuestionOptionDraft(text: 'D'),
          ],
          correctOptionIndex: 0,
        ),
      );
        controller.addManualQuestion(
          const QuestionDraft(
            questionText: 'What is shown on page 1?',
            options: [
              QuestionOptionDraft(text: 'A'),
              QuestionOptionDraft(text: 'B'),
              QuestionOptionDraft(text: 'C'),
              QuestionOptionDraft(text: 'D'),
            ],
            correctOptionIndex: 0,
          ),
        );

      expect(controller.detectedQuestions, hasLength(1));
      expect(controller.selectedIndices, [0]);
      expect(controller.readyDrafts.single.questionText, 'What is shown on page 1?');
      expect(controller.validateSelected(), isEmpty, reason: 'a complete manual draft is immediately valid');
      controller.dispose();
    });
  });
        expect(controller.detectedQuestions, hasLength(1));
        expect(controller.selectedIndices, [0]);
        expect(
          controller.readyDrafts.single.questionText,
          'What is shown on page 1?',
        );
        expect(
          controller.validateSelected(),
          isEmpty,
          reason: 'a complete manual draft is immediately valid',
        );
        controller.dispose();
      });
    },
  );

  group('AiGenerationPrefill — source grounding (Phase 21)', () {
    test('carries sourceText/sourceLabel through unchanged', () {
      const prefill = AiGenerationPrefill(
        subject: 'Science',
        sourceText: 'Photosynthesis is the process by which plants...',
        sourceLabel: 'notes.pdf',
      );
      expect(prefill.sourceText, contains('Photosynthesis'));
      expect(prefill.sourceLabel, 'notes.pdf');
    });

    test('a plain topic-only prefill has no source text (unaffected, per Phase 25 cost control)', () {
      const prefill = AiGenerationPrefill(subject: 'Science', topic: 'Light');
      expect(prefill.sourceText, isNull);
      expect(prefill.sourceLabel, isNull);
    });
  });
}
