import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/extracted_content.dart';
import 'package:my_praperation/core/models/question_bank_item.dart';
import 'package:my_praperation/core/services/document_service.dart';
import 'package:my_praperation/core/services/smart_ingestion_orchestrator.dart';
import 'package:my_praperation/features/test/data/ai_generation_repository.dart';
import 'package:my_praperation/features/test/data/question_bank_repository.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';
import 'package:my_praperation/features/test/screens/document_upload_screen.dart';
import 'package:my_praperation/features/test/state/document_upload_controller.dart';
import 'package:my_praperation/features/test/widgets/question_source_step.dart';

// ── Mock Services ──

class _MockDocService implements DocumentService {
  _MockDocService({this.extractedContent, this.questions = const []});

  ExtractedContent? extractedContent;
  List<DetectedQuestion> questions;
  final List<String> calls = [];
  final List<String> purgedDocIds = [];

  @override
  Future<PickedFile> pickDocument() async => PickedFile(
    path: '/mock/test.txt',
    name: 'test.txt',
    size: 256,
    bytes: Uint8List(256),
  );

  @override
  Future<PickedFile> pickImage() async => PickedFile(
    path: '/mock/test.png',
    name: 'test.png',
    size: 256,
    bytes: Uint8List(256),
  );

  @override
  void validateFile(PickedFile file) {}

  @override
  Future<UploadedDocumentRecord> uploadFile({
    required PickedFile file,
    String? groupId,
    bool isEphemeral = true,
  }) async {
    calls.add('upload');
    return UploadedDocumentRecord(
      id: 'doc-mock-123',
      fileName: file.name,
      storagePath: 'user/doc-mock-123.txt',
      mimeType: 'text/plain',
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
    purgedDocIds.add(doc.id);
    calls.add('purge:${doc.id}');
  }

  @override
  Future<int> purgeStaleEphemeralDocuments({int maxAgeMinutes = 120}) async =>
      0;

  @override
  Future<List<UploadedDocumentRecord>> listMyDocuments() async => [];

  @override
  Future<int> cleanupOrphanedStorage() async => 0;

  @override
  Future<ExtractedContent> extractContent(UploadedDocumentRecord doc) async {
    calls.add('extractContent:${doc.fileName}');
    return extractedContent ??
        const ExtractedContent(
          blocks: [
            ContentBlock(
              text: 'Sample Document Content',
              sourceLocation: 'p.1',
            ),
          ],
          sourceFormat: DocumentFormat.txt,
        );
  }

  @override
  ExtractedContent extractFromBytes(Uint8List bytes, String fileName) {
    calls.add('extractFromBytes:$fileName');
    return extractedContent ??
        const ExtractedContent(
          blocks: [
            ContentBlock(text: 'Bytes Document Content', sourceLocation: 'p.1'),
          ],
          sourceFormat: DocumentFormat.txt,
        );
  }

  @override
  ExtractedContent extractFromImages(List<Uint8List> pages) {
    calls.add('extractFromImages:${pages.length}');
    return extractedContent ??
        const ExtractedContent(blocks: [], sourceFormat: DocumentFormat.image);
  }

  @override
  List<DetectedQuestion> detectQuestions(ExtractedContent content) => questions;

  @override
  IngestionDetectionResult detectQuestionsWithConfidence(
    ExtractedContent content,
  ) {
    calls.add('detectQuestionsWithConfidence');
    final valid = questions.where((q) => q.hasValidStructure).toList();
    final withAns = questions.where((q) => q.hasCorrectAnswer).toList();
    final score = questions.isNotEmpty ? valid.length / questions.length : 0.0;
    return IngestionDetectionResult(
      questions: questions,
      confidence: IngestionConfidence(
        totalDetected: questions.length,
        validCount: valid.length,
        withAnswerCount: withAns.length,
        score: score,
        isHighConfidence: valid.length >= 2 && score >= 0.7,
      ),
      answersDetected: withAns.length,
    );
  }
}

class _MockAiRepository extends AiGenerationRepository {
  _MockAiRepository() : stubbedResult = null;

  AiGenerationResult? stubbedResult;
  final List<String> calls = [];

  @override
  Future<AiGenerationResult> generateQuestions({
    required String subject,
    required String topic,
    String? chapter,
    required int questionCount,
    required String difficulty,
    Map<String, int>? difficultyDistribution,
    required String language,
    String questionType = 'mcq',
    double marksPerQuestion = 1,
    String? groupId,
    String testMode = 'self',
    String? sourceText,
    String? title,
  }) async {
    calls.add(
      'generateQuestions:count=$questionCount,hasSourceText=${sourceText != null}',
    );
    return stubbedResult ??
        const AiGenerationResult(
          questions: [
            AiGeneratedQuestion(
              id: 'ai-q1',
              question: 'Generated Question 1 from Theory?',
              options: ['Option A', 'Option B', 'Option C', 'Option D'],
              correctOption: 1,
              explanation: 'Generated explanation 1',
              subject: 'Physics',
              topic: 'Kinematics',
            ),
            AiGeneratedQuestion(
              id: 'ai-q2',
              question: 'Generated Question 2 from Theory?',
              options: ['True', 'False', 'Neither', 'Both'],
              correctOption: 0,
              explanation: 'Generated explanation 2',
              subject: 'Physics',
              topic: 'Kinematics',
            ),
          ],
          summary: AiGenerationSummary(
            requested: 2,
            generated: 2,
            valid: 2,
            needsReview: 0,
            invalid: 0,
          ),
          quota: AiQuotaStatus(
            usedToday: 1,
            remaining: 2,
            limit: 3,
            canGenerate: true,
          ),
          tokensIn: 320,
          tokensOut: 180,
        );
  }
}

class _MockQuestionBankRepo implements QuestionBankRepository {
  final List<QuestionDraft> savedDrafts = [];
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
    savedDrafts.addAll(drafts);
    lastSubjectId = subjectId;
    lastChapterId = chapterId;
    lastSource = source;
    lastStatus = status;

    return QuestionBankSaveResult(
      total: drafts.length,
      savedCount: drafts.length,
      savedIds: [for (var i = 0; i < drafts.length; i++) 'qb-saved-$i'],
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
  group(
    'Phase 2: High-Precision Deterministic MCQ Engine & Noise Filtering',
    () {
      test(
        'Noise filter strips headers, footers, phone numbers, and page numbers',
        () {
          const textWithNoise = '''
ALLEN CAREER INSTITUTE, KOTA
Toll Free: 1800-258-5555 | www.allen.ac.in
Page 1 of 5
1. What is the SI unit of electric force?
(A) Joule
(B) Newton
(C) Pascal
(D) Watt
Answer: (B)
FIITJEE LTD. All Rights Reserved.
Page 2 of 5
2. What is the value of acceleration due to gravity?
(A) 9.8 m/s^2
(B) 8.9 m/s^2
(C) 10.2 m/s^2
(D) 12.0 m/s^2
Answer: (A)
''';

          final service = SupabaseDocumentService();
          const content = ExtractedContent(
            blocks: [ContentBlock(text: textWithNoise, sourceLocation: 'p.1')],
            sourceFormat: DocumentFormat.txt,
          );

          final result = service.detectQuestionsWithConfidence(content);

          expect(result.questions.length, equals(2));
          expect(result.confidence.isHighConfidence, isTrue);
          expect(result.confidence.score, equals(1.0));
          expect(result.confidence.validCount, equals(2));
          expect(result.confidence.withAnswerCount, equals(2));

          // Verify answers paired correctly from text
          expect(
            result.questions[0].detectedCorrectIndex,
            equals(1),
          ); // (B) -> index 1
          expect(
            result.questions[1].detectedCorrectIndex,
            equals(0),
          ); // (A) -> index 0
        },
      );

      test(
        'Answer key detector pairs footer answer table to detected questions',
        () {
          const textWithSeparateKey = '''
1. Which particle has positive charge?
(a) Electron
(b) Proton
(c) Neutron
(d) Photon

2. What is the symbol for Gold?
(a) Ag
(b) Fe
(c) Au
(d) Pb

--- ANSWER KEY ---
1. b
2. c
''';

          final service = SupabaseDocumentService();
          const content = ExtractedContent(
            blocks: [
              ContentBlock(text: textWithSeparateKey, sourceLocation: 'p.1'),
            ],
            sourceFormat: DocumentFormat.txt,
          );

          final result = service.detectQuestionsWithConfidence(content);

          expect(result.questions.length, equals(2));
          expect(result.questions[0].detectedCorrectIndex, equals(1)); // b -> 1
          expect(result.questions[1].detectedCorrectIndex, equals(2)); // c -> 2
        },
      );
    },
  );

  group('Phase 2: Smart Ingestion Orchestrator Branching Logic', () {
    test(
      'Branch A: >= 2 valid MCQs detected -> Deterministic (0 AI tokens used)',
      () async {
        const q1 = DetectedQuestion(
          questionText: 'What is the speed of light?',
          options: ['3x10^8 m/s', '3x10^6 m/s', '1x10^8 m/s', 'None'],
          detectedCorrectIndex: 0,
        );
        const q2 = DetectedQuestion(
          questionText: 'What is the unit of power?',
          options: ['Watt', 'Joule', 'Newton', 'Pascal'],
          detectedCorrectIndex: 0,
        );

        final mockDoc = _MockDocService(
          questions: [q1, q2],
          extractedContent: const ExtractedContent(
            blocks: [
              ContentBlock(
                text: 'Q1. What is the speed of light?\n(A) 3x10^8 m/s (B) 3x10^6 m/s\n\nQ2. What is the unit of power?\n(A) Watt (B) Joule',
                sourceLocation: 'p.1',
              ),
            ],
            sourceFormat: DocumentFormat.txt,
          ),
        );
        final mockAi = _MockAiRepository();

        final orchestrator = SmartIngestionOrchestrator(
          documentService: mockDoc,
          aiRepository: mockAi,
        );

        final events = <SmartIngestionEvent>[];
        final result = await orchestrator.processBytes(
          bytes: Uint8List.fromList('sample document'.codeUnits),
          fileName: 'mcqs.txt',
          onProgress: (e) => events.add(e),
        );

        // Verify Zero AI tokens consumed
        expect(result.source, equals(SmartIngestionSource.deterministic));
        expect(result.tokensUsed, equals(0));
        expect(result.isDeterministic, isTrue);
        expect(result.isAiGenerated, isFalse);
        expect(result.questions.length, equals(2));
        expect(mockAi.calls, isEmpty); // Zero AI calls

        // Check progress events
        expect(
          events.any((e) => e.stage == SmartIngestionStage.extracting),
          isTrue,
        );
        expect(
          events.any(
            (e) => e.stage == SmartIngestionStage.deterministicSuccess,
          ),
          isTrue,
        );
      },
    );

    test('Branch B: Theory reading (>150 chars) with 0 MCQs -> Routes to Gemini AI', () async {
      const theoryText = '''
Thermodynamics is the branch of physics that deals with heat, work, and temperature,
and their relation to energy, radiation, and physical properties of matter.
The four laws of thermodynamics govern how these quantities behave. The first law
states that energy cannot be created or destroyed, only transformed from one form to another.
The second law states that the total entropy of an isolated system always increases over time.
The third law states that the entropy of a system approaches a constant value as the temperature
approaches absolute zero.
''';

      final mockDoc = _MockDocService(
        questions: [], // No structured MCQs
        extractedContent: const ExtractedContent(
          blocks: [ContentBlock(text: theoryText, sourceLocation: 'p.1')],
          sourceFormat: DocumentFormat.txt,
        ),
      );
      final mockAi = _MockAiRepository();

      final orchestrator = SmartIngestionOrchestrator(
        documentService: mockDoc,
        aiRepository: mockAi,
      );

      final events = <SmartIngestionEvent>[];
      final result = await orchestrator.processBytes(
        bytes: Uint8List.fromList(theoryText.codeUnits),
        fileName: 'thermodynamics_notes.txt',
        subject: 'Physics',
        chapter: 'Thermodynamics',
        targetQuestionCount: 2,
        onProgress: (e) => events.add(e),
      );

      // Verify AI fallback was routed
      expect(result.source, equals(SmartIngestionSource.aiFallback));
      expect(result.isAiGenerated, isTrue);
      expect(result.tokensUsed, greaterThan(0));
      expect(mockAi.calls.length, equals(1));
      expect(mockAi.calls.first, contains('hasSourceText=true'));
      expect(result.questions.length, equals(2));
      expect(result.questions.first.source, equals('ai'));

      // Check lifecycle events
      expect(
        events.any((e) => e.stage == SmartIngestionStage.routingToAi),
        isTrue,
      );
      expect(
        events.any((e) => e.stage == SmartIngestionStage.aiGenerating),
        isTrue,
      );
      expect(
        events.any((e) => e.stage == SmartIngestionStage.completed),
        isTrue,
      );
    });
  });

  group('Phase 3: Controller & Unified UI Integration', () {
    test(
      'DocumentUploadController sets correct source and saves to Question Bank',
      () async {
        const q1 = DetectedQuestion(
          questionText: 'What is force?',
          options: [
            'Mass x Acceleration',
            'Mass / Volume',
            'Work / Time',
            'None',
          ],
          detectedCorrectIndex: 0,
        );
        const q2 = DetectedQuestion(
          questionText: 'What is momentum?',
          options: ['Mass x Velocity', 'Force x Time', 'Both A and B', 'None'],
          detectedCorrectIndex: 2,
        );

        final mockDoc = _MockDocService(
          questions: [q1, q2],
          extractedContent: const ExtractedContent(
            blocks: [
              ContentBlock(text: 'Structured MCQs', sourceLocation: 'p.1'),
            ],
            sourceFormat: DocumentFormat.txt,
          ),
        );
        final mockAi = _MockAiRepository();
        final mockQb = _MockQuestionBankRepo();

        final orchestrator = SmartIngestionOrchestrator(
          documentService: mockDoc,
          aiRepository: mockAi,
        );

        final controller = DocumentUploadController(
          documentService: mockDoc,
          orchestrator: orchestrator,
          questionBankRepository: mockQb,
          subjectId: 'sub-physics-1',
          chapterId: 'chap-mechanics-1',
        );

        // Upload and parse
        await controller.pickAndUpload();
        expect(controller.state, equals(DocumentFlowState.uploaded));

        await controller.parseDocument();
        expect(controller.state, equals(DocumentFlowState.parsed));
        expect(controller.detectedQuestions.length, equals(2));
        expect(controller.readyDrafts.length, equals(2));
        expect(controller.readyDrafts.first.source, equals('upload'));

        // Save to Question Bank
        controller.setSaveToQuestionBank(true);
        expect(controller.saveToQuestionBank, isTrue);

        final saveResult = await controller.saveSelectedToQuestionBank();
        expect(saveResult, isNotNull);
        expect(saveResult!.savedCount, equals(2));
        expect(mockQb.savedDrafts.length, equals(2));
        expect(mockQb.lastSubjectId, equals('sub-physics-1'));
        expect(mockQb.lastChapterId, equals('chap-mechanics-1'));
        expect(mockQb.lastSource, equals('upload'));

        // Post-processing purge
        await controller.purgePostProcessing();
        expect(mockDoc.purgedDocIds, contains('doc-mock-123'));
      },
    );

    testWidgets(
      'DocumentUploadScreen displays EXTRACTED and AI-GENERATED badges',
      (tester) async {
        const q1 = DetectedQuestion(
          questionText: 'Question One?',
          options: ['A', 'B', 'C', 'D'],
          detectedCorrectIndex: 0,
        );
        const q2 = DetectedQuestion(
          questionText: 'Question Two?',
          options: ['A', 'B', 'C', 'D'],
          detectedCorrectIndex: 1,
        );

        final mockDoc = _MockDocService(questions: [q1, q2]);
        final mockAi = _MockAiRepository();
        final mockQb = _MockQuestionBankRepo();

        final orchestrator = SmartIngestionOrchestrator(
          documentService: mockDoc,
          aiRepository: mockAi,
        );

        final controller = DocumentUploadController(
          documentService: mockDoc,
          orchestrator: orchestrator,
          questionBankRepository: mockQb,
        );

        await tester.pumpWidget(
          MaterialApp(home: DocumentUploadScreen(controller: controller)),
        );

        // Trigger parse to enter review state
        await controller.pickAndUpload();
        await controller.parseDocument();
        controller.startReview();
        await tester.pumpAndSettle();

        // Check review cards and EXTRACTED badge
        expect(find.byType(Card), findsNWidgets(2));
        expect(find.text('EXTRACTED'), findsNWidgets(2));

        // Check Save to Question Bank checkbox presence
        expect(
          find.text('Save selected to Question Bank / My Study'),
          findsOneWidget,
        );

        // Check Start Over & Add Questions buttons
        expect(find.text('Start Over'), findsOneWidget);
        expect(find.text('Add 2 Questions'), findsOneWidget);
      },
    );

    testWidgets(
      'QuestionSourceStep displays consolidated Smart Document & AI Intake option',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuestionSourceStep(
                selected: QuestionSource.document,
                onChanged: (_) {},
              ),
            ),
          ),
        );

        // Verify the consolidated title and description
        expect(find.text('Smart Document & AI Intake'), findsOneWidget);
        expect(
          find.textContaining('Upload PDF / Word / TXT / Image'),
          findsOneWidget,
        );
      },
    );
  });
}
