import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/gamification_service.dart';
import '../../data/study_repository.dart';
import '../../domain/study_chapter.dart';
import '../../domain/study_question.dart';
import '../../domain/study_topic.dart';

/// State management controller for Chapter Hub (Learn, Questions, Test).
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
  int _activeTabIndex = 0; // 0: Learn, 1: Assessment Hub (Practice & Test)
  int _assessmentMode = 0; // 0: Smart Practice Mode, 1: Formal Chapter Exam

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

  // Question interaction state for Smart Practice
  final Map<String, int> _userSelectedOptions = {};
  final Set<String> _checkedQuestionIds = {};
  final Set<String> _expandedExplanationIds = {};

  // ── Getters ──
  String get languageCode => _languageCode;
  int get activeTabIndex => _activeTabIndex;
  int get assessmentMode => _assessmentMode;
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

  /// Sets the active mode inside the Assessment Hub:
  /// 0: Smart Practice Mode, 1: Formal Chapter Exam.
  void setAssessmentMode(int mode) {
    if (_assessmentMode == mode) return;
    _assessmentMode = mode;
    notifyListeners();
  }

  /// Sets the active tab (0: Learn, 1: Assessment Hub).
  /// Gracefully accepts 2 for backward compatibility mapping to Formal Exam mode.
  void setActiveTab(int index) {
    final targetTab = index >= 1 ? 1 : 0;
    if (index == 2) {
      _assessmentMode = 1;
    } else if (index == 1 && _activeTabIndex != 1) {
      _assessmentMode = 0;
    }
    _activeTabIndex = targetTab;
    notifyListeners();

    // Lazy load questions when Assessment Hub is selected first time
    if (_activeTabIndex == 1 && _questions.isEmpty && !_isLoadingQuestions) {
      loadQuestions();
    }
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

    // If active tab is Questions, load questions as well
    if (_activeTabIndex == 1) {
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

  /// User selects an option for an MCQ practice card in Smart Practice Mode.
  /// Immediate feedback: checks answer and reveals explanation on demand.
  void selectOption(String questionId, int optionIndex) {
    final isFirstAttempt = !_userSelectedOptions.containsKey(questionId);
    _userSelectedOptions[questionId] = optionIndex;
    _checkedQuestionIds.add(questionId);
    _expandedExplanationIds.add(questionId);
    notifyListeners();

    if (isFirstAttempt) {
      unawaited(GamificationService.awardPracticeQuestionAttempted(questionId));
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
