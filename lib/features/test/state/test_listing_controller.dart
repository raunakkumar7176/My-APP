import 'package:flutter/foundation.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/test.dart';
import '../data/test_repository.dart';
import '../domain/test_lifecycle.dart';

/// Loads the tests visible to the user and buckets them with the shared
/// lifecycle rules. Screens only read [testsFor] / [drafts] and call
/// [load] / [refresh].
class TestListingController extends ChangeNotifier {
  TestListingController({
    TestRepository? repository,
    DateTime Function()? clock,
  })  : _repo = repository ?? const SupabaseTestRepository(),
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
  List<Test> get drafts => _drafts;

  List<Test> testsFor(ListingCategory category) {
    // Drafts come from the dedicated creator query, never from bucketing
    // the accessible list (which may also contain the creator's drafts).
    if (category == ListingCategory.drafts) return _drafts;
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
