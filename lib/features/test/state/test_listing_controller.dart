import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/test.dart';
import '../data/test_repository.dart';
import '../domain/backend_mapping.dart';
import '../domain/test_kind.dart';
import '../domain/test_lifecycle.dart';
import 'disposable_notifier.dart';

/// Loads the tests visible to the user and buckets them with the shared
/// lifecycle rules. Screens only read [testsFor] / [drafts] and call
/// [load] / [refresh].
class TestListingController extends DisposableNotifier {
  TestListingController({
    TestRepository? repository,
    DateTime Function()? clock,
  }) : _repo = repository ?? const SupabaseTestRepository(),
       _clock = clock ?? DateTime.now;

  final TestRepository _repo;
  final DateTime Function() _clock;

  List<Test> _accessible = const [];
  List<Test> _drafts = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  String? _draftsError;

  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  String? get error => _error;
  String? get draftsError => _draftsError;
  // ── search + kind filter (client-side over the RLS-scoped lists) ──
  String _query = '';
  TestKind? _kindFilter;

  String get query => _query;
  TestKind? get kindFilter => _kindFilter;
  bool get hasActiveFilter => _query.trim().isNotEmpty || _kindFilter != null;

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    notifyListeners();
  }

  /// null = all kinds.
  void setKindFilter(TestKind? kind) {
    if (kind == _kindFilter) return;
    _kindFilter = kind;
    notifyListeners();
  }

  void clearFilters() {
    if (!hasActiveFilter) return;
    _query = '';
    _kindFilter = null;
    notifyListeners();
  }

  /// Drafts matching the current filters (the unfiltered list is [draftsAll]).
  List<Test> get drafts => _applyFilters(_drafts);
  List<Test> get draftsAll => _drafts;

  /// Number of tests in [category] before filtering (for "N hidden by filters").
  int unfilteredCount(ListingCategory category) =>
      category == ListingCategory.drafts
      ? _drafts.length
      : _bucket(category).length;

  List<Test> testsFor(ListingCategory category) {
    // Drafts come from the dedicated creator query, never from bucketing
    // the accessible list (which may also contain the creator's drafts).
    if (category == ListingCategory.drafts) return drafts;
    return _applyFilters(_bucket(category));
  }

  List<Test> _bucket(ListingCategory category) {
    final now = _clock();
    return [
      for (final t in _accessible)
        if (TestLifecycle.categorize(
              status: t.status,
              testMode: t.testMode,
              startsAt: t.startsAt,
              endsAt: t.endsAt,
              isSoftDeleted: t.isSoftDeleted,
              now: now,
            ) ==
            category)
          t,
    ];
  }

  List<Test> _applyFilters(List<Test> source) {
    final q = _query.trim().toLowerCase();
    final k = _kindFilter;
    if (q.isEmpty && k == null) return source;
    return [
      for (final t in source)
        if ((k == null ||
                BackendMapping.fromBackend(t.testMode, t.settings) == k) &&
            (q.isEmpty ||
                t.title.toLowerCase().contains(q) ||
                (t.description ?? '').toLowerCase().contains(q)))
          t,
    ];
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _draftsError = null;
    notifyListeners();

    final results = await Future.wait<Object?>([
      _capture(() async => _accessible = await _repo.listAccessible()),
      _capture(() async => _drafts = await _repo.listMyDrafts()),
    ]);
    _error = results[0] as String?;
    _draftsError = results[1] as String?;

    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  /// Runs [body], returning the user-facing error message or null.
  static Future<String?> _capture(Future<void> Function() body) async {
    try {
      await body();
      return null;
    } on AppError catch (e) {
      return e.message;
    } catch (e, st) {
      AppLogger.error('Listing load failed: $e', stackTrace: st);
      return 'Failed to load tests. Please try again.';
    }
  }
}
