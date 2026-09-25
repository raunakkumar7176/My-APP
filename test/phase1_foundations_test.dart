import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/extracted_content.dart';
import 'package:my_praperation/core/models/question_bank_item.dart';
import 'package:my_praperation/core/services/document_service.dart';
import 'package:my_praperation/features/test/data/question_bank_repository.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/state/document_upload_controller.dart';

class _MockDocumentService implements DocumentService {
  UploadedDocumentRecord? nextUpload;
  final List<String> calls = [];
  final List<String> purgedDocIds = [];

  @override
  Future<PickedFile> pickDocument() async => PickedFile(
    path: '/test/doc.pdf',
    name: 'doc.pdf',
    size: 512,
    bytes: Uint8List(512),
  );

  @override
  Future<PickedFile> pickImage() async => PickedFile(
    path: '/test/doc.jpg',
    name: 'doc.jpg',
    size: 512,
    bytes: Uint8List(512),
  );

  @override
  void validateFile(PickedFile file) {}

  @override
  Future<UploadedDocumentRecord> uploadFile({
    required PickedFile file,
    String? groupId,
    bool isEphemeral = true,
  }) async {
    calls.add('upload:isEphemeral=$isEphemeral');
    return nextUpload ??
        UploadedDocumentRecord(
          id: 'test-doc-123',
          fileName: file.name,
          storagePath: 'user-uid/123-doc.pdf',
          mimeType: 'application/pdf',
          fileSize: file.size,
          isEphemeral: isEphemeral,
        );
  }

  @override
  Future<void> deleteDocument(UploadedDocumentRecord doc) async {
    calls.add('delete:${doc.id}');
  }

  @override
  Future<void> purgeEphemeralDocument(UploadedDocumentRecord doc) async {
    calls.add('purge:${doc.id}');
    purgedDocIds.add(doc.id);
  }

  @override
  Future<int> purgeStaleEphemeralDocuments({int maxAgeMinutes = 120}) async {
    calls.add('purgeStale:$maxAgeMinutes');
    return 1;
  }

  @override
  Future<List<UploadedDocumentRecord>> listMyDocuments() async => [];

  @override
  Future<int> cleanupOrphanedStorage() async => 0;

  @override
  Future<ExtractedContent> extractContent(UploadedDocumentRecord doc) async =>
      const ExtractedContent(blocks: [], sourceFormat: DocumentFormat.pdf);

  @override
  ExtractedContent extractFromBytes(Uint8List bytes, String fileName) =>
      const ExtractedContent(blocks: [], sourceFormat: DocumentFormat.pdf);

  @override
  ExtractedContent extractFromImages(List<Uint8List> pages) =>
      const ExtractedContent(blocks: [], sourceFormat: DocumentFormat.camera);

  @override
  List<DetectedQuestion> detectQuestions(ExtractedContent content) => [];

  @override
  IngestionDetectionResult detectQuestionsWithConfidence(
    ExtractedContent content,
  ) {
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

class _MockQuestionBankRepository implements QuestionBankRepository {
  QuestionBankSaveResult? saveResult;
  List<QuestionDraft>? lastSavedDrafts;
  String? lastSubjectId;
  String? lastChapterId;
  String? lastSource;
  String? lastStatus;

  @override
  Future<QuestionBankSaveResult> saveDrafts({
    required List<QuestionDraft> drafts,
    String? subjectId,
    String? chapterId,
    String source = 'upload',
    String status = 'pending_review',
  }) async {
    lastSavedDrafts = drafts;
    lastSubjectId = subjectId;
    lastChapterId = chapterId;
    lastSource = source;
    lastStatus = status;

    return saveResult ??
        QuestionBankSaveResult(
          total: drafts.length,
          savedCount: drafts.length,
          savedIds: List.generate(drafts.length, (i) => 'qb-id-$i'),
          skippedDuplicateCount: 0,
          skippedDuplicates: const [],
        );
  }

  @override
  Future<List<QuestionBankItem>> checkDuplicates(String questionText) async =>
      [];

  @override
  Future<int> cloneToTest({
    required String testId,
    required List<String> bankIds,
    int marksPerQuestion = 1,
  }) async => bankIds.length;

  @override
  Future<String> create({
    required String question,
    required List<QuestionBankOption> options,
    required int correctOption,
    String explanation = '',
    String? subjectId,
    String subjectName = '',
    String chapter = '',
    String? topicNodeId,
    String difficulty = 'medium',
    String language = 'en',
    String questionType = 'mcq',
    String source = 'manual',
  }) async => 'created-id';

  @override
  Future<int> getAvailableCount({
    String? subjectName,
    String? chapter,
    String? difficulty,
    String? language,
  }) async => 10;

  @override
  Future<QuestionBankItem?> getById(String id) async => null;

  @override
  Future<QuestionBankPage> list(QuestionBankFilter filter) async =>
      const QuestionBankPage(items: [], total: 0, offset: 0, pageSize: 20);

  @override
  Future<void> archive(String id) async {}

  @override
  Future<void> restore(String id) async {}

  @override
  Future<void> update({
    required String id,
    String? question,
    List<QuestionBankOption>? options,
    int? correctOption,
    String? explanation,
    String? subjectId,
    String? subjectName,
    String? chapter,
    String? topicNodeId,
    String? difficulty,
    String? language,
    String? questionType,
    String? status,
  }) async {}
}

void main() {
  group('Phase 1: Zero-Leak Storage Lifecycle', () {
    test('UploadedDocumentRecord defaults to isEphemeral = true', () {
      const record = UploadedDocumentRecord(
        id: 'doc-1',
        fileName: 'test.pdf',
        storagePath: 'uid/test.pdf',
        mimeType: 'application/pdf',
        fileSize: 1024,
      );

      expect(record.isEphemeral, isTrue);
    });

    test('UploadedDocumentRecord preserves explicit isEphemeral = false', () {
      const record = UploadedDocumentRecord(
        id: 'doc-2',
        fileName: 'permanent.pdf',
        storagePath: 'uid/permanent.pdf',
        mimeType: 'application/pdf',
        fileSize: 2048,
        isEphemeral: false,
      );

      expect(record.isEphemeral, isFalse);
    });

    test(
      'purgeOnCancellation calls service purge and clears uploaded doc',
      () async {
        final mock = _MockDocumentService();
        final controller = DocumentUploadController(documentService: mock);

        await controller.pickAndUpload();
        expect(controller.uploadedDoc, isNotNull);
        expect(controller.uploadedDoc!.isEphemeral, isTrue);

        await controller.purgeOnCancellation();
        expect(mock.purgedDocIds, contains('test-doc-123'));
        expect(controller.uploadedDoc, isNull);
      },
    );

    test(
      'purgePostProcessing purges ephemeral document after import',
      () async {
        final mock = _MockDocumentService();
        final controller = DocumentUploadController(documentService: mock);

        await controller.pickAndUpload();
        expect(controller.uploadedDoc, isNotNull);

        await controller.purgePostProcessing();
        expect(mock.purgedDocIds, contains('test-doc-123'));
        expect(controller.uploadedDoc, isNull);
      },
    );

    test('purgeOnCancellation skips non-ephemeral documents', () async {
      final mock = _MockDocumentService();
      mock.nextUpload = const UploadedDocumentRecord(
        id: 'persistent-1',
        fileName: 'book.pdf',
        storagePath: 'uid/book.pdf',
        mimeType: 'application/pdf',
        fileSize: 5000,
        isEphemeral: false,
      );

      final controller = DocumentUploadController(documentService: mock);
      await controller.pickAndUpload();

      await controller.purgeOnCancellation();
      expect(mock.purgedDocIds, isEmpty);
      expect(controller.uploadedDoc, isNotNull);
    });

    test('reset with purgeEphemeral=true triggers purge', () async {
      final mock = _MockDocumentService();
      final controller = DocumentUploadController(documentService: mock);

      await controller.pickAndUpload();
      controller.reset(purgeEphemeral: true);

      // Async purge scheduled
      await pumpEventQueue();
      expect(mock.purgedDocIds, contains('test-doc-123'));
      expect(controller.uploadedDoc, isNull);
    });
  });

  group('Phase 1: Question Bank Save Bridge', () {
    test('QuestionBankSaveResult fromJson parses valid response', () {
      final json = {
        'total': 3,
        'saved_count': 2,
        'saved_ids': ['id-1', 'id-2'],
        'skipped_duplicate_count': 1,
        'skipped_duplicates': [
          {
            'question': 'What is 2+2?',
            'reason': 'ALREADY_EXISTS_IN_BANK',
            'duplicate_key': 'what is 2+2?',
          },
        ],
      };

      final result = QuestionBankSaveResult.fromJson(json);
      expect(result.total, 3);
      expect(result.savedCount, 2);
      expect(result.savedIds, ['id-1', 'id-2']);
      expect(result.skippedDuplicateCount, 1);
      expect(result.skippedDuplicates.length, 1);
      expect(
        result.skippedDuplicates.first['reason'],
        'ALREADY_EXISTS_IN_BANK',
      );
    });

    test('QuestionBankSaveResult handles empty / null fallback', () {
      final result = QuestionBankSaveResult.fromJson({});
      expect(result.total, 0);
      expect(result.savedCount, 0);
      expect(result.savedIds, isEmpty);
      expect(result.skippedDuplicateCount, 0);
      expect(result.skippedDuplicates, isEmpty);
    });

    test('QuestionBankRepository.saveDrafts delegates correctly with options and mapping', () async {
      final repo = _MockQuestionBankRepository();

      const drafts = [
        QuestionDraft(
          questionText: 'What is the speed of light?',
          options: [
            QuestionOptionDraft(id: '1', text: '3x10^8 m/s'),
            QuestionOptionDraft(id: '2', text: '3x10^6 m/s'),
            QuestionOptionDraft(id: '3', text: '1.5x10^8 m/s'),
            QuestionOptionDraft(id: '4', text: 'None of these'),
          ],
          correctOptionIndex: 0,
          explanation: 'Standard speed of light in vacuum.',
          subjectId: 'sub-physics-uuid',
          topicNodeId: 'topic-optics-uuid',
        ),
      ];

      final res = await repo.saveDrafts(
        drafts: drafts,
        subjectId: 'sub-fallback-uuid',
        chapterId: 'chap-optics-uuid',
        source: 'upload',
        status: 'approved',
      );

      expect(res.savedCount, 1);
      expect(repo.lastSavedDrafts?.length, 1);
      expect(repo.lastSubjectId, 'sub-fallback-uuid');
      expect(repo.lastChapterId, 'chap-optics-uuid');
      expect(repo.lastSource, 'upload');
      expect(repo.lastStatus, 'approved');
    });
  });
}
