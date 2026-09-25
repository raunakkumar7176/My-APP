import 'package:flutter/foundation.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/auth_service.dart';
import '../../data/study_repository.dart';
import '../../domain/continue_learning.dart';
import '../../domain/study_subject.dart';

/// State management controller for the primary Study Home Dashboard.
class StudyHomeController extends ChangeNotifier {
  StudyHomeController({StudyRepository? repository})
    : _repository = repository ?? const SupabaseStudyRepository();

  final StudyRepository _repository;
  bool _disposed = false;

  // ── State ──
  String _languageCode = 'en';
  List<StudySubject> _allSubjects = [];
  List<StudySubject> _filteredSubjects = [];
  String _searchQuery = '';
  ContinueLearningSnapshot? _continueLearning;
  StudyProgressSummary _progressSummary = const StudyProgressSummary();
  bool _isLoading = false;
  String? _errorMessage;

  // ── Getters ──
  String get languageCode => _languageCode;
  bool get isHindi => _languageCode == 'hi';
  List<StudySubject> get subjects => List.unmodifiable(_filteredSubjects);
  String get searchQuery => _searchQuery;
  ContinueLearningSnapshot? get continueLearning => _continueLearning;
  StudyProgressSummary get progressSummary => _progressSummary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

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

  /// Initial load of subjects, continue-learning snapshot, and study stats.
  Future<void> load({String? languageCode}) async {
    if (languageCode != null) _languageCode = languageCode;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final userId = AuthService.currentUser?.id;

      final subjectsFuture = _repository.fetchSubjects(
        languageCode: _languageCode,
      );
      final continueFuture = userId != null
          ? _repository.fetchRecentStudyProgress(
              userId: userId,
              languageCode: _languageCode,
            )
          : Future<ContinueLearningSnapshot?>.value(null);
      final summaryFuture = userId != null
          ? _repository.fetchStudySummary(userId: userId)
          : Future<StudyProgressSummary>.value(const StudyProgressSummary());

      final results = await Future.wait([
        subjectsFuture,
        continueFuture,
        summaryFuture,
      ]);

      _allSubjects = results[0] as List<StudySubject>;
      _continueLearning = results[1] as ContinueLearningSnapshot?;
      _progressSummary = results[2] as StudyProgressSummary;
      _applySearch();
    } catch (e, st) {
      AppLogger.error('StudyHomeController.load error: $e\n$st');
      _errorMessage = 'Failed to load study subjects. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggles between English ('en') and Hindi ('hi').
  Future<void> setLanguage(String code) async {
    if (_languageCode == code) return;
    _languageCode = code;
    await load(languageCode: code);
  }

  /// Toggles between 'en' and 'hi'.
  Future<void> toggleLanguage() async {
    final next = _languageCode == 'en' ? 'hi' : 'en';
    await setLanguage(next);
  }

  /// Sets search query and filters visible subjects in-memory.
  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    _applySearch();
    notifyListeners();
  }

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      _filteredSubjects = List.from(_allSubjects);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredSubjects = _allSubjects.where((s) {
        return s.name.toLowerCase().contains(q) ||
            s.description.toLowerCase().contains(q) ||
            s.subjectKey.toLowerCase().contains(q);
      }).toList();
    }
  }
}
