import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/extracted_content.dart';
import '../../../core/services/document_service.dart';
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
    this.groupId,
  }) : _docService = documentService ?? SupabaseDocumentService();

  final DocumentService _docService;
  final String? groupId;

  // ── State ──
  DocumentFlowState _state = DocumentFlowState.idle;
  String? _errorMessage;
  UploadedDocumentRecord? _uploadedDoc;
  ExtractedContent? _extractedContent;
  final List<DetectedQuestion> _detectedQuestions = [];
  final List<int> _selectedIndices = [];
  final Map<int, QuestionDraft> _editedQuestions = {};

  // ── Getters ──
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
      _state == DocumentFlowState.creating;

  int get selectedCount => _selectedIndices.length;
  int get totalCount => _detectedQuestions.length;

  /// Whether there are any selected, valid questions ready for import.
  bool get hasReadyQuestions => _selectedIndices.isNotEmpty;

  /// The final list of QuestionDrafts ready to be fed into
  /// TestCreationController.setLocalQuestions().
  List<QuestionDraft> get readyDrafts {
    final drafts = <QuestionDraft>[];
    for (final idx in _selectedIndices) {
      if (idx < _detectedQuestions.length) {
        final edited = _editedQuestions[idx];
        if (edited != null) {
          drafts.add(edited);
        } else {
          drafts.add(_detectedQuestions[idx].toDraft());
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
      _uploadedDoc = await _docService.uploadFile(
        file: file,
        groupId: groupId,
      );
      _setState(DocumentFlowState.uploaded);
    } on AppError catch (e) {
      _setError(e.message);
    } catch (e, st) {
      AppLogger.error('Document pick/upload failed: $e', stackTrace: st);
      _setError('Failed to pick or upload file. Please try again.');
    }
  }

  /// Step 2: Parse/extract content from the uploaded file.
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
      _extractedContent = await _docService.extractContent(doc);

      // Detect questions.
      final detected = _docService.detectQuestions(_extractedContent!);
      _detectedQuestions
        ..clear()
        ..addAll(detected);

      // Auto-select all detected questions.
      _selectedIndices.clear();
      for (var i = 0; i < _detectedQuestions.length; i++) {
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

  /// Combined: pick, upload, and parse in one flow.
  Future<void> pickUploadAndParse() async {
    await pickAndUpload();
    if (_state == DocumentFlowState.uploaded) {
      await parseDocument();
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
    _editedQuestions.remove(index);
    _selectedIndices.remove(index);
    // Adjust indices.
    _selectedIndices.removeWhere((i) => i > index);
    _selectedIndices.addAll(
      _selectedIndices.where((i) => i > index).map((i) => i - 1),
    );
    _selectedIndices.sort();
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
          reasons.add('needs ${QuestionDraft.minOptions} options (has ${draft.options.length})');
        }
        if (!draft.hasCorrectOption) {
          reasons.add('no correct option set');
        }
        errors.add('Question ${idx + 1}: ${reasons.join(", ")}');
      }
    }

    return errors;
  }

  // ── Cleanup ──

  /// Reset the entire flow.
  void reset() {
    _state = DocumentFlowState.idle;
    _errorMessage = null;
    _uploadedDoc = null;
    _extractedContent = null;
    _detectedQuestions.clear();
    _selectedIndices.clear();
    _editedQuestions.clear();
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
