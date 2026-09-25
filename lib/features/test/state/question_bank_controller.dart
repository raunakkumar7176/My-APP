import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/question_bank_item.dart';
import '../data/question_bank_repository.dart';
import 'disposable_notifier.dart';

/// State management for the Question Bank feature.
///
/// Handles:
/// - Paginated listing with server-side filtering
/// - Search with debouncing
/// - Filter state management
/// - Bulk selection for test creation
/// - Loading/error states
class QuestionBankController extends DisposableNotifier {
  QuestionBankController({QuestionBankRepository? repository})
    : _repository = repository ?? const SupabaseQuestionBankRepository();

  final QuestionBankRepository _repository;

  // ── State ──
  List<QuestionBankItem> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  QuestionBankFilter _filter = const QuestionBankFilter();
  int _total = 0;
  bool _hasMore = true;

  // ── Selection state for test creation ──
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  // ── Getters ──
  List<QuestionBankItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  QuestionBankFilter get filter => _filter;
  int get total => _total;
  bool get hasMore => _hasMore;
  bool get selectionMode => _selectionMode;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;

  /// Whether the current user has any items selected.
  bool get hasSelection => _selectedIds.isNotEmpty;

  // ── Actions ──

  /// Loads the first page of bank questions.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _repository.list(_filter.resetOffset());
      _items = result.items;
      _total = result.total;
      _hasMore = result.hasMore;
      _error = null;
    } on AppError catch (e) {
      _error = e.message;
      AppLogger.error('QuestionBankController.load: $e');
    } catch (e, st) {
      _error = 'Failed to load question bank';
      AppLogger.error(
        'QuestionBankController.load unexpected: $e',
        stackTrace: st,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads the next page of results (append).
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final result = await _repository.list(
        _filter.copyWith(offset: _items.length),
      );
      _items = [..._items, ...result.items];
      _total = result.total;
      _hasMore = result.hasMore;
      _error = null;
    } on AppError catch (e) {
      _error = e.message;
      AppLogger.error('QuestionBankController.loadMore: $e');
    } catch (e, st) {
      _error = 'Failed to load more questions';
      AppLogger.error(
        'QuestionBankController.loadMore unexpected: $e',
        stackTrace: st,
      );
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Updates search query and reloads from page 1.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed == (_filter.search ?? '')) return;
    _filter = _filter.copyWith(search: trimmed.isEmpty ? null : trimmed);
    await load();
  }

  /// Updates a filter and reloads from page 1.
  Future<void> setFilter({
    String? status,
    String? subjectId,
    String? subjectName,
    String? chapter,
    String? topicNodeId,
    String? difficulty,
    String? language,
    String? questionType,
    String? source,
  }) async {
    _filter = _filter.copyWith(
      status: status,
      subjectId: subjectId,
      subjectName: subjectName,
      chapter: chapter,
      topicNodeId: topicNodeId,
      difficulty: difficulty,
      language: language,
      questionType: questionType,
      source: source,
    );
    await load();
  }

  /// Clears all filters and reloads.
  Future<void> clearFilters() async {
    _filter = const QuestionBankFilter();
    await load();
  }

  /// Checks if a specific filter is active.
  bool hasActiveFilter({
    String? status,
    String? subjectId,
    String? subjectName,
    String? chapter,
    String? topicNodeId,
    String? difficulty,
    String? language,
    String? questionType,
    String? source,
  }) {
    if (status != null && _filter.status == status) return true;
    if (subjectId != null && _filter.subjectId == subjectId) return true;
    if (subjectName != null && _filter.subjectName == subjectName) return true;
    if (chapter != null && _filter.chapter == chapter) return true;
    if (topicNodeId != null && _filter.topicNodeId == topicNodeId) return true;
    if (difficulty != null && _filter.difficulty == difficulty) return true;
    if (language != null && _filter.language == language) return true;
    if (questionType != null && _filter.questionType == questionType) {
      return true;
    }
    if (source != null && _filter.source == source) return true;
    return false;
  }

  /// Gets count of available bank questions for given filters.
  Future<int> getAvailableCount({
    String? subjectName,
    String? chapter,
    String? difficulty,
    String? language,
  }) async {
    try {
      return await _repository.getAvailableCount(
        subjectName: subjectName,
        chapter: chapter,
        difficulty: difficulty,
        language: language,
      );
    } catch (e) {
      AppLogger.warning('getAvailableCount failed: $e');
      return 0;
    }
  }

  // ── Selection management ──

  /// Enters selection mode.
  void enterSelectionMode() {
    _selectionMode = true;
    notifyListeners();
  }

  /// Exits selection mode and clears selection.
  void exitSelectionMode() {
    _selectionMode = false;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Toggles selection for a question.
  void toggleSelection(String questionId) {
    if (_selectedIds.contains(questionId)) {
      _selectedIds.remove(questionId);
    } else {
      _selectedIds.add(questionId);
    }
    notifyListeners();
  }

  /// Selects all currently loaded questions.
  void selectAll() {
    for (final item in _items) {
      _selectedIds.add(item.id);
    }
    notifyListeners();
  }

  /// Deselects all questions.
  void deselectAll() {
    _selectedIds.clear();
    notifyListeners();
  }

  /// Returns the selected bank items.
  List<QuestionBankItem> getSelectedItems() {
    return _items.where((item) => _selectedIds.contains(item.id)).toList();
  }

  /// Creates a question in the bank.
  Future<String?> createQuestion({
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
  }) async {
    try {
      final id = await _repository.create(
        question: question,
        options: options,
        correctOption: correctOption,
        explanation: explanation,
        subjectId: subjectId,
        subjectName: subjectName,
        chapter: chapter,
        topicNodeId: topicNodeId,
        difficulty: difficulty,
        language: language,
        questionType: questionType,
        source: source,
      );
      await load(); // Refresh list
      return id;
    } catch (e) {
      AppLogger.error('QuestionBankController.createQuestion: $e');
      rethrow;
    }
  }

  /// Updates a question in the bank.
  Future<void> updateQuestion({
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
  }) async {
    try {
      await _repository.update(
        id: id,
        question: question,
        options: options,
        correctOption: correctOption,
        explanation: explanation,
        subjectId: subjectId,
        subjectName: subjectName,
        chapter: chapter,
        topicNodeId: topicNodeId,
        difficulty: difficulty,
        language: language,
        questionType: questionType,
        status: status,
      );
      await load(); // Refresh list
    } catch (e) {
      AppLogger.error('QuestionBankController.updateQuestion: $e');
      rethrow;
    }
  }

  /// Archives a question in the bank.
  Future<void> archiveQuestion(String id) async {
    try {
      await _repository.archive(id);
      await load(); // Refresh list
    } catch (e) {
      AppLogger.error('QuestionBankController.archiveQuestion: $e');
      rethrow;
    }
  }

  /// Restores an archived question.
  Future<void> restoreQuestion(String id) async {
    try {
      await _repository.restore(id);
      await load(); // Refresh list
    } catch (e) {
      AppLogger.error('QuestionBankController.restoreQuestion: $e');
      rethrow;
    }
  }

  /// Checks for duplicate questions.
  Future<List<QuestionBankItem>> checkDuplicates(String questionText) async {
    try {
      return await _repository.checkDuplicates(questionText);
    } catch (e) {
      AppLogger.error('QuestionBankController.checkDuplicates: $e');
      return [];
    }
  }

  /// Gets a single bank question by ID.
  Future<QuestionBankItem?> getById(String id) async {
    try {
      return await _repository.getById(id);
    } catch (e) {
      AppLogger.error('QuestionBankController.getById: $e');
      return null;
    }
  }

  /// Clones selected bank questions into a test.
  ///
  /// This is a snapshot operation - bank questions are copied into the test's
  /// questions table with bank_id set for provenance tracking.
  /// Only APPROVED bank content can be cloned (governance enforced server-side).
  ///
  /// Returns the number of questions cloned.
  Future<int> cloneToTest({
    required String testId,
    required List<String> bankIds,
    int marksPerQuestion = 1,
  }) async {
    try {
      final count = await _repository.cloneToTest(
        testId: testId,
        bankIds: bankIds,
        marksPerQuestion: marksPerQuestion,
      );
      exitSelectionMode();
      return count;
    } catch (e) {
      AppLogger.error('QuestionBankController.cloneToTest: $e');
      rethrow;
    }
  }
}
