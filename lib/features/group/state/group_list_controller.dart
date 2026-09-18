import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_invitation.dart';
import '../../../core/models/group_join_request.dart';
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
  List<GroupJoinRequest> _pendingRequests = const [];
  List<GroupInvitation> _invitations = const [];
  bool _invitationsLoading = false;
  String? _invitationsError;
  String? _actingInvitationId;
  String? _actingWithdrawId;
  final Set<String> _pendingCodes = {};
  bool _loading = false;
  bool _loadedOnce = false;
  bool _busy = false;
  String? _error;

  List<Group> get groups => _groups;

  /// The caller's own pending join requests (own rows only, one query, no
  /// per-group reads). A pending request is **not** membership: nothing here
  /// opens a hub. Restricted groups are not readable to a non-member, so a
  /// request cannot be labelled with the group name; it is shown as a count.
  List<GroupJoinRequest> get pendingRequests => _pendingRequests;
  bool get hasPendingRequests => _pendingRequests.isNotEmpty;

  // ── incoming invitations (G5.4): own rows only, one query ──
  /// Pending invitations where the caller is the invitee. Never membership;
  /// never used to open a hub. Group / inviter names are not resolved: a
  /// non-member cannot read a private or restricted group's row.
  List<GroupInvitation> get invitations => _invitations;
  bool get hasInvitations => _invitations.isNotEmpty;
  bool get invitationsLoading => _invitationsLoading;
  String? get invitationsError => _invitationsError;

  /// The invitation an accept/decline is currently running for (single-flight).
  String? get actingInvitationId => _actingInvitationId;

  /// The join request a withdraw is currently running for (single-flight).
  String? get actingWithdrawId => _actingWithdrawId;

  /// Invite codes that produced a pending request in this session, so the
  /// join sheet does not offer a misleading second submission. The server
  /// upsert is idempotent anyway; this only avoids a pointless round trip.
  bool isCodePending(String code) =>
      _pendingCodes.contains(GroupErrors.normalizeInviteCode(code));
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
      await _loadInvitations();
      await _loadPendingRequests();
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

  /// Reads the caller's own pending join requests; a failure is kept
  /// separately so the groups list still renders.
  Future<void> _loadPendingRequests() async {
    try {
      _pendingRequests = await _repo.myPendingJoinRequests();
    } catch (e) {
      AppLogger.warning('Pending join requests unavailable: $e');
      _pendingRequests = const [];
    }
  }

  Future<void> refresh() => load();

  /// Reads the caller's pending invitations; a failure is kept separately so
  /// the groups list still renders and the section can offer Retry.
  Future<void> _loadInvitations() async {
    _invitationsLoading = true;
    _invitationsError = null;
    try {
      _invitations = await _repo.myInvitations();
    } on AppError catch (e) {
      _invitationsError = e.message;
    } catch (e, st) {
      AppLogger.error('Invitations load failed: $e', stackTrace: st);
      _invitationsError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.invitation,
      );
    }
    _invitationsLoading = false;
  }

  Future<void> retryInvitations() async {
    if (_invitationsLoading) return;
    notifyListeners();
    await _loadInvitations();
    notifyListeners();
  }

  /// Accepts via `fn_accept_group_invitation`. Returns the accepted group's
  /// id **only if it appears in `rpc_get_user_groups` after the refresh** —
  /// i.e. membership was confirmed by the server — else null. The invitation
  /// row alone never opens anything.
  Future<String?> acceptInvitation(GroupInvitation invitation) async {
    if (_busy || _actingInvitationId != null) return null;
    final r = await _actOnInvitation<String?>(invitation, () async {
      await _repo.acceptInvitation(invitation.id);
      await load();
      final joined = _groups.any((g) => g.id == invitation.groupId);
      return joined ? invitation.groupId : null;
    });
    return r;
  }

  /// Declines via `fn_decline_group_invitation`. Declining touches no
  /// membership (an invitation is not membership).
  Future<bool> declineInvitation(GroupInvitation invitation) async {
    if (_busy || _actingInvitationId != null) return false;
    final r = await _actOnInvitation(invitation, () async {
      await _repo.declineInvitation(invitation.id);
      await _loadInvitations();
      return true;
    });
    return r ?? false;
  }

  Future<T?> _actOnInvitation<T>(
    GroupInvitation invitation,
    Future<T> Function() body,
  ) async {
    _actingInvitationId = invitation.id;
    _error = null;
    notifyListeners();
    try {
      return await body();
    } on AppError catch (e) {
      _error = e.message;
      // Stale / unavailable (INVITE_NOT_FOUND or anything else): re-read the
      // caller's own rows so the list reflects the server, never a guess.
      await _loadInvitations();
      return null;
    } catch (e, st) {
      AppLogger.error('Invitation action failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.invitation,
      );
      await _loadInvitations();
      return null;
    } finally {
      _actingInvitationId = null;
      notifyListeners();
    }
  }

  /// Withdraws the caller's own pending join request via
  /// `fn_withdraw_join_request`. Touches only `group_join_requests`.
  /// Single-flight; re-reads pending requests after success or failure.
  Future<bool> withdrawJoinRequest(GroupJoinRequest request) async {
    if (_busy || _actingWithdrawId != null || _actingInvitationId != null) {
      return false;
    }
    if (!request.isPending) {
      _error = 'Only a pending request can be withdrawn.';
      notifyListeners();
      return false;
    }
    _actingWithdrawId = request.id;
    _error = null;
    notifyListeners();
    try {
      await _repo.withdrawJoinRequest(request.id);
      // The request carries no invite code, so the session guard cannot be
      // narrowed to one code; clear it so the user can re-apply with any
      // code (the server upsert is idempotent regardless).
      _pendingCodes.clear();
      await _loadPendingRequests();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadPendingRequests();
      return false;
    } catch (e, st) {
      AppLogger.error('Withdraw join request failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.joinRequest,
      );
      await _loadPendingRequests();
      return false;
    } finally {
      _actingWithdrawId = null;
      notifyListeners();
    }
  }

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
  /// `JoinedGroup` ⇒ membership exists (server said so). `JoinRequestFiled`
  /// ⇒ `fn_join_group` returned NULL (restricted group): the pending list is
  /// re-read from the server and the code is remembered as pending.
  Future<JoinOutcome?> joinByCode(String code) async {
    final invalid = GroupErrors.validateInviteCode(code);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return null;
    }
    if (isCodePending(code)) {
      _error = 'Your join request for this code is already pending approval.';
      notifyListeners();
      return null;
    }
    return _run(() async {
      final outcome = await _repo.joinByCode(code);
      if (outcome is JoinRequestFiled) {
        _pendingCodes.add(GroupErrors.normalizeInviteCode(code));
      }
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
