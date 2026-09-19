import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/result.dart';
import '../../../core/models/result_batch.dart';
import '../../../core/models/test.dart';
import '../../../core/services/auth_service.dart';
import '../../test/data/result_repository.dart';
import '../../test/data/test_repository.dart';
import '../../test/domain/test_errors.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';
import '../domain/group_permission.dart';
import '../domain/group_role.dart';
import '../domain/group_test_results.dart';

/// Group test results (G11): the caller's own stored result with
/// deterministic insights, the stored AI coach report (if any), and — for
/// GENERATE_RESULTS / VIEW_GROUP_ANALYTICS holders and the owner — the batch
/// status, every participant's result and the report coverage.
///
/// Opening this screen only READS (`results`, `ai_reports`, `result_batches`,
/// roster, permissions). Result generation and AI-report queuing happen only
/// on explicit manager actions, are single-flight, and are followed by a
/// server re-read. All gates are UX; RLS / RPCs are the boundary.
class GroupTestResultsController extends DisposableNotifier {
  GroupTestResultsController({
    required this.groupId,
    required this.testId,
    ResultRepository? results,
    TestRepository? tests,
    GroupRepository? groups,
    String? currentUserId,
  }) : _results = results ?? const SupabaseResultRepository(),
       _tests = tests ?? const SupabaseTestRepository(),
       _groups = groups ?? const SupabaseGroupRepository(),
       _currentUserId = currentUserId ?? AuthService.currentUser?.id;

  final String groupId;
  final String testId;
  final ResultRepository _results;
  final TestRepository _tests;
  final GroupRepository _groups;
  final String? _currentUserId;

  static const _probe = [
    GroupPermission.generateResults,
    GroupPermission.viewGroupAnalytics,
  ];

  Group? _group;
  Test? _test;
  List<GroupMember> _members = const [];
  GroupPermissions _permissions = GroupPermissions.none;
  List<Result> _results_ = const [];
  AiCoachReport? _myReport;
  List<AiCoachReport> _allReports = const [];
  ResultBatch? _batch;
  CoachReportJob? _job;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _accessDenied = false;
  bool _busy = false;
  String? _error;

  Group? get group => _group;
  Test? get test => _test;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  bool get accessDenied => _accessDenied;
  bool get isBusy => _busy;
  String? get error => _error;
  String? get currentUserId => _currentUserId;
  ResultBatch? get batch => _batch;
  CoachReportJob? get coachJob => _job;
  AiCoachReport? get myReport => _myReport;
  List<AiCoachReport> get allReports => _allReports;

  /// Every `results` row the server returned (RLS-scoped), best first.
  List<Result> get results => _results_;
  bool get hasAnyResults => _results_.isNotEmpty;

  /// The caller's own stored result (latest computed attempt).
  Result? get myResult {
    final mine = _results_.where((r) => r.userId == _currentUserId).toList()
      ..sort((a, b) => (b.computedAt ?? DateTime(0)).compareTo(a.computedAt ?? DateTime(0)));
    return mine.firstOrNull;
  }

  ResultInsights? get myInsights =>
      myResult == null ? null : ResultInsights.from(myResult!, test: _test);

  GroupTestResultsSummary get summary => GroupTestResultsSummary.from(_results_);

  bool get isOwner => GroupRole.fromDb(_group?.userRole).isOwner;
  bool get isCreator =>
      _currentUserId != null && _test?.createdBy == _currentUserId;

  bool get canGenerateResults => GroupResultsAccess.canGenerate(
    isCreator: isCreator,
    hasGenerateResults: _permissions.has(GroupPermission.generateResults),
    isOwner: isOwner,
  );
  bool get canSeeAllResults => GroupResultsAccess.canSeeAllResults(
    hasViewAnalytics: _permissions.has(GroupPermission.viewGroupAnalytics),
    isOwner: isOwner,
  );
  bool get canSeeAllReports => GroupResultsAccess.canSeeAllReports(
    hasGenerateResults: _permissions.has(GroupPermission.generateResults),
    isOwner: isOwner,
  );
  bool get isResultsPhase =>
      _test != null && GroupResultsAccess.isResultsPhase(_test!.status);

  /// Display name from the roster already loaded — "You", the member's
  /// name, or "Former member". No extra profile read.
  String participantLabel(Result r) {
    if (r.userId == _currentUserId) return 'You';
    return _members.where((m) => m.userId == r.userId).firstOrNull?.displayName ??
        'Former member';
  }

  bool hasReport(Result r) => _allReports.any((x) => x.userId == r.userId);

  // ── loading (reads only) ──

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final group = await _groups.groupForMember(groupId);
      if (group == null) {
        _group = null;
        _test = null;
        _results_ = const [];
        _myReport = null;
        _allReports = const [];
        _batch = null;
        _accessDenied = true;
      } else {
        _group = group;
        _accessDenied = false;
        _permissions = await _groups.permissionsFor(groupId, of: _probe);
        _test = await _tests.getById(testId);
        if (_test != null && _test!.groupId != groupId) {
          // A test id from another group is never shown through this group.
          _test = null;
        }
        if (_test == null) {
          _accessDenied = true;
        } else {
          _members = await _groups.members(groupId);
          await _readResults();
        }
      }
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Group test results load failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.load);
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  Future<void> _readResults() async {
    _results_ = await _results.resultsForTest(testId);
    _myReport = await _results.myAiReport(testId);
    _allReports = canSeeAllReports
        ? await _results.allAiReports(testId)
        : [?_myReport];
    _batch = canGenerateResults ? await _results.batchForTest(testId) : null;
  }

  // ── manager actions (explicit, single-flight, server re-read) ──

  Future<bool> _run(bool allowed, String denied, Future<void> Function() body) async {
    if (_busy) return false;
    if (!allowed) {
      _error = denied;
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      await _readResults();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _safeReread();
      return false;
    } catch (e, st) {
      AppLogger.error('Group results action failed: $e', stackTrace: st);
      _error = TestErrors.map(e.toString());
      await _safeReread();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _safeReread() async {
    try {
      await _readResults();
    } catch (_) {
      // keep the last good state; the action error is already surfaced
    }
  }

  /// `rpc_generate_results`: deterministic scoring of every submitted
  /// attempt into `results`; creates/reuses the test's single batch.
  /// No AI is involved.
  Future<bool> generateResults() => _run(
    canGenerateResults,
    'Only the test creator or a member with the results permission can generate results.',
    () async {
      _batch = await _results.generateResults(testId);
    },
  );

  /// Queues AI coach reports for the finished batch (proposed RPC). The
  /// request itself runs no AI; the same request twice returns the same job.
  Future<bool> requestCoachReports() => _run(
    canGenerateResults && (_batch?.isCompleted == true || _batch?.isPartiallyCompleted == true),
    _batch == null
        ? 'Generate results first, then request coach reports.'
        : 'Only the test creator or a member with the results permission can request coach reports.',
    () async {
      _job = await _results.requestCoachReports(testId);
    },
  );

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
