import 'dart:typed_data';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/extracted_content.dart';
import '../../../core/services/document_service.dart';
import '../../../core/services/smart_ingestion_orchestrator.dart';
import '../data/question_bank_repository.dart';
import '../models/question_draft.dart';
import 'disposable_notifier.dart';

/// Lifecycle states for the document upload → question import flow.
enum DocumentFlowState {
  idle,
  picking,
  validating,
  uploading,
  uploaded,
  parsing,
  parsed,
  reviewing,
  creating,
  deleting,
  success,
  error,
}

/// Manages the complete document upload → extract → detect → review flow.
///
/// This controller is independent of TestCreationController and feeds
/// detected questions back as QuestionDrafts once the user confirms.
class DocumentUploadController extends DisposableNotifier {
  DocumentUploadController({
    DocumentService? documentService,
    SmartIngestionOrchestrator? orchestrator,
    QuestionBankRepository? questionBankRepository,
    this.groupId,
    this.subjectId,
    this.chapterId,
  }) : _docService = documentService ?? SupabaseDocumentService(),
       _orchestrator =
           orchestrator ??
           SmartIngestionOrchestrator(
             documentService: documentService ?? SupabaseDocumentService(),
           ),
       _qbRepo =
           questionBankRepository ?? const SupabaseQuestionBankRepository();

  final DocumentService _docService;
  final SmartIngestionOrchestrator _orchestrator;
  final QuestionBankRepository _qbRepo;
  final String? groupId;
  final String? subjectId;
  final String? chapterId;

  // ── State ──
  DocumentFlowState _state = DocumentFlowState.idle;
  String? _errorMessage;
  UploadedDocumentRecord? _uploadedDoc;
  ExtractedContent? _extractedContent;
  final List<DetectedQuestion> _detectedQuestions = [];
  final List<int> _selectedIndices = [];
  final Map<int, QuestionDraft> _editedQuestions = {};
  SmartIngestionSource _ingestionSource = SmartIngestionSource.deterministic;
  SmartIngestionEvent? _lastEvent;
  bool _saveToQuestionBank = false;

  // ── Getters ──
  SmartIngestionSource get ingestionSource => _ingestionSource;
  SmartIngestionEvent? get lastEvent => _lastEvent;
  bool get saveToQuestionBank => _saveToQuestionBank;
  void setSaveToQuestionBank(bool value) {
    _saveToQuestionBank = value;
    notifyListeners();
  }

  DocumentFlowState get state => _state;
  String? get errorMessage => _errorMessage;
  UploadedDocumentRecord? get uploadedDoc => _uploadedDoc;
  ExtractedContent? get extractedContent => _extractedContent;
  List<DetectedQuestion> get detectedQuestions =>
      List.unmodifiable(_detectedQuestions);
  List<int> get selectedIndices => List.unmodifiable(_selectedIndices);
  bool get isBusy =>
      _state == DocumentFlowState.picking ||
      _state == DocumentFlowState.uploading ||
      _state == DocumentFlowState.parsing ||
      _state == DocumentFlowState.creating ||
      _state == DocumentFlowState.deleting;

  int get selectedCount => _selectedIndices.length;
  int get totalCount => _detectedQuestions.length;

  /// Whether there are any selected, valid questions ready for import.
  bool get hasReadyQuestions => _selectedIndices.isNotEmpty;

  /// The final list of QuestionDrafts ready to be fed into
  /// TestCreationController.setLocalQuestions().
  List<QuestionDraft> get readyDrafts {
    final drafts = <QuestionDraft>[];
    final defaultSource = _ingestionSource == SmartIngestionSource.aiFallback
        ? 'ai'
        : 'upload';
    for (final idx in _selectedIndices) {
      if (idx < _detectedQuestions.length) {
        final edited = _editedQuestions[idx];
        if (edited != null) {
          drafts.add(
            edited.source.isNotEmpty
                ? edited
                : edited.copyWith(source: defaultSource),
          );
        } else {
          final draft = _detectedQuestions[idx].toDraft();
          drafts.add(
            draft.source.isNotEmpty
                ? draft
                : draft.copyWith(source: defaultSource),
          );
        }
      }
    }
    return drafts;
  }

  // ── Flow Steps ──

  /// Step 1: Pick and upload a document.
  Future<void> pickAndUpload() async {
    if (isBusy) return;
    _setState(DocumentFlowState.picking);
    _errorMessage = null;

    try {
      // Pick file.
      _setState(DocumentFlowState.validating);
      final file = await _docService.pickDocument();

      // Validate.
      _docService.validateFile(file);

      // Upload.
      _setState(DocumentFlowState.uploading);
      _uploadedDoc = await _docService.uploadFile(file: file, groupId: groupId);
      _setState(DocumentFlowState.uploaded);
    } on AppError catch (e) {
      _setError(e.message);
    } catch (e, st) {
      AppLogger.error('Document pick/upload failed: $e', stackTrace: st);
      _setError('Failed to pick or upload file. Please try again.');
    }
  }

  /// Step 2: Parse/extract content from the uploaded file using smart intake.
  Future<void> parseDocument() async {
    final doc = _uploadedDoc;
    if (doc == null) {
      _setError('No document uploaded.');
      return;
    }
    if (isBusy) return;

    _setState(DocumentFlowState.parsing);
    _errorMessage = null;

    try {
      final result = await _orchestrator.processUploadedDocument(
        doc: doc,
        subject: subjectId,
        chapter: chapterId,
        onProgress: (event) {
          _lastEvent = event;
          notifyListeners();
        },
      );

      _ingestionSource = result.source;
      _extractedContent =
          result.rawContent ??
          ExtractedContent(
            sourceFormat: DocumentFormat.pdf,
            blocks: [
              ContentBlock(text: result.extractedText, sourceLocation: 'p.1'),
            ],
          );

      _detectedQuestions.clear();
      _selectedIndices.clear();
      _editedQuestions.clear();

      for (var i = 0; i < result.questions.length; i++) {
        final draft = result.questions[i];
        final detected = DetectedQuestion(
          questionText: draft.questionText,
          options: draft.options.map((o) => o.text).toList(),
          detectedCorrectIndex: draft.correctOptionIndex,
          explanation: draft.explanation,
          sourceLocation: 'p.1',
          sourceFormat: _extractedContent?.sourceFormat ?? DocumentFormat.pdf,
          confidence: result.isDeterministic ? 0.95 : 0.85,
        );
        _detectedQuestions.add(detected);
        _editedQuestions[i] = draft;
        _selectedIndices.add(i);
      }

      _setState(DocumentFlowState.parsed);
    } on AppError catch (e) {
      _setError(e.message);
    } catch (e, st) {
      AppLogger.error('Document parsing failed: $e', stackTrace: st);
      _setError('Failed to parse document. The file may be corrupted.');
    }
  }

  /// Camera pages, captured via [CameraCaptureScreen], enter the exact same
  /// extract → detect → review pipeline as an uploaded file (Phase 1/26) —
  /// there is no separate camera detection engine. No upload/storage step:
  /// this V1 keeps camera pages in memory for the review session only (see
  /// the report's "known limitations" for what that means for provenance).
  Future<void> parseImages(List<Uint8List> pages) async {
    if (pages.isEmpty) {
      _setError('No pages to process.');
      return;
    }
    if (isBusy) return;

    _setState(DocumentFlowState.parsing);
    _errorMessage = null;

    try {
      await _runExtraction(() async => _docService.extractFromImages(pages));
    } on AppError catch (e) {
      _setError(e.message);
    } catch (e, st) {
      AppLogger.error('Camera page processing failed: $e', stackTrace: st);
      _setError('Could not process those pages. Please try again.');
    }
  }

  /// Shared tail of [parseImages]: run the extractor, detect
  /// questions with confidence, and auto-select all of them.
  Future<void> _runExtraction(
    Future<ExtractedContent> Function() extract,
  ) async {
    _extractedContent = await extract();

    final detection = _docService.detectQuestionsWithConfidence(
      _extractedContent!,
    );
    _detectedQuestions
      ..clear()
      ..addAll(detection.questions);

    _selectedIndices.clear();
    _editedQuestions.clear();
    for (var i = 0; i < _detectedQuestions.length; i++) {
      _selectedIndices.add(i);
    }

    _setState(DocumentFlowState.parsed);
  }

  /// Combined: pick, upload, and parse in one flow.
  Future<void> pickUploadAndParse() async {
    await pickAndUpload();
    if (_state == DocumentFlowState.uploaded) {
      await parseDocument();
    }
  }

  /// Step 1 (image variant): pick an image from the gallery and upload it —
  /// same states, same storage/DB path as [pickAndUpload], just sourced
  /// from [DocumentService.pickImage] instead of [DocumentService.
  /// pickDocument].
  Future<void> pickImageAndUpload() async {
    if (isBusy) return;
    _setState(DocumentFlowState.picking);
    _errorMessage = null;

    try {
      _setState(DocumentFlowState.validating);
      final file = await _docService.pickImage();

      _docService.validateFile(file);

      _setState(DocumentFlowState.uploading);
      _uploadedDoc = await _docService.uploadFile(file: file, groupId: groupId);
      _setState(DocumentFlowState.uploaded);
    } on AppError catch (e) {
      _setError(e.message);
    } catch (e, st) {
      AppLogger.error('Image pick/upload failed: $e', stackTrace: st);
      _setError('Failed to pick or upload image. Please try again.');
    }
  }

  /// Combined: pick an image, upload, and parse (no OCR — see
  /// [DocumentService.extractFromImages] — so this always lands in the
  /// "add manually" review state, same as a camera page).
  Future<void> pickImageUploadAndParse() async {
    await pickImageAndUpload();
    if (_state == DocumentFlowState.uploaded) {
      await parseDocument();
    }
  }

  /// Removes the currently uploaded document (Storage object + metadata
  /// row) and returns to idle. Used for an explicit "Remove file" action
  /// before the creator commits to reviewing/importing its questions.
  Future<void> deleteCurrentDocument() async {
    final doc = _uploadedDoc;
    if (doc == null || isBusy) return;

    _setState(DocumentFlowState.deleting);
    _errorMessage = null;

    try {
      await _docService.deleteDocument(doc);
      reset();
    } on AppError catch (e) {
      _setError(e.message);
    } catch (e, st) {
      AppLogger.error('Document delete failed: $e', stackTrace: st);
      _setError('Failed to delete the file. Please try again.');
    }
  }

  // ── Review Operations ──

  /// Enter the review state.
  void startReview() {
    _setState(DocumentFlowState.reviewing);
  }

  /// Toggle selection of a detected question.
  void toggleSelection(int index) {
    if (index < 0 || index >= _detectedQuestions.length) return;
    if (_selectedIndices.contains(index)) {
      _selectedIndices.remove(index);
    } else {
      _selectedIndices.add(index);
    }
    notifyListeners();
  }

  /// Select all questions.
  void selectAll() {
    _selectedIndices.clear();
    for (var i = 0; i < _detectedQuestions.length; i++) {
      _selectedIndices.add(i);
    }
    notifyListeners();
  }

  /// Deselect all questions.
  void deselectAll() {
    _selectedIndices.clear();
    notifyListeners();
  }

  /// Adds a brand-new question directly into the review list, selected.
  /// Needed for camera-sourced content, which (no OCR — see
  /// [DocumentService.extractFromImages]) never auto-detects anything: the
  /// creator still needs a way to add a question against a captured page
  /// without leaving this screen.
  void addManualQuestion(
    QuestionDraft draft, {
    String sourceLocation = 'Manual entry',
  }) {
    _detectedQuestions.add(
      DetectedQuestion(
        questionText: draft.questionText,
        options: [for (final o in draft.options) o.text],
        sourceLocation: sourceLocation,
        sourceFormat: _extractedContent?.sourceFormat ?? DocumentFormat.camera,
        detectedCorrectIndex: draft.correctOptionIndex,
        explanation: draft.explanation,
      ),
    );
    final newIndex = _detectedQuestions.length - 1;
    _editedQuestions[newIndex] = draft;
    _selectedIndices.add(newIndex);
    notifyListeners();
  }

  /// Edit a detected question's draft.
  void updateQuestionDraft(int index, QuestionDraft draft) {
    if (index < 0 || index >= _detectedQuestions.length) return;
    _editedQuestions[index] = draft;
    notifyListeners();
  }

  /// Get the current draft for a question (edited or original).
  QuestionDraft draftForQuestion(int index) {
    if (index < 0 || index >= _detectedQuestions.length) {
      return const QuestionDraft(questionText: '');
    }
    return _editedQuestions[index] ?? _detectedQuestions[index].toDraft();
  }

  /// Remove a detected question from the list entirely.
  void removeQuestion(int index) {
    if (index < 0 || index >= _detectedQuestions.length) return;
    _detectedQuestions.removeAt(index);

    // Re-key everything past `index` down by one in a single pass — doing
    // the removal and the shift as two separate list mutations (as this
    // used to) reads the "shift" data from a list the "removal" step had
    // already destroyed, silently deselecting every question after the
    // removed one instead of shifting its selection down.
    final newEdited = <int, QuestionDraft>{
      for (final e in _editedQuestions.entries)
        if (e.key != index) (e.key > index ? e.key - 1 : e.key): e.value,
    };
    _editedQuestions
      ..clear()
      ..addAll(newEdited);

    final newSelected = {
      for (final i in _selectedIndices)
        if (i != index) (i > index ? i - 1 : i),
    }.toList()..sort();
    _selectedIndices
      ..clear()
      ..addAll(newSelected);

    notifyListeners();
  }

  /// Reorder a question to a new position.
  void reorderQuestion(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _detectedQuestions.length) return;
    if (newIndex < 0 || newIndex >= _detectedQuestions.length) return;

    final item = _detectedQuestions.removeAt(oldIndex);
    _detectedQuestions.insert(newIndex, item);

    // Rebuild selected indices and edited questions maps.
    final newSelected = <int>[];
    final newEdited = <int, QuestionDraft>{};
    for (final idx in _selectedIndices) {
      if (idx == oldIndex) {
        newSelected.add(newIndex);
      } else if (oldIndex < newIndex) {
        newSelected.add(idx >= oldIndex && idx <= newIndex ? idx - 1 : idx);
      } else {
        newSelected.add(idx >= newIndex && idx < oldIndex ? idx + 1 : idx);
      }
    }
    _selectedIndices
      ..clear()
      ..addAll(newSelected);

    for (final entry in _editedQuestions.entries) {
      var newKey = entry.key;
      if (entry.key == oldIndex) {
        newKey = newIndex;
      } else if (oldIndex < newIndex) {
        if (entry.key > oldIndex && entry.key <= newIndex) newKey--;
      } else {
        if (entry.key >= newIndex && entry.key < oldIndex) newKey++;
      }
      newEdited[newKey] = entry.value;
    }
    _editedQuestions
      ..clear()
      ..addAll(newEdited);

    notifyListeners();
  }

  /// Validate that selected questions meet minimum requirements.
  List<String> validateSelected() {
    final errors = <String>[];
    if (_selectedIndices.isEmpty) {
      errors.add('No questions selected.');
      return errors;
    }

    for (final idx in _selectedIndices) {
      final draft = draftForQuestion(idx);
      if (!draft.isValid) {
        final reasons = <String>[];
        if (draft.questionText.trim().isEmpty) {
          reasons.add('empty question text');
        }
        if (draft.options.length < QuestionDraft.minOptions) {
          reasons.add(
            'needs ${QuestionDraft.minOptions} options (has ${draft.options.length})',
          );
        }
        if (!draft.hasCorrectOption) {
          reasons.add('no correct option set');
        }
        errors.add('Question ${idx + 1}: ${reasons.join(", ")}');
      }
    }

    return errors;
  }

  // ── Zero-Leak Ephemeral Purging ──

  /// Purges uploaded ephemeral document when user cancels/leaves the upload flow.
  Future<void> purgeOnCancellation() async {
    final doc = _uploadedDoc;
    if (doc != null && doc.isEphemeral) {
      _uploadedDoc = null;
      try {
        await _docService.purgeEphemeralDocument(doc);
      } catch (e, st) {
        AppLogger.error('purgeOnCancellation error: $e', stackTrace: st);
      }
    }
  }

  /// Purges uploaded ephemeral document after questions are imported into test/bank.
  Future<void> purgePostProcessing() async {
    final doc = _uploadedDoc;
    if (doc != null && doc.isEphemeral) {
      _uploadedDoc = null;
      try {
        await _docService.purgeEphemeralDocument(doc);
      } catch (e, st) {
        AppLogger.error('purgePostProcessing error: $e', stackTrace: st);
      }
    }
  }

  /// Saves selected ready drafts to Question Bank using RPC with deduplication.
  Future<QuestionBankSaveResult?> saveSelectedToQuestionBank() async {
    final drafts = readyDrafts;
    if (drafts.isEmpty) return null;

    try {
      final defaultSource = _ingestionSource == SmartIngestionSource.aiFallback
          ? 'ai'
          : 'upload';
      final result = await _qbRepo.saveDrafts(
        drafts: drafts,
        subjectId: subjectId,
        chapterId: chapterId,
        source: defaultSource,
      );
      AppLogger.info(
        'Saved drafts to Question Bank: saved=${result.savedCount}, duplicates=${result.skippedDuplicateCount}',
      );
      return result;
    } catch (e, st) {
      AppLogger.error(
        'Failed to save drafts to Question Bank: $e',
        stackTrace: st,
      );
      return null;
    }
  }

  // ── Cleanup ──

  /// Reset the entire flow.
  void reset({bool purgeEphemeral = false}) {
    if (purgeEphemeral && _uploadedDoc != null && _uploadedDoc!.isEphemeral) {
      final doc = _uploadedDoc!;
      _uploadedDoc = null;
      _docService.purgeEphemeralDocument(doc).ignore();
    } else {
      _uploadedDoc = null;
    }
    _state = DocumentFlowState.idle;
    _errorMessage = null;
    _extractedContent = null;
    _detectedQuestions.clear();
    _selectedIndices.clear();
    _editedQuestions.clear();
    _ingestionSource = SmartIngestionSource.deterministic;
    _lastEvent = null;
    _saveToQuestionBank = false;
    notifyListeners();
  }

  // ── Internals ──

  void _setState(DocumentFlowState newState) {
    _state = newState;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _setState(DocumentFlowState.error);
  }
}
