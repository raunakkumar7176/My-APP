import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/performance_summary.dart';
import '../../../core/models/progress_snapshot.dart';
import '../../../core/models/result.dart';
import '../../../core/models/result_analytics.dart';
import '../../../core/models/test.dart';
import '../../../core/services/progress_service.dart';
import '../../test/data/result_repository.dart';
import '../../test/data/test_repository.dart';
import '../../test/domain/result_analytics_mapper.dart';
import '../../test/domain/test_lifecycle.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/performance_repository.dart';

/// One completed test plus the caller's latest result on it.
final class RecentTestResult {
  const RecentTestResult({required this.test, required this.result});

  final Test test;
  final Result result;
}

/// Aggregates existing per-test [Result] rows and [ProgressSnapshot]s into a
/// performance overview. Nothing here is server-computed ranking or a new
/// statistic — every number is derived from rows the app already stores and
/// already shows elsewhere (test result screen, progress snapshots).
///
/// Bounded fetch: only the most recent [_maxTestsScanned] completed tests are
/// scanned for a result, never the caller's whole history.
class PerformanceController extends DisposableNotifier {
  PerformanceController({
    TestRepository? testRepository,
    ResultRepository? resultRepository,
    PerformanceRepository? performanceRepository,
  })  : _tests = testRepository ?? const SupabaseTestRepository(),
        _results = resultRepository ?? const SupabaseResultRepository(),
        _performanceRepo = performanceRepository ?? const SupabasePerformanceRepository();

  final TestRepository _tests;
  final ResultRepository _results;
  final PerformanceRepository _performanceRepo;

  static const _maxTestsScanned = 15;

  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<RecentTestResult> _recent = [];
  List<ProgressSnapshot> _snapshots = [];

  // ── 0072 server-authoritative analytics (time-filtered) ──
  TimeFilter _filter = TimeFilter.week;
  bool _analyticsLoading = false;
  String? _analyticsError;
  PerformanceSummary? _summary;
  PerformanceSummary? _previousSummary; // for the delta indicator
  List<SubjectWiseBreakdown> _subjectBreakdown = [];
  List<DailyActivity> _dailyActivity = [];
  WeeklyPerformanceReport? _weeklyReport;

  TimeFilter get filter => _filter;
  bool get isAnalyticsLoading => _analyticsLoading;
  String? get analyticsError => _analyticsError;
  PerformanceSummary get summary => _summary ?? PerformanceSummary.empty;
  double? get accuracyDelta => (_summary != null && _previousSummary != null)
      ? _summary!.accuracyPercentage - _previousSummary!.accuracyPercentage
      : null;
  List<SubjectWiseBreakdown> get subjectBreakdown => List.unmodifiable(_subjectBreakdown);
  List<DailyActivity> get dailyActivity => List.unmodifiable(_dailyActivity);
  WeeklyPerformanceReport? get weeklyReport => _weeklyReport;

  /// True on Sundays with no report yet generated for the current week —
  /// drives the "Your Weekly Study Audit is Ready" banner's visibility.
  bool get shouldOfferWeeklyReport {
    if (DateTime.now().weekday != DateTime.sunday) return false;
    if (_weeklyReport == null) return true;
    final now = DateTime.now();
    final weekStart = _weeklyReport!.weekStartDate;
    return now.difference(weekStart).inDays >= 7;
  }

  /// Loads the time-filtered summary/breakdown/daily-activity in parallel.
  /// Also fetches the 'week' summary as a delta baseline when filtering by
  /// week isn't already the active filter, so "+4% vs last week" has a real
  /// number to compare against rather than a guess.
  Future<void> loadAnalytics() async {
    _analyticsLoading = true;
    _analyticsError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _performanceRepo.fetchSummary(_filter),
        _performanceRepo.fetchSubjectBreakdown(_filter),
        _performanceRepo.fetchDailyActivity(),
        _performanceRepo.fetchLatestWeeklyReport(),
      ]);
      _summary = results[0] as PerformanceSummary;
      _subjectBreakdown = results[1] as List<SubjectWiseBreakdown>;
      _dailyActivity = results[2] as List<DailyActivity>;
      _weeklyReport = results[3] as WeeklyPerformanceReport?;
      // Delta baseline: the previous week's own summary (only meaningful
      // when the active filter IS week — a month-over-month or all-time
      // delta against "last week" would be comparing different periods).
      _previousSummary = _filter == TimeFilter.week && _weeklyReport != null
          ? PerformanceSummary(
              filter: 'week',
              totalTestsCompleted: _weeklyReport!.testsCount,
              totalQuestionsAttempted: 0,
              accuracyPercentage: _weeklyReport!.accuracyPct,
              totalStudyMinutes: _weeklyReport!.totalHours * 60,
              speedAvgSecondsPerQ: 0,
            )
          : null;
    } on AppError catch (e) {
      _analyticsError = e.message;
    } catch (e, st) {
      AppLogger.error('PerformanceController.loadAnalytics failed: $e', stackTrace: st);
      _analyticsError = 'Failed to load your performance analytics. Please try again.';
    }
    _analyticsLoading = false;
    notifyListeners();
  }

  Future<void> setFilter(TimeFilter filter) async {
    if (filter == _filter) return;
    _filter = filter;
    await loadAnalytics();
  }

  /// The results behind one Subject Mastery row, for the active filter —
  /// let the caller (a drill-down sheet) surface the real error rather than
  /// swallowing it, since this is triggered by an explicit tap, not a
  /// screen-level load.
  Future<List<SubjectResultEntry>> fetchSubjectResults(String groupKey) =>
      _performanceRepo.fetchSubjectResults(groupKey, _filter);

  Future<void> generateWeeklyReport() async {
    try {
      await _performanceRepo.generateWeeklyReport();
      _weeklyReport = await _performanceRepo.fetchLatestWeeklyReport();
      notifyListeners();
    } on AppError catch (e) {
      _analyticsError = e.message;
      notifyListeners();
    }
  }

  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  String? get error => _error;

  List<RecentTestResult> get recentResults => List.unmodifiable(_recent);
  ProgressSnapshot? get latestSnapshot =>
      _snapshots.isEmpty ? null : _snapshots.first;

  int get testsAttempted => _recent.length;

  double get averageScorePercent {
    final withPct = [
      for (final r in _recent)
        if (r.result.percentage != null) r.result.percentage!,
    ];
    if (withPct.isEmpty) return 0;
    return withPct.reduce((a, b) => a + b) / withPct.length;
  }

  double get averageAccuracy {
    final withAcc = [
      for (final r in _recent)
        if (r.result.accuracy != null) r.result.accuracy!,
    ];
    if (withAcc.isEmpty) return 0;
    return withAcc.reduce((a, b) => a + b) / withAcc.length;
  }

  /// Subject performance merged across every scanned result, sorted by
  /// accuracy ascending — the lowest-accuracy subjects are the weak areas.
  List<SubjectBreakdownItem> get subjectPerformance {
    final byId = <String, ({int attempted, int correct, int wrong, int unanswered, String name})>{};
    for (final r in _recent) {
      final items = ResultAnalyticsMapper.subjects(r.result.subjectBreakdown);
      for (final item in items) {
        final existing = byId[item.subjectId];
        byId[item.subjectId] = (
          attempted: (existing?.attempted ?? 0) + item.attempted,
          correct: (existing?.correct ?? 0) + item.correct,
          wrong: (existing?.wrong ?? 0) + item.wrong,
          unanswered: (existing?.unanswered ?? 0) + item.unanswered,
          name: item.subjectName,
        );
      }
    }
    final merged = [
      for (final entry in byId.entries)
        SubjectBreakdownItem.fromRaw(
          subjectId: entry.key,
          subjectName: entry.value.name,
          data: {
            'attempted': entry.value.attempted,
            'correct': entry.value.correct,
            'wrong': entry.value.wrong,
            'unanswered': entry.value.unanswered,
          },
        ),
    ]..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return merged;
  }

  List<SubjectBreakdownItem> get weakAreas =>
      subjectPerformance.where((s) => s.attempted > 0).take(3).toList();

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([_loadRecentResults(), _loadSnapshots()]);
      _recent = results[0] as List<RecentTestResult>;
      _snapshots = results[1] as List<ProgressSnapshot>;
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('PerformanceController.load failed: $e', stackTrace: st);
      _error = 'Failed to load your performance. Please try again.';
    }

    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  Future<List<RecentTestResult>> _loadRecentResults() async {
    final accessible = await _tests.listAccessible();
    final now = DateTime.now();
    final previous = [
      for (final t in accessible)
        if (TestLifecycle.categorize(
              status: t.status,
              testMode: t.testMode,
              startsAt: t.startsAt,
              endsAt: t.endsAt,
              isSoftDeleted: t.isSoftDeleted,
              now: now,
            ) ==
            ListingCategory.previous)
          t,
    ]..sort((a, b) {
        final aAt = a.endsAt ?? a.startsAt ?? DateTime(0);
        final bAt = b.endsAt ?? b.startsAt ?? DateTime(0);
        return bAt.compareTo(aAt);
      });

    final scanned = previous.take(_maxTestsScanned).toList();
    final rowsPerTest = await Future.wait([
      for (final t in scanned) _results.mineForTest(t.id),
    ]);
    final out = <RecentTestResult>[];
    for (var i = 0; i < scanned.length; i++) {
      final rows = rowsPerTest[i];
      if (rows.isNotEmpty) {
        out.add(RecentTestResult(test: scanned[i], result: rows.first));
      }
    }
    out.sort((a, b) {
      final aAt = a.result.computedAt ?? DateTime(0);
      final bAt = b.result.computedAt ?? DateTime(0);
      return bAt.compareTo(aAt);
    });
    return out;
  }

  Future<List<ProgressSnapshot>> _loadSnapshots() => ProgressService.loadUserProgress();
}
