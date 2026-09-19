import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/result.dart';
import '../../../core/models/test.dart';
import '../../../core/services/auth_service.dart';
import '../../test/data/result_repository.dart';
import '../../test/data/test_repository.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';
import '../domain/group_role.dart';
import '../domain/group_test_results.dart';

/// Group test leaderboard (G12): deterministic ranking of participants for
/// a single completed test, derived entirely from stored `results` rows.
/// No AI is called; no score is computed client-side. The same data the
/// server returned under RLS is sorted and presented.
class GroupLeaderboardController extends DisposableNotifier {
  GroupLeaderboardController({
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

  Group? _group;
  Test? _test;
  List<GroupMember> _members = const [];
  List<Result> _results_ = const [];
  List<LeaderboardEntry> _entries = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _accessDenied = false;
  String? _error;

  Group? get group => _group;
  Test? get test => _test;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  bool get accessDenied => _accessDenied;
  String? get error => _error;
  String? get currentUserId => _currentUserId;

  /// Deterministic leaderboard entries, best first.
  List<LeaderboardEntry> get entries => _entries;

  /// The current user's leaderboard entry, if present.
  LeaderboardEntry? get myEntry =>
      _entries.where((e) => e.isCurrentUser).firstOrNull;

  bool get isOwner => GroupRole.fromDb(_group?.userRole).isOwner;

  bool get isMember =>
      isOwner || (_group?.userRole.isNotEmpty == true);

  bool get canSeeLeaderboard => GroupResultsAccess.canSeeLeaderboard(
    isMember: isMember,
    isOwner: isOwner,
  );

  /// Display name from the roster — no extra profile read.
  String _labelFor(String userId) {
    if (userId == _currentUserId) return 'You';
    return _members
            .where((m) => m.userId == userId)
            .firstOrNull
            ?.displayName ??
        'Former member';
  }

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
        _entries = const [];
        _accessDenied = true;
      } else {
        _group = group;
        _accessDenied = false;
        _test = await _tests.getById(testId);
        if (_test != null && _test!.groupId != groupId) {
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
      AppLogger.error('Group leaderboard load failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.load);
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  Future<void> _readResults() async {
    _results_ = await _results.resultsForTest(testId);
    _entries = LeaderboardEntry.fromResults(
      _results_,
      currentUserId: _currentUserId ?? '',
      labelFor: _labelFor,
    );
  }
}
