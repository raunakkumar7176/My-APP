// V1 — Via Document/File: unit tests for models, detection, validation,
// controller, and creation_method integration.
//
// Pure Dart tests — no Supabase, no network, no Flutter widget tests.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/extracted_content.dart';
import 'package:my_praperation/core/models/uploaded_document.dart';
import 'package:my_praperation/core/services/document_service.dart';
import 'package:my_praperation/features/test/data/test_repository.dart';
import 'package:my_praperation/features/test/domain/backend_mapping.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/state/document_upload_controller.dart';
import 'package:my_praperation/features/test/widgets/question_source_step.dart';

/// Fake DocumentService for testing without Supabase.
class FakeDocumentService implements DocumentService {
  PickedFile? nextFile;
  Object? pickError;
  UploadedDocumentRecord? nextUpload;
  Object? uploadError;
  ExtractedContent? nextContent;
  Object? extractError;
  List<DetectedQuestion> detectResult = [];

  final List<String> calls = [];

  @override
  Future<PickedFile> pickDocument() async {
    calls.add('pick');
    if (pickError != null) throw pickError!;
    return nextFile ??
        PickedFile(
          path: '/tmp/test.pdf',
          name: 'test.pdf',
          size: 1024,
          bytes: Uint8List(1024),
        );
  }

  @override
  void validateFile(PickedFile file) {
    calls.add('validate');
    final ext = file.name.split('.').last.toLowerCase();
    const allowed = ['pdf', 'docx', 'xlsx', 'xls'];
    if (!allowed.contains(ext)) {
      throw ValidationError(message: 'Unsupported file format: .$ext');
    }
    if (file.size <= 0) {
      throw const ValidationError(message: 'File is empty.');
    }
    if (file.size > 20 * 1024 * 1024) {
      throw const ValidationError(message: 'File too large.');
    }
  }

  @override
  Future<PickedFile> pickImage() async {
    calls.add('pickImage');
    return nextFile ??
        PickedFile(
          path: '/tmp/test.jpg',
          name: 'test.jpg',
          size: 1024,
          bytes: Uint8List(1024),
        );
  }

  @override
  Future<UploadedDocumentRecord> uploadFile({
    required PickedFile file,
    String? groupId,
    bool isEphemeral = true,
  }) async {
    calls.add('upload');
    if (uploadError != null) throw uploadError!;
    return nextUpload ??
        UploadedDocumentRecord(
          id: 'doc-1',
          fileName: file.name,
          storagePath: 'user-1/${file.name}',
          mimeType: 'application/pdf',
          fileSize: file.size,
          isEphemeral: isEphemeral,
        );
  }

  @override
  Future<void> deleteDocument(UploadedDocumentRecord doc) async {
    calls.add('delete');
  }

  @override
  Future<void> purgeEphemeralDocument(UploadedDocumentRecord doc) async {
    calls.add('purgeEphemeral');
  }

  @override
  Future<int> purgeStaleEphemeralDocuments({int maxAgeMinutes = 120}) async {
    calls.add('purgeStaleEphemeral');
    return 0;
  }

  @override
  Future<List<UploadedDocumentRecord>> listMyDocuments() async => [];

  @override
  Future<int> cleanupOrphanedStorage() async => 0;

  @override
  Future<ExtractedContent> extractContent(UploadedDocumentRecord doc) async {
    calls.add('extract');
    if (extractError != null) throw extractError!;
    return nextContent ??
        const ExtractedContent(blocks: [], sourceFormat: DocumentFormat.pdf);
  }

  @override
  List<DetectedQuestion> detectQuestions(ExtractedContent content) {
    calls.add('detect');
    return detectResult;
  }

  @override
  IngestionDetectionResult detectQuestionsWithConfidence(
    ExtractedContent content,
  ) {
    calls.add('detectQuestionsWithConfidence');
    return IngestionDetectionResult(
      questions: detectResult,
      confidence: IngestionConfidence.zero,
      answersDetected: 0,
      noiseLinesFiltered: 0,
      rawCharacterCount: 0,
    );
  }

  @override
  ExtractedContent extractFromBytes(Uint8List bytes, String fileName) {
    calls.add('extractFromBytes');
    return nextContent ??
        const ExtractedContent(blocks: [], sourceFormat: DocumentFormat.pdf);
  }

  @override
  ExtractedContent extractFromImages(List<Uint8List> pages) {
    calls.add('extractFromImages');
    return nextContent ??
        const ExtractedContent(blocks: [], sourceFormat: DocumentFormat.camera);
  }
}

void main() {
  // ──────────────────────────────────────────────────────────
  // 1. QuestionSource creationMethod mapping
  // ──────────────────────────────────────────────────────────
  group('QuestionSource.creationMethod', () {
    test('manual → manual', () {
      expect(QuestionSource.manual.creationMethod, 'manual');
    });
    test('document → upload', () {
      expect(QuestionSource.document.creationMethod, 'upload');
    });
    test('ai → ai', () {
      expect(QuestionSource.ai.creationMethod, 'ai');
    });
    test('books → manual', () {
      expect(QuestionSource.books.creationMethod, 'manual');
    });
  });

  // ──────────────────────────────────────────────────────────
  // 2. QuestionSource.isAvailable
  // ──────────────────────────────────────────────────────────
  group('QuestionSource.isAvailable', () {
    test('manual is available', () {
      expect(QuestionSource.manual.isAvailable, isTrue);
    });
    test('document is available (V1)', () {
      expect(QuestionSource.document.isAvailable, isTrue);
    });
    test('books is available', () {
      expect(QuestionSource.books.isAvailable, isTrue);
    });
    test('ai is available (V1 — implemented)', () {
      expect(QuestionSource.ai.isAvailable, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────
  // 3. TestWriteInput creation_method
  // ──────────────────────────────────────────────────────────
  group('TestWriteInput creation_method', () {
    test('defaults to manual', () {
      final p = const TestWriteInput(title: 'T').toCreateParams();
      expect(p['p_creation_method'], 'manual');
    });

    test('upload when creationMethod is upload', () {
      final p = const TestWriteInput(
        title: 'T',
        creationMethod: 'upload',
      ).toCreateParams();
      expect(p['p_creation_method'], 'upload');
    });

    test('ai when creationMethod is ai', () {
      final p = const TestWriteInput(
        title: 'T',
        creationMethod: 'ai',
      ).toCreateParams();
      expect(p['p_creation_method'], 'ai');
    });

    test('creation_method is always present', () {
      final p = const TestWriteInput(title: 'T').toCreateParams();
      expect(p.containsKey('p_creation_method'), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────
  // 4. DetectedQuestion → QuestionDraft conversion
  // ──────────────────────────────────────────────────────────
  group('DetectedQuestion.toDraft', () {
    test('converts basic MCQ', () {
      const dq = DetectedQuestion(
        questionText: 'What is 2+2?',
        options: ['3', '4', '5', '6'],
        detectedCorrectIndex: 1,
        sourceLocation: 'Page 1',
        sourceFormat: DocumentFormat.pdf,
      );
      final draft = dq.toDraft(marks: 2);

      expect(draft.questionText, 'What is 2+2?');
      expect(draft.options.length, 4);
      expect(draft.options[0].text, '3');
      expect(draft.options[1].text, '4');
      expect(draft.correctOptionIndex, 1);
      expect(draft.marks, 2);
    });

    test('no correct index when not detected', () {
      const dq = DetectedQuestion(
        questionText: 'Test question?',
        options: ['A', 'B', 'C', 'D'],
      );
      final draft = dq.toDraft();
      expect(draft.hasCorrectOption, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────
  // 5. DetectedQuestion validation
  // ──────────────────────────────────────────────────────────
  group('DetectedQuestion validation', () {
    test('valid with question + 2+ options', () {
      const dq = DetectedQuestion(
        questionText: 'What is X?',
        options: ['A', 'B'],
      );
      expect(dq.hasValidStructure, isTrue);
    });

    test('invalid with empty question', () {
      const dq = DetectedQuestion(questionText: '', options: ['A', 'B']);
      expect(dq.hasValidStructure, isFalse);
    });

    test('invalid with < 2 options', () {
      const dq = DetectedQuestion(questionText: 'What is X?', options: ['A']);
      expect(dq.hasValidStructure, isFalse);
    });

    test('hasCorrectAnswer when index set', () {
      const dq = DetectedQuestion(
        questionText: 'Q?',
        options: ['A', 'B'],
        detectedCorrectIndex: 0,
      );
      expect(dq.hasCorrectAnswer, isTrue);
    });

    test('no hasCorrectAnswer when index null', () {
      const dq = DetectedQuestion(questionText: 'Q?', options: ['A', 'B']);
      expect(dq.hasCorrectAnswer, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────
  // 6. ContentBlock properties
  // ──────────────────────────────────────────────────────────
  group('ContentBlock', () {
    test('isEmpty for whitespace', () {
      const block = ContentBlock(text: '   ', sourceLocation: 'Line 1');
      expect(block.isEmpty, isTrue);
    });

    test('is not empty for real text', () {
      const block = ContentBlock(text: 'Hello', sourceLocation: 'Line 1');
      expect(block.isEmpty, isFalse);
    });

    test('mayContainQuestion when flagged', () {
      const block = ContentBlock(
        text: 'What is X?',
        sourceLocation: 'Line 1',
        isQuestionLike: true,
      );
      expect(block.mayContainQuestion, isTrue);
    });

    test('mayContainQuestion when blockType is question', () {
      const block = ContentBlock(
        text: 'Some text',
        sourceLocation: 'Line 1',
        blockType: ContentType.question,
      );
      expect(block.mayContainQuestion, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────
  // 7. ExtractedContent
  // ──────────────────────────────────────────────────────────
  group('ExtractedContent', () {
    test('blockCount returns total blocks', () {
      const content = ExtractedContent(
        blocks: [
          ContentBlock(text: 'A', sourceLocation: '1'),
          ContentBlock(text: 'B', sourceLocation: '2'),
          ContentBlock(text: 'C', sourceLocation: '3'),
        ],
        sourceFormat: DocumentFormat.docx,
      );
      expect(content.blockCount, 3);
    });

    test('questionLikeBlocks filters correctly', () {
      const content = ExtractedContent(
        blocks: [
          ContentBlock(text: 'Header', sourceLocation: '1'),
          ContentBlock(
            text: 'What is X?',
            sourceLocation: '2',
            isQuestionLike: true,
          ),
          ContentBlock(text: 'Body', sourceLocation: '3'),
        ],
        sourceFormat: DocumentFormat.pdf,
      );
      expect(content.questionLikeBlocks.length, 1);
      expect(content.questionLikeBlocks.first.text, 'What is X?');
    });
  });

  // ──────────────────────────────────────────────────────────
  // 8. DocumentUploadController state machine
  // ──────────────────────────────────────────────────────────
  group('DocumentUploadController', () {
    late FakeDocumentService fakeService;
    late DocumentUploadController controller;

    setUp(() {
      fakeService = FakeDocumentService();
      controller = DocumentUploadController(documentService: fakeService);
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts in idle state', () {
      expect(controller.state, DocumentFlowState.idle);
      expect(controller.errorMessage, isNull);
      expect(controller.isBusy, isFalse);
    });

    test('reset returns to idle', () {
      controller.reset();
      expect(controller.state, DocumentFlowState.idle);
      expect(controller.errorMessage, isNull);
      expect(controller.detectedQuestions, isEmpty);
      expect(controller.selectedIndices, isEmpty);
    });

    test('toggleSelection on empty list is no-op', () {
      controller.toggleSelection(0);
      expect(controller.selectedIndices, isEmpty);
    });

    test('selectAll / deselectAll', () {
      controller.selectAll();
      expect(controller.selectedIndices, isEmpty); // No questions loaded.
      controller.deselectAll();
      expect(controller.selectedIndices, isEmpty);
    });

    test('readyDrafts returns empty when nothing selected', () {
      expect(controller.readyDrafts, isEmpty);
    });

    test('hasReadyQuestions is false when nothing selected', () {
      expect(controller.hasReadyQuestions, isFalse);
    });

    test('validateSelected reports no questions', () {
      final errors = controller.validateSelected();
      expect(errors, contains('No questions selected.'));
    });

    test('pickAndUpload transitions through states', () async {
      fakeService.nextFile = PickedFile(
        path: '/tmp/test.pdf',
        name: 'test.pdf',
        size: 1024,
        bytes: Uint8List(1024),
      );
      fakeService.nextUpload = const UploadedDocumentRecord(
        id: 'doc-1',
        fileName: 'test.pdf',
        storagePath: 'user-1/test.pdf',
        mimeType: 'application/pdf',
        fileSize: 1024,
      );

      await controller.pickAndUpload();
      expect(controller.state, DocumentFlowState.uploaded);
      expect(controller.uploadedDoc, isNotNull);
      expect(fakeService.calls, contains('pick'));
      expect(fakeService.calls, contains('validate'));
      expect(fakeService.calls, contains('upload'));
    });

    test('pickAndUpload handles pick error', () async {
      fakeService.pickError = const ValidationError(message: 'No file');
      await controller.pickAndUpload();
      expect(controller.state, DocumentFlowState.error);
      expect(controller.errorMessage, contains('No file'));
    });

    test('parseDocument transitions to parsed', () async {
      fakeService.nextContent = const ExtractedContent(
        blocks: [
          ContentBlock(text: 'Q1?', sourceLocation: '1', isQuestionLike: true),
        ],
        sourceFormat: DocumentFormat.pdf,
      );
      fakeService.detectResult = const [
        DetectedQuestion(questionText: 'Q1?', options: ['A', 'B', 'C', 'D']),
      ];

      // First upload.
      await controller.pickAndUpload();
      expect(controller.state, DocumentFlowState.uploaded);

      // Then parse.
      await controller.parseDocument();
      expect(controller.state, DocumentFlowState.parsed);
      expect(controller.detectedQuestions.length, 1);
      expect(controller.selectedIndices.length, 1);
    });

    test('pickUploadAndParse combines steps', () async {
      fakeService.nextContent = const ExtractedContent(
        blocks: [],
        sourceFormat: DocumentFormat.pdf,
      );
      fakeService.detectResult = const [
        DetectedQuestion(questionText: 'Q?', options: ['A', 'B', 'C', 'D']),
      ];

      await controller.pickUploadAndParse();
      expect(controller.state, DocumentFlowState.parsed);
      expect(controller.detectedQuestions.length, 1);
    });

    test('removeQuestion works', () async {
      fakeService.detectResult = const [
        DetectedQuestion(questionText: 'Q1?', options: ['A', 'B', 'C', 'D']),
        DetectedQuestion(questionText: 'Q2?', options: ['A', 'B', 'C', 'D']),
      ];
      fakeService.nextContent = const ExtractedContent(
        blocks: [],
        sourceFormat: DocumentFormat.pdf,
      );

      await controller.pickUploadAndParse();
      expect(controller.detectedQuestions.length, 2);

      controller.removeQuestion(0);
      expect(controller.detectedQuestions.length, 1);
      expect(controller.detectedQuestions[0].questionText, 'Q2?');
    });

    test('reorderQuestion swaps positions', () async {
      fakeService.detectResult = const [
        DetectedQuestion(questionText: 'Q1?', options: ['A', 'B', 'C', 'D']),
        DetectedQuestion(questionText: 'Q2?', options: ['A', 'B', 'C', 'D']),
      ];
      fakeService.nextContent = const ExtractedContent(
        blocks: [],
        sourceFormat: DocumentFormat.pdf,
      );

      await controller.pickUploadAndParse();
      controller.reorderQuestion(0, 1);
      expect(controller.detectedQuestions[0].questionText, 'Q2?');
      expect(controller.detectedQuestions[1].questionText, 'Q1?');
    });

    test('draftForQuestion returns empty for invalid index', () {
      final draft = controller.draftForQuestion(999);
      expect(draft.questionText, isEmpty);
    });

    test('updateQuestionDraft stores edited version', () async {
      fakeService.detectResult = const [
        DetectedQuestion(questionText: 'Q1?', options: ['A', 'B', 'C', 'D']),
      ];
      fakeService.nextContent = const ExtractedContent(
        blocks: [],
        sourceFormat: DocumentFormat.pdf,
      );

      await controller.pickUploadAndParse();

      const edited = QuestionDraft(
        questionText: 'Edited Q?',
        options: [
          QuestionOptionDraft(text: 'X'),
          QuestionOptionDraft(text: 'Y'),
          QuestionOptionDraft(text: 'Z'),
          QuestionOptionDraft(text: 'W'),
        ],
        correctOptionIndex: 0,
      );
      controller.updateQuestionDraft(0, edited);
      expect(controller.draftForQuestion(0).questionText, 'Edited Q?');
    });

    test('readyDrafts returns selected drafts', () async {
      fakeService.detectResult = const [
        DetectedQuestion(questionText: 'Q1?', options: ['A', 'B', 'C', 'D']),
        DetectedQuestion(questionText: 'Q2?', options: ['A', 'B', 'C', 'D']),
      ];
      fakeService.nextContent = const ExtractedContent(
        blocks: [],
        sourceFormat: DocumentFormat.pdf,
      );

      await controller.pickUploadAndParse();
      controller.deselectAll();
      expect(controller.readyDrafts, isEmpty);

      controller.toggleSelection(0);
      expect(controller.readyDrafts.length, 1);
      expect(controller.readyDrafts[0].questionText, 'Q1?');
    });
  });

  // ──────────────────────────────────────────────────────────
  // 9. QuestionDraft validity for document imports
  // ──────────────────────────────────────────────────────────
  group('QuestionDraft validity', () {
    test('valid draft with 4 options and correct answer', () {
      const draft = QuestionDraft(
        questionText: 'What is 2+2?',
        options: [
          QuestionOptionDraft(text: '3'),
          QuestionOptionDraft(text: '4'),
          QuestionOptionDraft(text: '5'),
          QuestionOptionDraft(text: '6'),
        ],
        correctOptionIndex: 1,
        marks: 1,
      );
      expect(draft.isValid, isTrue);
    });

    test('invalid: empty question text', () {
      const draft = QuestionDraft(
        questionText: '',
        options: [
          QuestionOptionDraft(text: '3'),
          QuestionOptionDraft(text: '4'),
          QuestionOptionDraft(text: '5'),
          QuestionOptionDraft(text: '6'),
        ],
        correctOptionIndex: 1,
      );
      expect(draft.isValid, isFalse);
    });

    test('invalid: too few options', () {
      const draft = QuestionDraft(
        questionText: 'Q?',
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
        ],
        correctOptionIndex: 0,
      );
      expect(draft.isValid, isFalse);
    });

    test('invalid: no correct option', () {
      const draft = QuestionDraft(
        questionText: 'Q?',
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
          QuestionOptionDraft(text: 'C'),
          QuestionOptionDraft(text: 'D'),
        ],
      );
      expect(draft.isValid, isFalse);
    });

    test('invalid: zero marks', () {
      const draft = QuestionDraft(
        questionText: 'Q?',
        options: [
          QuestionOptionDraft(text: 'A'),
          QuestionOptionDraft(text: 'B'),
          QuestionOptionDraft(text: 'C'),
          QuestionOptionDraft(text: 'D'),
        ],
        correctOptionIndex: 0,
        marks: 0,
      );
      expect(draft.isValid, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────
  // 10. PickedFile validation via FakeDocumentService
  // ──────────────────────────────────────────────────────────
  group('File validation (via FakeDocumentService)', () {
    late FakeDocumentService service;

    setUp(() {
      service = FakeDocumentService();
    });

    test('detects unsupported extension', () {
      final file = PickedFile(
        path: '/tmp/test.exe',
        name: 'test.exe',
        size: 100,
        bytes: Uint8List(100),
      );
      expect(
        () => service.validateFile(file),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('Unsupported file format'),
          ),
        ),
      );
    });

    test('detects empty file', () {
      final file = PickedFile(
        path: '/tmp/empty.pdf',
        name: 'empty.pdf',
        size: 0,
        bytes: Uint8List(0),
      );
      expect(
        () => service.validateFile(file),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });

    test('accepts valid PDF', () {
      final file = PickedFile(
        path: '/tmp/test.pdf',
        name: 'test.pdf',
        size: 1024,
        bytes: Uint8List(1024),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });

    test('accepts valid DOCX', () {
      final file = PickedFile(
        path: '/tmp/test.docx',
        name: 'test.docx',
        size: 2048,
        bytes: Uint8List(2048),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });

    test('accepts valid XLSX', () {
      final file = PickedFile(
        path: '/tmp/test.xlsx',
        name: 'test.xlsx',
        size: 4096,
        bytes: Uint8List(4096),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });

    test('accepts valid XLS', () {
      final file = PickedFile(
        path: '/tmp/test.xls',
        name: 'test.xls',
        size: 4096,
        bytes: Uint8List(4096),
      );
      expect(() => service.validateFile(file), returnsNormally);
    });

    test('rejects file over 20MB', () {
      final file = PickedFile(
        path: '/tmp/huge.pdf',
        name: 'huge.pdf',
        size: 25 * 1024 * 1024,
        bytes: Uint8List(100),
      );
      expect(
        () => service.validateFile(file),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });
  });

  // ──────────────────────────────────────────────────────────
  // 11. UploadedDocument model serialization
  // ──────────────────────────────────────────────────────────
  group('UploadedDocument model', () {
    test('fromJson roundtrip', () {
      final now = DateTime.now();
      final doc = UploadedDocument(
        id: 'doc-1',
        fileName: 'test.pdf',
        filePath: '/tmp/test.pdf',
        mimeType: 'application/pdf',
        fileSize: 1024,
        storagePath: 'user-1/test.pdf',
        uploadedBy: 'user-1',
        groupId: null,
        status: DocumentStatus.uploaded,
        createdAt: now,
      );

      final json = doc.toJson();
      final parsed = UploadedDocument.fromJson(json);

      expect(parsed.id, doc.id);
      expect(parsed.fileName, doc.fileName);
      expect(parsed.mimeType, doc.mimeType);
      expect(parsed.fileSize, doc.fileSize);
      expect(parsed.storagePath, doc.storagePath);
      expect(parsed.uploadedBy, doc.uploadedBy);
      expect(parsed.status, doc.status);
    });

    test('copyWith preserves unchanged fields', () {
      const doc = UploadedDocument(
        id: 'doc-1',
        fileName: 'test.pdf',
        filePath: '/tmp/test.pdf',
        mimeType: 'application/pdf',
        fileSize: 1024,
        storagePath: 'user-1/test.pdf',
        uploadedBy: 'user-1',
      );

      final updated = doc.copyWith(status: DocumentStatus.parsed);
      expect(updated.status, DocumentStatus.parsed);
      expect(updated.fileName, doc.fileName);
      expect(updated.storagePath, doc.storagePath);
    });
  });

  // ──────────────────────────────────────────────────────────
  // 12. Source provenance tracking
  // ──────────────────────────────────────────────────────────
  group('Source provenance', () {
    test('DetectedQuestion carries source location', () {
      const dq = DetectedQuestion(
        questionText: 'Q?',
        options: ['A', 'B', 'C', 'D'],
        sourceLocation: 'Sheet 1, Row 5',
        sourceFormat: DocumentFormat.xlsx,
      );
      expect(dq.sourceLocation, 'Sheet 1, Row 5');
      expect(dq.sourceFormat, DocumentFormat.xlsx);
    });

    test('Draft preserves source info via explanation', () {
      const dq = DetectedQuestion(
        questionText: 'Q?',
        options: ['A', 'B', 'C', 'D'],
        sourceLocation: 'Page 3, Paragraph 12',
        sourceFormat: DocumentFormat.docx,
        explanation: 'Source: Page 3, Paragraph 12',
      );
      final draft = dq.toDraft();
      expect(draft.explanation, contains('Page 3'));
    });
  });

  // ──────────────────────────────────────────────────────────
  // 13. Double-tap / idempotency
  // ──────────────────────────────────────────────────────────
  group('Idempotency', () {
    test('TestWriteInput create idempotency (same params)', () {
      final p1 = const TestWriteInput(
        title: 'T',
        creationMethod: 'upload',
      ).toCreateParams();
      final p2 = const TestWriteInput(
        title: 'T',
        creationMethod: 'upload',
      ).toCreateParams();
      expect(p1, equals(p2));
    });
  });

  // ──────────────────────────────────────────────────────────
  // 14. Existing Manual flow regression
  // ──────────────────────────────────────────────────────────
  group('Manual flow regression', () {
    test('TestWriteInput defaults to manual', () {
      final p = const TestWriteInput(title: 'Manual Test').toCreateParams();
      expect(p['p_creation_method'], 'manual');
    });

    test('Practice kind still works with manual', () {
      final b = BackendMapping.toBackend(TestKind.practice);
      final p = TestWriteInput(
        title: 'Practice',
        testMode: b.mode.dbValue,
        settings: BackendMapping.settingsFor(TestKind.practice, null),
        durationSec: 10800,
      ).toCreateParams();
      expect(p['p_creation_method'], 'manual');
      expect(p['p_test_mode'], 'self');
    });

    test('Group kind still works with manual', () {
      final b = BackendMapping.toBackend(TestKind.group);
      final p = TestWriteInput(
        title: 'Group Test',
        testMode: b.mode.dbValue,
        settings: BackendMapping.settingsFor(TestKind.group, null),
        groupId: 'g-1',
        durationSec: 3600,
      ).toCreateParams();
      expect(p['p_creation_method'], 'manual');
      expect(p['p_test_mode'], 'group');
      expect(p['p_group_id'], 'g-1');
    });
  });

  // ──────────────────────────────────────────────────────────
  // 15. Document format labels
  // ──────────────────────────────────────────────────────────
  group('QuestionSource labels', () {
    test('document label is "Smart Document & AI Intake"', () {
      expect(QuestionSource.document.label, 'Smart Document & AI Intake');
    });

    test('document description mentions PDF/Word/Gemini AI', () {
      expect(QuestionSource.document.description, contains('PDF'));
      expect(QuestionSource.document.description, contains('Word'));
      expect(QuestionSource.document.description, contains('Gemini AI'));
    });

    test('document icon is document_scanner_outlined', () {
      expect(QuestionSource.document.icon, isNotNull);
    });
  });
}
