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
  DateTime? _expiresAt;
  int? _maxUses;
  int _useCount = 0;
  bool _loading = false;
  bool _rotating = false;
  bool _settingLimits = false;
  bool _loadedOnce = false;
  String? _error;
  bool _rotated = false;

  /// The current code, or null before load / after a failed load.
  String? get code => _code;

  /// Null means no expiry.
  DateTime? get expiresAt => _expiresAt;

  /// Null means unlimited uses.
  int? get maxUses => _maxUses;
  int get useCount => _useCount;

  bool get isLoading => _loading;
  bool get isRotating => _rotating;
  bool get isSettingLimits => _settingLimits;
  bool get hasLoaded => _loadedOnce;
  bool get isBusy => _loading || _rotating || _settingLimits;
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
      final limits = await _repo.inviteLimits(groupId);
      _code = limits.code;
      _expiresAt = limits.expiresAt;
      _maxUses = limits.maxUses;
      _useCount = limits.useCount;
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
  /// A rotation resets the use counter server-side (new code, new budget).
  Future<bool> rotate() async {
    if (_rotating || _loading) return false;
    _rotating = true;
    _error = null;
    _rotated = false;
    notifyListeners();
    try {
      _code = await _repo.rotateInviteCode(groupId);
      _useCount = 0;
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

  /// Sets expiry/max-uses together (`fn_set_group_invite_limits`); either
  /// null means "no limit" for that one.
  Future<bool> setLimits({DateTime? expiresAt, int? maxUses}) async {
    if (isBusy) return false;
    _settingLimits = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.setInviteLimits(
        groupId: groupId,
        expiresAt: expiresAt,
        maxUses: maxUses,
      );
      _expiresAt = expiresAt;
      _maxUses = maxUses;
      return true;
    } on AppError catch (e) {
      _error = e.message;
      return false;
    } catch (e, st) {
      AppLogger.error('Invite limits update failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.inviteCode,
      );
      return false;
    } finally {
      _settingLimits = false;
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
