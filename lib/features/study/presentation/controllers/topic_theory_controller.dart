import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/gamification_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/study_repository.dart';
import '../../domain/content_block.dart';
import '../../domain/study_chapter.dart';
import '../../domain/study_topic.dart';

/// State management controller for Topic Theory reading screen.
class TopicTheoryController extends ChangeNotifier {
  TopicTheoryController({
    required String initialTopicId,
    required this.chapterId,
    StudyRepository? repository,
    String? userId,
  }) : _currentTopicId = initialTopicId,
       _repository = repository ?? const SupabaseStudyRepository(),
       _explicitUserId = userId;

  final String chapterId;
  final StudyRepository _repository;
  final String? _explicitUserId;
  bool _disposed = false;

  // ── State ──
  String _currentTopicId;
  String _languageCode = 'en';
  StudyChapter? _chapter;
  StudyTopic? _topic;
  List<StudyTopic> _chapterTopics = [];
  List<ContentBlock> _contentBlocks = [];
  bool _isLoading = false;
  bool _isSavingProgress = false;
  String? _errorMessage;

  // ── Getters ──
  String get currentTopicId => _currentTopicId;
  String get languageCode => _languageCode;
  bool get isHindi => _languageCode == 'hi';
  StudyChapter? get chapter => _chapter;
  StudyTopic? get topic => _topic;
  List<ContentBlock> get contentBlocks => List.unmodifiable(_contentBlocks);
  bool get isLoading => _isLoading;
  bool get isSavingProgress => _isSavingProgress;
  String? get errorMessage => _errorMessage;

  int get currentTopicIndex =>
      _chapterTopics.indexWhere((t) => t.id == _currentTopicId);

  bool get hasPrevious => currentTopicIndex > 0;
  bool get hasNext =>
      currentTopicIndex >= 0 && currentTopicIndex < _chapterTopics.length - 1;

  StudyTopic? get previousTopic =>
      hasPrevious ? _chapterTopics[currentTopicIndex - 1] : null;

  StudyTopic? get nextTopic =>
      hasNext ? _chapterTopics[currentTopicIndex + 1] : null;

  bool get isCompleted => _topic?.isCompleted ?? false;

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

  String? _resolveUserId() {
    if (_explicitUserId != null) return _explicitUserId;
    try {
      if (SupabaseService.isInitialized) {
        return AuthService.currentUser?.id;
      }
    } catch (_) {}
    return null;
  }

  /// Loads topic details, sibling topics in chapter, and content blocks.
  Future<void> load({String? topicId, String? languageCode}) async {
    if (topicId != null) _currentTopicId = topicId;
    if (languageCode != null) _languageCode = languageCode;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final userId = _resolveUserId();

      // Parallel batch fetching for optimal performance
      final topicsFuture = _repository.fetchTopics(
        chapterId: chapterId,
        languageCode: _languageCode,
        userId: userId,
      );

      final blocksFuture = _repository.fetchContentBlocks(
        topicId: _currentTopicId,
        languageCode: _languageCode,
      );

      Future<StudyChapter?> chapterFuture;
      if (chapterId.isNotEmpty) {
        chapterFuture = _repository
            .fetchChapterById(
              chapterId: chapterId,
              languageCode: _languageCode,
              userId: userId,
            )
            .then<StudyChapter?>((c) => c)
            .catchError((_) => null);
      } else {
        chapterFuture = Future.value(null);
      }

      final results = await Future.wait([
        topicsFuture,
        blocksFuture,
        chapterFuture,
      ]);

      _chapterTopics = results[0] as List<StudyTopic>;
      _contentBlocks = results[1] as List<ContentBlock>;
      _chapter = results[2] as StudyChapter?;

      // Identify active topic
      final found = _chapterTopics.where((t) => t.id == _currentTopicId);
      if (found.isNotEmpty) {
        _topic = found.first;
      } else {
        _topic = await _repository.fetchTopicById(
          topicId: _currentTopicId,
          languageCode: _languageCode,
        );
      }
    } catch (e, st) {
      AppLogger.error('TopicTheoryController.load error: $e\n$st');
      _errorMessage = 'Failed to load topic contents.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles topic completion status and updates Supabase.
  Future<void> toggleCompletion() async {
    if (_topic == null || _isSavingProgress) return;
    final userId = _resolveUserId();

    final targetStatus = !_topic!.isCompleted;
    _isSavingProgress = true;
    notifyListeners();

    try {
      if (userId != null && userId.isNotEmpty) {
        await _repository.toggleTopicCompletion(
          topicId: _currentTopicId,
          chapterId: chapterId,
          userId: userId,
          isCompleted: targetStatus,
        );
      }

      _topic = _topic!.copyWith(isCompleted: targetStatus);

      if (targetStatus) {
        unawaited(GamificationService.awardTopicCompleted(_currentTopicId));
      }

      // Update in chapterTopics list as well
      final idx = _chapterTopics.indexWhere((t) => t.id == _currentTopicId);
      if (idx != -1) {
        _chapterTopics[idx] = _topic!;
      }
    } catch (e) {
      AppLogger.error('TopicTheoryController.toggleCompletion error: $e');
    } finally {
      _isSavingProgress = false;
      notifyListeners();
    }
  }

  /// Switches to language ('en' or 'hi') and reloads blocks.
  Future<void> setLanguage(String code) async {
    if (_languageCode == code) return;
    _languageCode = code;
    await load(languageCode: code);
  }

  /// Navigates to previous topic in current chapter.
  Future<void> goToPreviousTopic() async {
    if (!hasPrevious) return;
    await load(topicId: previousTopic!.id);
  }

  /// Navigates to next topic in current chapter.
  Future<void> goToNextTopic() async {
    if (!hasNext) return;
    await load(topicId: nextTopic!.id);
  }
}
