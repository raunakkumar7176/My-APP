import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';

/// Invite-code state for one group. Owned by the settings screen only and
/// created only when the caller holds GROUP_SETTINGS or is the owner, so the
/// code is never loaded for anyone else and never cached beyond that screen.
/// The server (`groups` RLS, `fn_reset_group_invite`) stays the authority;
/// the permission gate here only decides whether to ask.
class InviteCodeController extends DisposableNotifier {
  InviteCodeController({required this.groupId, GroupRepository? repository})
    : _repo = repository ?? const SupabaseGroupRepository();

  final String groupId;
  final GroupRepository _repo;

  String? _code;
  bool _loading = false;
  bool _rotating = false;
  bool _loadedOnce = false;
  String? _error;
  bool _rotated = false;

  /// The current code, or null before load / after a failed load.
  String? get code => _code;
  bool get isLoading => _loading;
  bool get isRotating => _rotating;
  bool get hasLoaded => _loadedOnce;
  bool get isBusy => _loading || _rotating;
  String? get error => _error;

  /// True only after the most recent rotation succeeded; cleared by any
  /// later action so a failed rotation never leaves a stale success state.
  bool get justRotated => _rotated;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _rotated = false;
    notifyListeners();
    try {
      _code = await _repo.inviteCode(groupId);
    } on AppError catch (e) {
      _code = null;
      _error = e.message;
    } catch (e, st) {
      // Log the failure, never the code.
      AppLogger.error('Invite code load failed: $e', stackTrace: st);
      _code = null;
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.inviteCode,
      );
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> retry() => load();

  /// Rotates via the server and shows what it returned. Single-flight: a
  /// second call while one is running is dropped. On failure the previous
  /// code stays displayed (it is still the valid one) and [error] is set.
  Future<bool> rotate() async {
    if (_rotating || _loading) return false;
    _rotating = true;
    _error = null;
    _rotated = false;
    notifyListeners();
    try {
      _code = await _repo.rotateInviteCode(groupId);
      _rotated = true;
      return true;
    } on AppError catch (e) {
      _error = e.message;
      return false;
    } catch (e, st) {
      AppLogger.error('Invite code rotation failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.inviteCode,
      );
      return false;
    } finally {
      _rotating = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _code = null; // drop the secret with the screen
    super.dispose();
  }
}
