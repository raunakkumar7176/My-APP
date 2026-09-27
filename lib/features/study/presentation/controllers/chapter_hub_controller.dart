import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/gamification_service.dart';
import '../../data/study_repository.dart';
import '../../domain/study_chapter.dart';
import '../../domain/study_question.dart';
import '../../domain/study_topic.dart';

/// The three Chapter Hub modes. There is no fourth "test builder" mode —
/// Chapter Hub never opens the standalone test-creation flow; that feature
/// lives entirely in the separate Tests area of the app.
enum ChapterHubTab { learn, readMcq, practice }

/// State management controller for Chapter Hub's 3 modes: Learn (theory),
/// Read MCQ (read-only revision), and Chapter Practice (interactive quiz).
class ChapterHubController extends ChangeNotifier {
  ChapterHubController({
    required this.chapterId,
    StudyRepository? repository,
    this.userId,
  }) : _repository = repository ?? const SupabaseStudyRepository();

  final String chapterId;
  final StudyRepository _repository;
  final String? userId;
  bool _disposed = false;

  // ── State ──
  String _languageCode = 'en';
  ChapterHubTab _activeTab = ChapterHubTab.learn;

  StudyChapter? _chapter;
  List<StudyTopic> _topics = [];
  bool _isLoadingChapter = false;
  bool _isLoadingTopics = false;
  String? _errorMessage;

  // Questions / Assessment tab state
  List<StudyQuestion> _questions = [];
  bool _isLoadingQuestions = false;
  bool _isLoadingMoreQuestions = false;
  bool _hasMoreQuestions = true;
  int _questionOffset = 0;
  static const int _questionPageSize = 20;

  // Question interaction state for Chapter Practice (interactive quiz)
  final Map<String, int> _userSelectedOptions = {};
  final Set<String> _checkedQuestionIds = {};
  final Set<String> _expandedExplanationIds = {};

  // Card-by-card stepper position within Chapter Practice.
  int _practiceIndex = 0;

  // Local-only bookmark toggle (no backend "Saved Questions" table exists
  // today — same honest, non-persisted pattern already used for the topic
  // bookmark button elsewhere in Study; never invented server state).
  final Set<String> _bookmarkedQuestionIds = {};

  // ── Getters ──
  String get languageCode => _languageCode;
  ChapterHubTab get activeTab => _activeTab;
  int get activeTabIndex => _activeTab.index;
  StudyChapter? get chapter => _chapter;
  List<StudyTopic> get topics => List.unmodifiable(_topics);
  List<StudyQuestion> get questions => List.unmodifiable(_questions);
  bool get isLoadingChapter => _isLoadingChapter;
  bool get isLoadingTopics => _isLoadingTopics;
  bool get isLoadingQuestions => _isLoadingQuestions;
  bool get isLoadingMoreQuestions => _isLoadingMoreQuestions;
  bool get hasMoreQuestions => _hasMoreQuestions;
  String? get errorMessage => _errorMessage;

  int? getSelectedOption(String questionId) => _userSelectedOptions[questionId];
  bool isAnswerChecked(String questionId) =>
      _checkedQuestionIds.contains(questionId);
  bool isExplanationExpanded(String questionId) =>
      _expandedExplanationIds.contains(questionId);

  int get answeredCount => _userSelectedOptions.length;
  int get correctCount {
    var count = 0;
    for (final entry in _userSelectedOptions.entries) {
      for (final q in _questions) {
        if (q.id == entry.key && q.correctOption == entry.value) {
          count++;
          break;
        }
      }
    }
    return count;
  }

  // Multi-segment progress metrics
  double get theoryProgressPercentage {
    if (_topics.isEmpty) return 0.0;
    final completed = _topics.where((t) => t.isCompleted).length;
    return ((completed / _topics.length) * 100.0).clamp(0.0, 100.0);
  }

  double get questionsProgressPercentage {
    if (_questions.isEmpty) return 0.0;
    return 100.0;
  }

  int get totalEstimatedMinutes =>
      _topics.fold<int>(0, (acc, t) => acc + t.estimatedMinutes);

  int get completedTopicCount => _topics.where((t) => t.isCompleted).length;

  int get totalTopicCount => _topics.length;

  bool get isAllCompleted =>
      totalTopicCount > 0 && completedTopicCount == totalTopicCount;

  StudyTopic? get nextTopicToLearn => _topics.isEmpty
      ? null
      : _topics.firstWhere((t) => !t.isCompleted, orElse: () => _topics.first);

  int get totalQuestionCount => _chapter?.questionCount ?? _questions.length;

  // ── Chapter Practice stepper (card-by-card) ──
  int get practiceIndex => _practiceIndex;
  StudyQuestion? get currentPracticeQuestion =>
      (_practiceIndex >= 0 && _practiceIndex < _questions.length)
          ? _questions[_practiceIndex]
          : null;
  bool get isPracticeComplete =>
      _questions.isNotEmpty && _practiceIndex >= _questions.length;
  bool get hasNextPracticeQuestion => _practiceIndex < _questions.length - 1;

  bool isBookmarked(String questionId) =>
      _bookmarkedQuestionIds.contains(questionId);

  void toggleBookmark(String questionId) {
    if (_bookmarkedQuestionIds.contains(questionId)) {
      _bookmarkedQuestionIds.remove(questionId);
    } else {
      _bookmarkedQuestionIds.add(questionId);
    }
    notifyListeners();
  }

  /// Advances the Chapter Practice stepper to the next question, or past
  /// the end (see [isPracticeComplete]) once the last one is answered.
  void nextPracticeQuestion() {
    if (_practiceIndex < _questions.length) {
      _practiceIndex++;
      notifyListeners();
    }
  }

  /// Restarts the Chapter Practice session from the first question,
  /// clearing this session's answers (but not points already awarded).
  void restartPractice() {
    _practiceIndex = 0;
    _userSelectedOptions.clear();
    _checkedQuestionIds.clear();
    _expandedExplanationIds.clear();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Sets the active tab by [ChapterHubTab].
  void setTab(ChapterHubTab tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    notifyListeners();

    // Lazy load questions the first time either question-backed tab opens.
    if ((tab == ChapterHubTab.readMcq || tab == ChapterHubTab.practice) &&
        _questions.isEmpty &&
        !_isLoadingQuestions) {
      loadQuestions();
    }
  }

  /// Sets the active tab by index (0: Learn, 1: Read MCQ, 2: Chapter
  /// Practice) — for callers driving a [TabController] by index.
  void setActiveTab(int index) {
    final clamped = index.clamp(0, ChapterHubTab.values.length - 1);
    setTab(ChapterHubTab.values[clamped]);
  }

  /// Loads initial chapter metadata and topics.
  Future<void> load({String? languageCode}) async {
    if (languageCode != null) _languageCode = languageCode;
    _isLoadingChapter = true;
    _isLoadingTopics = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String? resolvedUserId = userId;
      if (resolvedUserId == null) {
        try {
          resolvedUserId = AuthService.currentUser?.id;
        } catch (_) {
          resolvedUserId = null;
        }
      }

      final chapterFuture = _repository.fetchChapterById(
        chapterId: chapterId,
        languageCode: _languageCode,
        userId: resolvedUserId,
      );
      final topicsFuture = _repository.fetchTopics(
        chapterId: chapterId,
        languageCode: _languageCode,
        userId: resolvedUserId,
      );

      final results = await Future.wait([chapterFuture, topicsFuture]);
      _chapter = results[0] as StudyChapter;
      _topics = results[1] as List<StudyTopic>;
    } catch (e, st) {
      AppLogger.error('ChapterHubController.load error: $e\n$st');
      _errorMessage = 'Failed to load chapter information.';
    } finally {
      _isLoadingChapter = false;
      _isLoadingTopics = false;
      notifyListeners();
    }

    // If a question-backed tab is already active, load questions too.
    if (_activeTab == ChapterHubTab.readMcq ||
        _activeTab == ChapterHubTab.practice) {
      await loadQuestions();
    }
  }

  /// Loads first page of practice questions.
  Future<void> loadQuestions() async {
    _isLoadingQuestions = true;
    _questionOffset = 0;
    _hasMoreQuestions = true;
    notifyListeners();

    try {
      final items = await _repository.fetchChapterQuestions(
        chapterId: chapterId,
        languageCode: _languageCode,
        limit: _questionPageSize,
        offset: 0,
      );
      _questions = items;
      _hasMoreQuestions = items.length >= _questionPageSize;
      _questionOffset = items.length;
    } catch (e, st) {
      AppLogger.error('ChapterHubController.loadQuestions error: $e\n$st');
    } finally {
      _isLoadingQuestions = false;
      notifyListeners();
    }
  }

  /// Loads subsequent page of practice questions.
  Future<void> loadMoreQuestions() async {
    if (_isLoadingMoreQuestions || !_hasMoreQuestions) return;
    _isLoadingMoreQuestions = true;
    notifyListeners();

    try {
      final items = await _repository.fetchChapterQuestions(
        chapterId: chapterId,
        languageCode: _languageCode,
        limit: _questionPageSize,
        offset: _questionOffset,
      );
      if (items.isEmpty) {
        _hasMoreQuestions = false;
      } else {
        _questions.addAll(items);
        _questionOffset += items.length;
        _hasMoreQuestions = items.length >= _questionPageSize;
      }
    } catch (e) {
      AppLogger.warning('ChapterHubController.loadMoreQuestions error: $e');
    } finally {
      _isLoadingMoreQuestions = false;
      notifyListeners();
    }
  }

  /// User selects an option in Chapter Practice (interactive quiz). Gives
  /// instant correct/wrong feedback (checked immediately); the explanation
  /// stays collapsed until [toggleExplanation] is called. A correct first
  /// attempt awards +1 point (`practice_correct`); every first attempt
  /// (correct or not) also counts toward the existing attempt-based award.
  void selectOption(String questionId, int optionIndex) {
    final isFirstAttempt = !_userSelectedOptions.containsKey(questionId);
    _userSelectedOptions[questionId] = optionIndex;
    _checkedQuestionIds.add(questionId);
    notifyListeners();

    if (isFirstAttempt) {
      unawaited(GamificationService.awardPracticeQuestionAttempted(questionId));
      StudyQuestion? question;
      for (final q in _questions) {
        if (q.id == questionId) {
          question = q;
          break;
        }
      }
      if (question != null && question.correctOption == optionIndex) {
        unawaited(GamificationService.awardPracticeCorrectAnswer(questionId));
      }
    }
  }

  /// Manually checks answer for a question on demand.
  void checkAnswer(String questionId) {
    _checkedQuestionIds.add(questionId);
    _expandedExplanationIds.add(questionId);
    notifyListeners();
  }

  /// Resets an answered question so the student can try active recall again.
  void resetQuestion(String questionId) {
    _userSelectedOptions.remove(questionId);
    _checkedQuestionIds.remove(questionId);
    _expandedExplanationIds.remove(questionId);
    notifyListeners();
  }

  /// Toggles visibility of question explanation.
  void toggleExplanation(String questionId) {
    if (_expandedExplanationIds.contains(questionId)) {
      _expandedExplanationIds.remove(questionId);
    } else {
      _expandedExplanationIds.add(questionId);
    }
    notifyListeners();
  }

  /// Toggles language and reloads data.
  Future<void> setLanguage(String code) async {
    if (_languageCode == code) return;
    _languageCode = code;
    await load(languageCode: code);
    if (_questions.isNotEmpty) {
      await loadQuestions();
    }
  }
}
