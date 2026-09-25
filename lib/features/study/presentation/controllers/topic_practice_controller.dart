import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/study_repository.dart';
import '../../domain/study_question.dart';

/// Manages interactive question-by-question practice session for a topic.
class TopicPracticeController extends ChangeNotifier {
  TopicPracticeController({
    required this.topicId,
    this.chapterId,
    this.topicTitle,
    this.chapterTitle,
    this.subjectTitle,
    this.subjectId,
    this.languageCode = 'en',
    StudyRepository? repository,
  }) : _repository = repository ?? const SupabaseStudyRepository();

  final String topicId;
  final String? chapterId;
  final String? topicTitle;
  final String? chapterTitle;
  final String? subjectTitle;
  final String? subjectId;
  final StudyRepository _repository;

  String languageCode;
  bool _disposed = false;
  bool _isLoading = false;
  String? _errorMessage;

  List<StudyQuestion> _allQuestions = [];
  List<StudyQuestion> _sessionQuestions = [];
  int _currentIndex = 0;
  int? _selectedOptionIndex;
  bool _isAnswerChecked = false;
  final Map<int, int> _userAnswers = {};
  final Set<String> _mistakeQuestionIds = {};
  int _correctCount = 0;
  int _incorrectCount = 0;
  bool _isCompleted = false;
  bool _isReviewMode = false;
  final Stopwatch _stopwatch = Stopwatch();

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isHindi => languageCode == 'hi';

  List<StudyQuestion> get questions => List.unmodifiable(_sessionQuestions);
  int get totalQuestions => _sessionQuestions.length;
  int get currentIndex => _currentIndex;

  StudyQuestion? get currentQuestion =>
      _sessionQuestions.isNotEmpty && _currentIndex < _sessionQuestions.length
      ? _sessionQuestions[_currentIndex]
      : null;

  int? get selectedOptionIndex => _selectedOptionIndex;
  bool get isAnswerChecked => _isAnswerChecked;
  int get correctCount => _correctCount;
  int get incorrectCount => _incorrectCount;
  int get totalAnswered => _correctCount + _incorrectCount;

  int get accuracyPercentage {
    if (totalAnswered == 0) return 0;
    return ((_correctCount / totalAnswered) * 100).round();
  }

  bool get isCompleted => _isCompleted;
  bool get isReviewMode => _isReviewMode;
  int get mistakeCount => _mistakeQuestionIds.length;
  Duration get elapsedTime => _stopwatch.elapsed;

  String get formattedDuration {
    final minutes = _stopwatch.elapsed.inMinutes;
    final seconds = _stopwatch.elapsed.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  bool get isLastQuestion =>
      _sessionQuestions.isNotEmpty &&
      _currentIndex == _sessionQuestions.length - 1;

  bool get hasUnsavedProgress =>
      !_isCompleted &&
      (_selectedOptionIndex != null ||
          _correctCount > 0 ||
          _incorrectCount > 0);

  bool get isCurrentAnswerCorrect =>
      _isAnswerChecked &&
      currentQuestion != null &&
      _selectedOptionIndex == currentQuestion!.correctOption;

  // ── Session Lifecycle ─────────────────────────────────────────────────────

  @override
  void dispose() {
    _stopwatch.stop();
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  /// Loads practice questions from the repository.
  Future<void> loadQuestions({bool forceChapterFallback = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      List<StudyQuestion> items;
      if (forceChapterFallback && chapterId != null && chapterId!.isNotEmpty) {
        items = await _repository.fetchChapterQuestions(
          chapterId: chapterId!,
          languageCode: languageCode,
          limit: 30,
        );
      } else {
        items = await _repository.fetchTopicQuestions(
          topicId: topicId,
          chapterId: chapterId,
          languageCode: languageCode,
          limit: 30,
        );
      }

      _allQuestions = items;
      _sessionQuestions = List.of(items);
      _currentIndex = 0;
      _selectedOptionIndex = null;
      _isAnswerChecked = false;
      _userAnswers.clear();
      _mistakeQuestionIds.clear();
      _correctCount = 0;
      _incorrectCount = 0;
      _isCompleted = false;
      _isReviewMode = false;

      _stopwatch.reset();
      if (_sessionQuestions.isNotEmpty) {
        _stopwatch.start();
      }
    } catch (e, st) {
      AppLogger.error('TopicPracticeController.loadQuestions error: $e\n$st');
      _errorMessage = isHindi
          ? 'प्रश्नों को लोड करने में त्रुटि हुई। कृपया पुनः प्रयास करें।'
          : 'Failed to load practice questions. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Selects an option for the current question before checking.
  void selectOption(int index) {
    if (_isAnswerChecked || _isCompleted) return;
    if (_selectedOptionIndex == index) return;
    _selectedOptionIndex = index;
    notifyListeners();
  }

  /// Checks the selected option and calculates immediate feedback.
  void checkAnswer() {
    final question = currentQuestion;
    if (_selectedOptionIndex == null || _isAnswerChecked || question == null) {
      return;
    }

    _isAnswerChecked = true;
    _userAnswers[_currentIndex] = _selectedOptionIndex!;

    if (_selectedOptionIndex == question.correctOption) {
      _correctCount++;
    } else {
      _incorrectCount++;
      _mistakeQuestionIds.add(question.id);
    }

    notifyListeners();
  }

  /// Advances to the next question or completes the practice session.
  void nextQuestion() {
    if (!_isAnswerChecked && !_isCompleted) return;

    if (_currentIndex < _sessionQuestions.length - 1) {
      _currentIndex++;
      _selectedOptionIndex = null;
      _isAnswerChecked = false;
    } else {
      _isCompleted = true;
      _stopwatch.stop();
    }
    notifyListeners();
  }

  /// Starts a focused review session containing only questions answered incorrectly.
  void startReviewMistakes() {
    if (_mistakeQuestionIds.isEmpty) return;

    final mistakes = _allQuestions
        .where((q) => _mistakeQuestionIds.contains(q.id))
        .toList();

    if (mistakes.isEmpty) return;

    _sessionQuestions = mistakes;
    _currentIndex = 0;
    _selectedOptionIndex = null;
    _isAnswerChecked = false;
    _isCompleted = false;
    _isReviewMode = true;
    _correctCount = 0;
    _incorrectCount = 0;
    _userAnswers.clear();

    _stopwatch.reset();
    _stopwatch.start();
    notifyListeners();
  }

  /// Restarts the practice session from the beginning with the full question pool.
  void restartPractice() {
    _sessionQuestions = List.of(_allQuestions);
    _currentIndex = 0;
    _selectedOptionIndex = null;
    _isAnswerChecked = false;
    _isCompleted = false;
    _isReviewMode = false;
    _correctCount = 0;
    _incorrectCount = 0;
    _mistakeQuestionIds.clear();
    _userAnswers.clear();

    _stopwatch.reset();
    if (_sessionQuestions.isNotEmpty) {
      _stopwatch.start();
    }
    notifyListeners();
  }

  /// Toggles between English and Hindi.
  void toggleLanguage() {
    languageCode = languageCode == 'en' ? 'hi' : 'en';
    loadQuestions();
  }
}
