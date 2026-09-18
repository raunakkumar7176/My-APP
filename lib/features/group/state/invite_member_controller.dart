import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group_invitation.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/profile_match.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../domain/group_errors.dart';

/// Pre-send state derived from what the hub already knows (roster and the
/// group's invitations). UX only — the server (INSERT policy + UNIQUE) decides.
enum InviteeState {
  canInvite,
  self,
  alreadyMember,
  alreadyPending,
  accepted,
  declined,
  expired,
}

/// Invite-by-student-code flow for one group. Created only by the invite
/// sheet, only for a caller whose server-reported MANAGE_MEMBERS is true.
/// The lookup result lives here and dies with the sheet — no global cache.
class InviteMemberController extends DisposableNotifier {
  InviteMemberController({
    required this.groupId,
    required this.currentUserId,
    required List<GroupMember> members,
    required List<GroupInvitation> invitations,
    GroupRepository? repository,
  }) : _repo = repository ?? const SupabaseGroupRepository(),
       _members = List.of(members),
       _invitations = List.of(invitations);

  final String groupId;
  final String? currentUserId;
  final GroupRepository _repo;
  List<GroupMember> _members;
  List<GroupInvitation> _invitations;

  ProfileMatch? _match;
  bool _searched = false;
  bool _searching = false;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  ProfileMatch? get match => _match;

  /// True after a completed search (so "not found" can be shown).
  bool get hasSearched => _searched;
  bool get isSearching => _searching;
  bool get isSending => _sending;
  bool get isBusy => _searching || _sending;

  /// True after the server confirmed the invitation row was created.
  bool get sent => _sent;
  String? get error => _error;

  /// Refreshes the context the pre-send checks use (after the hub reloads).
  void updateContext({
    required List<GroupMember> members,
    required List<GroupInvitation> invitations,
  }) {
    _members = members;
    _invitations = invitations;
    notifyListeners();
  }

  InviteeState stateFor(ProfileMatch m) {
    if (m.id == currentUserId) return InviteeState.self;
    if (_members.any((x) => x.userId == m.id)) {
      return InviteeState.alreadyMember;
    }
    final inv = _invitations.where((i) => i.inviteeId == m.id).firstOrNull;
    if (inv == null) return InviteeState.canInvite;
    switch (inv.status) {
      case GroupInvitation.statusPending:
        return InviteeState.alreadyPending;
      case GroupInvitation.statusAccepted:
        return InviteeState.accepted;
      case GroupInvitation.statusDeclined:
        return InviteeState.declined;
      case GroupInvitation.statusExpired:
        return InviteeState.expired;
      default:
        return InviteeState.canInvite;
    }
  }

  static String? validateCode(String value) {
    if (value.trim().isEmpty) return 'Enter a student code.';
    return null;
  }

  /// Explicit search (not per keystroke). Single-flight. Trims the input;
  /// the server upper-cases and exact-matches.
  Future<void> search(String code) async {
    if (_searching || _sending) return;
    final invalid = validateCode(code);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return;
    }
    _searching = true;
    _error = null;
    _sent = false;
    _match = null;
    _searched = false;
    notifyListeners();
    try {
      _match = await _repo.findProfileByStudentCode(code.trim());
      _searched = true;
      if (_match == null) _error = 'No user found with that student code.';
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Student code lookup failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.invitation,
      );
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  void clear() {
    _match = null;
    _searched = false;
    _sent = false;
    _error = null;
    notifyListeners();
  }

  /// Sends `{group_id, invitee_id}`; the inviter is the session user. Refuses
  /// locally for self / member / pending / accepted (the server would too);
  /// declined and expired rows are handled by the G5.5 re-invite path, not
  /// by silently replacing them here.
  Future<bool> send() async {
    final m = _match;
    if (m == null || _sending || _searching) return false;
    final state = stateFor(m);
    if (state != InviteeState.canInvite) {
      _error = _explain(state);
      notifyListeners();
      return false;
    }
    _sending = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.sendInvitation(groupId: groupId, inviteeId: m.id);
      _sent = true;
      return true;
    } on AppError catch (e) {
      _error = e.message;
      return false;
    } catch (e, st) {
      AppLogger.error('Send invitation failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.invitation,
      );
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  static String _explain(InviteeState s) {
    switch (s) {
      case InviteeState.self:
        return 'You cannot invite yourself.';
      case InviteeState.alreadyMember:
        return 'This person is already a member of this group.';
      case InviteeState.alreadyPending:
        return 'An invitation for this person is already pending.';
      case InviteeState.accepted:
        return 'This person already accepted an invitation to this group.';
      case InviteeState.declined:
        return 'This person declined an earlier invitation. Use Re-invite in Sent invitations.';
      case InviteeState.expired:
        return 'An earlier invitation to this person is marked expired, which '
            'blocks a new one while that row exists.';
      case InviteeState.canInvite:
        return '';
    }
  }

  @override
  void dispose() {
    _match = null; // drop the third party's identity with the sheet
    super.dispose();
  }
}
