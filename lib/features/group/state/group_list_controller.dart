import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';

/// Group Hub entry state: the caller's groups, plus create and join.
/// Every mutation goes through a live function and is followed by a reload,
/// so the list always reflects what the server (RLS) actually returns.
class GroupListController extends DisposableNotifier {
  GroupListController({GroupRepository? repository})
    : _repo = repository ?? const SupabaseGroupRepository();

  final GroupRepository _repo;

  List<Group> _groups = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _busy = false;
  String? _error;

  List<Group> get groups => _groups;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;

  /// True while a create/join is in flight — the screens use it to disable
  /// the submit button, which is what stops a double submission.
  bool get isBusy => _busy;
  String? get error => _error;
  bool get isEmpty => _loadedOnce && _groups.isEmpty && _error == null;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _groups = await _repo.myGroups();
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Group list failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.load);
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  /// Creates a group and returns its id, or null when the call failed
  /// ([error] then holds the message). The server seeds the owner membership
  /// and the default permissions — nothing is written here.
  Future<String?> create({
    required String name,
    String description = '',
    String privacy = 'public',
  }) async {
    final invalid = GroupErrors.validateName(name);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return null;
    }
    return _run(() async {
      final id = await _repo.create(
        name: name,
        description: description,
        privacy: privacy,
      );
      await load();
      return id;
    });
  }

  /// Joins by invite code. Returns the outcome, or null on failure.
  Future<JoinOutcome?> joinByCode(String code) async {
    final invalid = GroupErrors.validateInviteCode(code);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return null;
    }
    return _run(() async {
      final outcome = await _repo.joinByCode(code);
      await load();
      return outcome;
    });
  }

  /// Guards against double submission and funnels errors to [error].
  Future<T?> _run<T>(Future<T> Function() body) async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      return await body();
    } on AppError catch (e) {
      _error = e.message;
      return null;
    } catch (e, st) {
      AppLogger.error('Group action failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.create);
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
