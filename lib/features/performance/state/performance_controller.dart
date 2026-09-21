import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
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
  })  : _tests = testRepository ?? const SupabaseTestRepository(),
        _results = resultRepository ?? const SupabaseResultRepository();

  final TestRepository _tests;
  final ResultRepository _results;

  static const _maxTestsScanned = 15;

  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<RecentTestResult> _recent = [];
  List<ProgressSnapshot> _snapshots = [];

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

    final out = <RecentTestResult>[];
    for (final t in previous.take(_maxTestsScanned)) {
      final rows = await _results.mineForTest(t.id);
      if (rows.isNotEmpty) out.add(RecentTestResult(test: t, result: rows.first));
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
