import 'dart:async';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_announcement.dart';
import '../../../core/models/group_invitation.dart';
import '../../../core/models/group_join_request.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/group_message.dart';
import '../../../core/models/group_rule.dart';
import '../../../core/models/test.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../test/data/test_repository.dart';
import '../../test/state/disposable_notifier.dart';
import '../data/group_repository.dart';
import '../data/notification_repository.dart';
import '../domain/group_controls.dart';
import '../domain/group_errors.dart';
import '../domain/group_privacy.dart';
import '../domain/group_permission.dart';
import '../domain/group_role.dart';
import '../domain/group_test_management.dart';

/// One group's core state: profile, roster, the caller's own role, and the
/// membership mutations of G1 (leave, remove member, edit basics).
///
/// Access rule: the hub opens only for a member. A public group's row is
/// readable by any signed-in user under the live "public groups are
/// discoverable" policy, so readability is never treated as access.
class GroupHubController extends DisposableNotifier {
  GroupHubController({
    required this.groupId,
    GroupRepository? repository,
    String? currentUserId,
    this.notifications,
    this.tests,
    DateTime Function()? now,
  }) : _repo = repository ?? const SupabaseGroupRepository(),
       _currentUserId = currentUserId ?? AuthService.currentUser?.id,
       _now = now ?? DateTime.now;

  final String groupId;
  final GroupRepository _repo;
  final String? _currentUserId;
  final DateTime Function() _now;

  /// G16: the live notification inbox, when the hub is wired with one (the
  /// hub screen passes the Supabase repository; tests inject a fake or
  /// nothing). Null means no badge, never a guessed count.
  final NotificationRepository? notifications;

  /// Overview's upcoming-test preview source, when the hub is wired with
  /// one (the hub screen passes the Supabase repository; tests inject a
  /// fake or nothing). Null means no preview, never a guessed test list —
  /// same nullable-and-skip pattern as [notifications].
  final TestRepository? tests;

  /// The data source this hub uses, so flows opened from it (invite sheet)
  /// share it instead of constructing a second one.
  GroupRepository get repository => _repo;

  Group? _group;
  List<GroupMember> _members = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _busy = false;
  bool _accessDenied = false;
  bool _leftGroup = false;
  GroupPermissions _permissions = GroupPermissions.none;

  // ── manager join-request queue (G5.3) ──
  List<GroupJoinRequest> _joinRequests = const [];
  bool _joinRequestsLoading = false;
  String? _joinRequestsError;
  String? _actingRequestId;

  // ── outgoing / managed invitations (G5.5) ──
  List<GroupInvitation> _outgoingInvitations = const [];
  bool _outgoingLoading = false;
  String? _outgoingError;
  String? _actingInvitationId;

  /// Invitations of this group, all statuses, loaded only when the
  /// server-reported MANAGE_MEMBERS is true. Kept separate from the incoming
  /// (invitee) list and from join requests — different lifecycle entities.
  List<GroupInvitation> get outgoingInvitations => _outgoingInvitations;
  bool get outgoingLoading => _outgoingLoading;
  String? get outgoingError => _outgoingError;
  String? get actingInvitationId => _actingInvitationId;

  // ── group rules (G6) ──
  List<GroupRule> _rules = const [];
  bool _rulesLoading = false;
  String? _rulesError;
  String? _actingRuleId;
  bool _rulesSaving = false;

  List<GroupRule> get rules => _rules;
  bool get rulesLoading => _rulesLoading;
  String? get rulesError => _rulesError;
  String? get actingRuleId => _actingRuleId;
  bool get rulesSaving => _rulesSaving;
  bool get hasRules => _rules.isNotEmpty;

  // ── group announcements (G7) ──
  List<GroupAnnouncement> _announcements = const [];
  bool _announcementsLoading = false;
  String? _announcementsError;
  String? _actingAnnouncementId;
  bool _announcementSaving = false;

  /// Newest first, exactly as the server returned them (member-only rows).
  List<GroupAnnouncement> get announcements => _announcements;
  bool get announcementsLoading => _announcementsLoading;
  String? get announcementsError => _announcementsError;
  String? get actingAnnouncementId => _actingAnnouncementId;
  bool get announcementSaving => _announcementSaving;
  bool get hasAnnouncements => _announcements.isNotEmpty;

  // ── group chat (G8) ──
  /// Oldest → newest for display; the server window is newest-first.
  List<GroupMessage> _messages = const [];
  bool _messagesLoading = false;
  bool _olderLoading = false;
  String? _messagesError;
  bool _sending = false;
  bool _hasOlder = false;

  List<GroupMessage> get messages => _messages;
  bool get messagesLoading => _messagesLoading;
  bool get olderMessagesLoading => _olderLoading;
  String? get messagesError => _messagesError;
  bool get sending => _sending;
  bool get hasOlderMessages => _hasOlder;
  bool get hasMessages => _messages.isNotEmpty;

  // ── Realtime (Group Hub redesign): live INSERT/UPDATE on group_messages,
  // via Supabase Realtime (already publishes this table server-side — see
  // migrations 0037/0049 — this wiring is the first client-side use of
  // it). One subscription per controller instance, started once the group
  // has loaded, stopped exactly once in [dispose]. ──
  GroupMessageSubscription? _messageSub;
  bool _realtimeConnected = false;

  /// False while the channel is joining/reconnecting — drives a small
  /// "Reconnecting…" indicator; never a reason to hide messages already
  /// loaded, only to explain why new ones might be delayed.
  bool get isRealtimeConnected => _realtimeConnected;

  void _subscribeRealtime() {
    if (_messageSub != null) return; // already subscribed for this instance
    _messageSub = _repo.subscribeToMessages(
      groupId: groupId,
      onInsert: _onRealtimeInsert,
      onUpdate: _onRealtimeUpdate,
      onConnectionChange: (connected) {
        _realtimeConnected = connected;
        notifyListeners();
      },
    );
  }

  /// Upserts `message_reads.last_read_at = now()` for this group. Best
  /// effort: a failure here must never surface as a hub-load error, since
  /// unread state is a list-screen convenience, not something the hub
  /// itself displays.
  Future<void> _markRead() async {
    try {
      await _repo.markGroupRead(groupId);
    } catch (e, st) {
      AppLogger.warning('markGroupRead($groupId) failed: $e', error: e, stackTrace: st);
    }
  }

  /// Merges a realtime-delivered message into the loaded window, de-duped
  /// by id — the same row can otherwise arrive twice (once from this
  /// device's own post-send `_loadMessages()` re-read, once from the
  /// realtime echo of that same INSERT) without ever becoming a visible
  /// duplicate bubble.
  void _onRealtimeInsert(GroupMessage message) {
    if (message.groupId != groupId) return; // defensive; filter already scopes this
    if (_messages.any((m) => m.id == message.id)) return;
    _messages = [..._messages, message]
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    notifyListeners();
  }

  /// Applies a realtime UPDATE (currently only soft-delete sets
  /// `deleted_at`) to the matching loaded message, in place.
  void _onRealtimeUpdate(GroupMessage message) {
    if (message.groupId != groupId) return;
    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx == -1) return; // not in the currently-loaded window; ignore
    _messages = [
      for (var i = 0; i < _messages.length; i++)
        if (i == idx) message else _messages[i],
    ];
    notifyListeners();
  }

  Future<void> _unsubscribeRealtime() async {
    final sub = _messageSub;
    _messageSub = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (e) {
        AppLogger.warning('Realtime unsubscribe failed (non-fatal): $e');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_unsubscribeRealtime());
    _clearActiveGroupForPush();
    super.dispose();
  }

  /// Tells [PushNotificationService] this group's chat is on screen, so a
  /// foreground `GROUP_MESSAGE` push about it is skipped (realtime already
  /// shows it here) — purely a client-side toast-dedupe convenience, never
  /// a substitute for the server's own notification rules. Best effort:
  /// this must never affect the hub itself, so any failure (e.g. the
  /// plugin isn't available in a test host) is swallowed.
  void _setActiveGroupForPush() {
    try {
      PushNotificationService.instance.activeGroupId = groupId;
    } catch (e) {
      AppLogger.warning('Could not set active group for push dedupe: $e');
    }
  }

  void _clearActiveGroupForPush() {
    try {
      if (PushNotificationService.instance.activeGroupId == groupId) {
        PushNotificationService.instance.activeGroupId = null;
      }
    } catch (e) {
      AppLogger.warning('Could not clear active group for push dedupe: $e');
    }
  }

  // ── G16: notification unread badge ──
  int? _unreadNotifications;

  /// The caller's unread `notifications` rows for this group (live
  /// `read_at IS NULL`, `data->>'group_id'`), or null when the hub has no
  /// notification repository or the count could not be read — the badge is
  /// then simply not shown. Re-read on every [load] / [refresh], so it never
  /// goes stale after the notification screen marked rows read.
  int? get unreadNotifications => _unreadNotifications;
  bool get hasUnreadNotifications => (_unreadNotifications ?? 0) > 0;
  bool get hasNotifications => notifications != null;

  Future<void> _loadUnreadNotifications() async {
    final repo = notifications;
    if (repo == null) return;
    try {
      _unreadNotifications = await repo.unreadCount(groupId);
    } catch (e) {
      // A badge is never worth an error state; the inbox screen reports.
      AppLogger.warning('Unread notification count unavailable: $e');
      _unreadNotifications = null;
    }
  }

  // ── Overview: upcoming-test preview + recent activity ──
  // Both best-effort, additive to the existing hub load — a failure in
  // either never blocks the hub itself from opening (same pattern as
  // `_loadUnreadNotifications`).

  List<Test> _groupTests = const [];
  List<AppNotification>? _recentActivity;

  /// The next test in [GroupTestSection.upcoming] (earliest `startsAt`
  /// first), or null when there is none. Reuses the exact same section
  /// logic `GroupTestsController`/`group_tests_screen.dart` use — no
  /// second definition of "upcoming".
  Test? get upcomingTest {
    final now = _now();
    final upcoming = [
      for (final t in _groupTests)
        if (GroupTestManagement.sectionFor(t, now) == GroupTestSection.upcoming)
          t,
    ]..sort((a, b) {
      final as_ = a.startsAt;
      final bs = b.startsAt;
      if (as_ == null && bs == null) return 0;
      if (as_ == null) return 1;
      if (bs == null) return -1;
      return as_.compareTo(bs);
    });
    return upcoming.isEmpty ? null : upcoming.first;
  }

  int _countInSection(GroupTestSection s) {
    final now = _now();
    return _groupTests
        .where((t) => GroupTestManagement.sectionFor(t, now) == s)
        .length;
  }

  int get liveTestCount => _countInSection(GroupTestSection.live);
  int get upcomingTestCount => _countInSection(GroupTestSection.upcoming);
  int get previousTestCount => _countInSection(GroupTestSection.previous);

  Future<void> _loadGroupTests() async {
    final repo = tests;
    if (repo == null) return;
    try {
      _groupTests = await repo.listForGroup(groupId);
    } catch (e) {
      AppLogger.warning('Group tests preview unavailable: $e');
      _groupTests = const [];
    }
  }

  /// The caller's own recent notifications for this group (existing
  /// `notifications.forGroup`, own rows only — see that method's doc for
  /// why this is a personal activity view, not a shared group timeline: no
  /// member-readable cross-user audit log exists for group events today).
  List<AppNotification>? get recentActivity => _recentActivity;

  Future<void> _loadRecentActivity() async {
    final repo = notifications;
    if (repo == null) return;
    try {
      _recentActivity = await repo.forGroup(groupId, limit: 5);
    } catch (e) {
      AppLogger.warning('Recent activity unavailable: $e');
      _recentActivity = null;
    }
  }

  // ── G14: management controls & role permissions ──
  GroupRolePermissions _rolePermissions = GroupRolePermissions.empty;
  bool _rolePermissionsLoading = false;
  String? _rolePermissionsError;

  /// Which management controls may be offered (server-reported permissions
  /// plus the owner bypass). UX only; every mutation is decided live.
  GroupControls get controls =>
      GroupControls(permissions: _permissions, isOwner: isOwner);

  /// True when any management surface applies to the caller. A plain member
  /// with no seeded permission never sees the Manage section.
  bool get hasManagementControls => controls.hasAnyManagement;

  /// `role_permissions` policy "manage roles perms": MANAGE_ROLES (owner via
  /// the function's bypass; accepted locally too so a failed probe never
  /// hides the owner's controls).
  bool get canManageRolePermissions => controls.canManageRolePermissions;

  /// The group's `role_permissions` rows, loaded only for a caller who may
  /// manage them (see [loadRolePermissions]).
  GroupRolePermissions get rolePermissions => _rolePermissions;
  bool get rolePermissionsLoading => _rolePermissionsLoading;
  String? get rolePermissionsError => _rolePermissionsError;

  /// Reads the matrix from the server. Never called for a caller without the
  /// manage-roles control; single-flight.
  Future<void> loadRolePermissions() async {
    if (!canManageRolePermissions || _rolePermissionsLoading) return;
    _rolePermissionsLoading = true;
    _rolePermissionsError = null;
    notifyListeners();
    try {
      _rolePermissions = await _repo.rolePermissions(groupId);
    } on AppError catch (e) {
      _rolePermissionsError = e.message;
    } catch (e, st) {
      AppLogger.error('Role permissions load failed: $e', stackTrace: st);
      _rolePermissionsError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.rolePermission,
      );
    }
    _rolePermissionsLoading = false;
    notifyListeners();
  }

  /// Grants or revokes one `(role, permission)` for this group. Client
  /// invariants (the live policy and PK enforce the rest): only a role from
  /// [RolePermissionRules.editableRoles] — never `owner` (bypass) and never
  /// `member` — and only a live permission value. `MANAGE_ROLES` is decided
  /// by the server; the client merely does not offer the action without it.
  /// After success the matrix **and** the caller's own probes are re-read
  /// from the server (a leader changing the leader row changes themselves).
  Future<bool> setRolePermission(
    GroupRole role,
    GroupPermission permission, {
    required bool granted,
  }) async {
    if (!canManageRolePermissions) {
      _error = GroupErrors.map(
        'NOT_AUTHORIZED',
        context: GroupErrorContext.rolePermission,
      );
      notifyListeners();
      return false;
    }
    if (!RolePermissionRules.canEditRole(role)) {
      _error = role.isOwner
          ? 'The owner always holds every permission; nothing to change.'
          : 'Permissions cannot be assigned to the ${role.label} role here.';
      notifyListeners();
      return false;
    }
    if (!RolePermissionRules.canEditPermission(permission)) {
      _error = 'That permission cannot be changed here.';
      notifyListeners();
      return false;
    }
    if (_rolePermissions.has(role, permission) == granted) return true; // no-op
    final ok = await _run(
      GroupErrorContext.rolePermission,
      () => _repo.setRolePermission(
        groupId: groupId,
        role: role,
        permission: permission,
        granted: granted,
      ),
    );
    // Server re-read either way: on failure the matrix must not show a
    // toggle the server refused.
    await loadRolePermissions();
    if (ok) await load();
    return ok;
  }

  /// Sender label from the roster already loaded: "You", the member's
  /// display name, "System" for server notices (null sender), or "Former
  /// member" when the sender is no longer in the roster.
  String messageSenderLabel(GroupMessage m) {
    final sender = m.senderId;
    if (sender == null) return 'System';
    if (sender == _currentUserId) return 'You';
    return _members.where((x) => x.userId == sender).firstOrNull?.displayName ??
        'Former member';
  }

  /// Author label from the roster already loaded (no extra profile read):
  /// "You", the member's display name, or null when the author is no longer
  /// a member — then nothing is shown rather than a guessed identity.
  String? announcementAuthorLabel(GroupAnnouncement a) {
    if (a.authorId == _currentUserId) return 'You';
    return _members.where((m) => m.userId == a.authorId).firstOrNull?.displayName;
  }

  /// Re-invite is offered only for a `declined` row whose invitee is not
  /// already in the roster. Pending/accepted/expired rows are never re-sent.
  bool canReinvite(GroupInvitation inv) =>
      canManageMembers &&
      inv.status == GroupInvitation.statusDeclined &&
      !_members.any((m) => m.userId == inv.inviteeId);

  /// Pending requests for this group. Loaded only when the server-reported
  /// MANAGE_MEMBERS is true; otherwise never queried. A requester is not a
  /// member and their profile is not readable, so rows carry no identity.
  List<GroupJoinRequest> get joinRequests => _joinRequests;
  int get pendingRequestCount => _joinRequests.length;
  bool get joinRequestsLoading => _joinRequestsLoading;
  String? get joinRequestsError => _joinRequestsError;

  /// Request currently being decided (single-flight per request; other
  /// items stay enabled unless a global mutation is running).
  String? get actingRequestId => _actingRequestId;
  String? _error;

  Group? get group => _group;
  List<GroupMember> get members => _members;

  // ── members hub: local search + role filter over the permitted roster ──
  String _memberQuery = '';
  GroupRole? _roleFilter;

  String get memberQuery => _memberQuery;
  GroupRole? get roleFilter => _roleFilter;
  bool get hasMemberFilter =>
      _memberQuery.trim().isNotEmpty || _roleFilter != null;

  void setMemberQuery(String value) {
    if (value == _memberQuery) return;
    _memberQuery = value;
    notifyListeners();
  }

  /// null = all roles.
  void setRoleFilter(GroupRole? role) {
    if (role == _roleFilter) return;
    _roleFilter = role;
    notifyListeners();
  }

  void clearMemberFilters() {
    if (!hasMemberFilter) return;
    _memberQuery = '';
    _roleFilter = null;
    notifyListeners();
  }

  /// Roster narrowed by [memberQuery] (case-insensitive, trimmed; name first,
  /// then student code) and [roleFilter]. Purely local over rows RLS already
  /// returned — it never widens what the server permitted.
  List<GroupMember> get filteredMembers {
    final q = _memberQuery.trim().toLowerCase();
    final r = _roleFilter;
    if (q.isEmpty && r == null) return _members;
    return [
      for (final m in _members)
        if ((r == null || GroupRole.fromDb(m.role) == r) &&
            (q.isEmpty ||
                m.displayName.toLowerCase().contains(q) ||
                (m.studentCode ?? '').toLowerCase().contains(q)))
          m,
    ];
  }

  /// The caller's own membership row, when loaded.
  GroupMember? get me =>
      _members.where((m) => m.userId == _currentUserId).firstOrNull;
  bool get isLoading => _loading;
  bool get hasLoaded => _loadedOnce;
  bool get isBusy => _busy;
  String? get error => _error;
  String? get currentUserId => _currentUserId;

  /// True when the group does not exist, was deleted, or the caller is not
  /// (or is no longer) a member of it. The screen shows one honest state for
  /// all three: the server does not distinguish them, and guessing would leak
  /// the existence of groups the caller cannot see.
  bool get accessDenied => _accessDenied;

  /// True once the caller has left this group in this session.
  bool get hasLeft => _leftGroup;

  GroupRole get myRole => GroupRole.fromDb(_group?.userRole);
  GroupPrivacy get privacy => GroupPrivacy.fromDb(_group?.privacy);
  bool get isOwner => myRole.isOwner;
  int get memberCount => _group?.memberCount ?? _members.length;

  /// The caller's server-reported permissions in this group (one
  /// `fn_has_permission` probe per value; owner is true for all of them by the
  /// function's own owner branch). UX mirror only — the server decides.
  GroupPermissions get permissions => _permissions;

  /// Server-confirmed `MANAGE_MEMBERS`. Used only to decide whether to offer
  /// the action.
  bool get canManageMembers => _permissions.canManageMembers;

  /// Server-confirmed `MANAGE_ROLES`.
  bool get canManageRoles => _permissions.canManageRoles;

  /// Server-confirmed `GROUP_SETTINGS`, which is exactly the live `groups`
  /// UPDATE policy (`GROUP_SETTINGS` OR owner). Owner is also accepted locally
  /// so a failed probe never hides the owner's own settings.
  bool get canEditBasics => _permissions.canEditSettings || isOwner;

  /// Server-confirmed `SEND_ANNOUNCEMENT` (owner true via the function's own
  /// bypass) — exactly the live `group_announcements` INSERT / manage gate.
  /// Owner accepted locally too so a failed probe never hides the owner's
  /// controls; the server still decides.
  bool get canSendAnnouncement =>
      _permissions.has(GroupPermission.sendAnnouncement) || isOwner;

  /// Roles an authorised manager may assign through ordinary role editing.
  /// `owner` is never assignable here: it is an invariant, not a permission
  /// (no ownership-transfer mechanism exists live).
  static const assignableRoles = [
    GroupRole.leader,
    GroupRole.moderator,
    GroupRole.member,
  ];

  /// The owner cannot leave: live `trg_owner_guard` (fn_prevent_owner_removal,
  /// verified in the G3 audit) raises CANNOT_REMOVE_OWNER on deleting an owner
  /// row, and no ownership-transfer function exists. The client refuses up
  /// front with the same outcome the server would give.
  bool get canLeave => _group != null && !isOwner;

  String get leaveBlockedReason =>
      'You own this group. Ownership transfer is not available yet, so the '
      'owner cannot leave. Delete the group or transfer ownership once that '
      'is supported.';

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final group = await _repo.groupForMember(groupId);
      if (group == null) {
        _group = null;
        _members = const [];
        _accessDenied = true;
        // G14: a removed manager must not keep stale controls — the
        // server-reported permissions and matrix are dropped with access.
        _permissions = GroupPermissions.none;
        _rolePermissions = GroupRolePermissions.empty;
        _unreadNotifications = null;
      } else {
        _group = group;
        _accessDenied = false;
        _members = await _repo.members(groupId);
        // G14: every live permission is probed (one `fn_has_permission`
        // call each, in parallel) so the Manage section shows exactly what
        // the server grants — test, results and analytics controls included.
        _permissions = await _repo.permissionsFor(
          groupId,
          of: GroupPermission.live,
        );
        // Manager queue: loaded only when the server says MANAGE_MEMBERS.
        if (_permissions.canManageMembers) {
          await _loadJoinRequests();
          await _loadOutgoingInvitations();
        } else {
          _joinRequests = const [];
          _joinRequestsError = null;
          _outgoingInvitations = const [];
          _outgoingError = null;
        }
        // Rules: loaded for all members (RLS enforces member-only read).
        await _loadRules();
        // Announcements: loaded for all members (RLS: member-only read).
        await _loadAnnouncements();
        // Chat: latest window for all members (RLS: member-only read).
        await _loadMessages();
        // G16: unread badge (own `notifications` rows; one count request).
        await _loadUnreadNotifications();
        // Overview: upcoming-test preview + recent (own) activity — both
        // best-effort, reusing the existing tests/notifications RPCs.
        await _loadGroupTests();
        await _loadRecentActivity();
        // Realtime: start (or, on a refresh, no-op — already subscribed)
        // once membership is confirmed, so a message from another member
        // appears here without any manual refresh.
        _subscribeRealtime();
        // Unread: opening the hub is "read" for chat purposes (0027's
        // `message_reads`). Fire-and-forget — the groups list re-derives
        // unread counts itself on its own next load, and a failure here
        // must never block the hub from opening.
        unawaited(_markRead());
        _setActiveGroupForPush();
      }
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('Group hub load failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.load);
    }
    _loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refresh() => load();

  Future<void> _loadJoinRequests() async {
    _joinRequestsLoading = true;
    _joinRequestsError = null;
    try {
      _joinRequests = await _repo.pendingJoinRequests(groupId);
    } on AppError catch (e) {
      _joinRequestsError = e.message;
    } catch (e, st) {
      AppLogger.error('Join requests load failed: $e', stackTrace: st);
      _joinRequestsError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.joinRequest,
      );
    }
    _joinRequestsLoading = false;
  }

  Future<void> _loadOutgoingInvitations() async {
    _outgoingLoading = true;
    _outgoingError = null;
    try {
      _outgoingInvitations = await _repo.groupInvitations(groupId);
    } on AppError catch (e) {
      _outgoingError = e.message;
    } catch (e, st) {
      AppLogger.error('Outgoing invitations load failed: $e', stackTrace: st);
      _outgoingError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.invitation,
      );
    }
    _outgoingLoading = false;
  }

  Future<void> retryOutgoingInvitations() async {
    if (!canManageMembers || _outgoingLoading) return;
    notifyListeners();
    await _loadOutgoingInvitations();
    notifyListeners();
  }

  /// Cancels a pending invitation (exact-row DELETE under the live policy).
  /// The list is re-read from the server afterwards, success or failure.
  Future<bool> cancelInvitation(GroupInvitation inv) async {
    if (!inv.isPending) {
      _error = 'Only a pending invitation can be cancelled.';
      notifyListeners();
      return false;
    }
    return _actOnInvitation(inv, () => _repo.cancelInvitation(inv.id));
  }

  /// Re-invites a declined invitee: DELETE the declined row, INSERT a new
  /// pending one (two steps; the repository reports an incomplete second step
  /// explicitly). Never offered for pending / accepted / expired rows or for
  /// someone who is already a member.
  Future<bool> reinvite(GroupInvitation inv) async {
    if (!canReinvite(inv)) {
      _error = inv.status == GroupInvitation.statusDeclined
          ? 'This person is already a member.'
          : 'Only a declined invitation can be sent again.';
      notifyListeners();
      return false;
    }
    return _actOnInvitation(inv, () => _repo.reinvite(inv));
  }

  Future<bool> _actOnInvitation(
    GroupInvitation inv,
    Future<void> Function() body,
  ) async {
    if (!canManageMembers) {
      _error = GroupErrors.map(
        'NOT_AUTHORIZED',
        context: GroupErrorContext.invitation,
      );
      notifyListeners();
      return false;
    }
    if (_actingInvitationId == inv.id || _busy) return false;
    _actingInvitationId = inv.id;
    _error = null;
    notifyListeners();
    try {
      await body();
      await _loadOutgoingInvitations();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadOutgoingInvitations(); // server truth, never a guess
      return false;
    } catch (e, st) {
      AppLogger.error('Invitation action failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.invitation,
      );
      await _loadOutgoingInvitations();
      return false;
    } finally {
      _actingInvitationId = null;
      notifyListeners();
    }
  }

  Future<void> retryJoinRequests() async {
    if (!canManageMembers || _joinRequestsLoading) return;
    notifyListeners();
    await _loadJoinRequests();
    notifyListeners();
  }

  /// Approves or declines via `fn_approve_group_join_request(id, approve)`.
  /// Only the request id is sent — the server derives the group from the
  /// row and checks MANAGE_MEMBERS there. On approval the whole hub reloads
  /// (members, count, queue) so the new member comes from the server row the
  /// function inserted; on decline only the queue is re-read. Any error is
  /// mapped and followed by a server re-read — nothing is fabricated.
  Future<bool> decideJoinRequest(
    GroupJoinRequest request, {
    required bool approve,
  }) async {
    if (!canManageMembers) {
      _error = GroupErrors.map(
        'NOT_AUTHORIZED',
        context: GroupErrorContext.joinRequest,
      );
      notifyListeners();
      return false;
    }
    if (_actingRequestId == request.id || _busy) return false;
    _actingRequestId = request.id;
    _error = null;
    notifyListeners();
    try {
      await _repo.decideJoinRequest(request.id, approve: approve);
      if (approve) {
        await load();
      } else {
        await _loadJoinRequests();
      }
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadJoinRequests();
      return false;
    } catch (e, st) {
      AppLogger.error('Join request decision failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.joinRequest,
      );
      await _loadJoinRequests();
      return false;
    } finally {
      _actingRequestId = null;
      notifyListeners();
    }
  }

  /// Leaves the group. Returns true when the membership is gone.
  Future<bool> leave() async {
    if (!canLeave) {
      _error = leaveBlockedReason;
      notifyListeners();
      return false;
    }
    final ok = await _run(GroupErrorContext.leave, () => _repo.leave(groupId));
    if (ok) {
      _leftGroup = true;
      _accessDenied = true;
      _group = null;
      _members = const [];
      notifyListeners();
    }
    return ok;
  }

  /// True only for a solo group — its owner, with no other member rows.
  /// Mirrors `rpc_delete_group`'s own check exactly; the server re-verifies
  /// regardless (this only decides whether to offer the action).
  bool get canDeleteGroup =>
      _group != null && isOwner && _members.every((m) => m.userId == _currentUserId);

  /// Deletes a solo group (Phase 7). Hard delete — see
  /// `migrations/GROUP_HUB_rpc_delete_group.sql` for why `groups` uses hard
  /// delete rather than the soft-delete pattern `tests` uses.
  Future<bool> deleteGroup() async {
    if (!canDeleteGroup) {
      _error = 'This group still has other members. Remove them first, or '
          'transfer ownership, before deleting it.';
      notifyListeners();
      return false;
    }
    final ok = await _run(
      GroupErrorContext.update,
      () => _repo.deleteGroup(groupId),
    );
    if (ok) {
      _accessDenied = true;
      _group = null;
      _members = const [];
      notifyListeners();
    }
    return ok;
  }

  /// Changes another member's role. Client invariants (each also enforced by
  /// the live "role changes" policy / trg_owner_guard, verified in the G3
  /// audit): never yourself, never the owner, never *to* owner, only a live
  /// assignable role, and only a user who is in this group's roster.
  /// `MANAGE_ROLES` is enforced server-side; the client merely does not offer
  /// the action without it.
  Future<bool> changeRole(String userId, GroupRole role) async {
    if (!canManageRoles) {
      _error = GroupErrors.map(
        'NOT_AUTHORIZED',
        context: GroupErrorContext.changeRole,
      );
      notifyListeners();
      return false;
    }
    if (userId == _currentUserId) {
      _error = 'You cannot change your own role.';
      notifyListeners();
      return false;
    }
    final target = _members.where((m) => m.userId == userId).firstOrNull;
    if (target == null) {
      _error = 'That user is not a member of this group.';
      notifyListeners();
      return false;
    }
    if (GroupRole.fromDb(target.role).isOwner) {
      _error = 'The group owner cannot be demoted.';
      notifyListeners();
      return false;
    }
    if (!assignableRoles.contains(role)) {
      _error = 'That role cannot be assigned here.';
      notifyListeners();
      return false;
    }
    if (GroupRole.fromDb(target.role) == role) return true; // no-op
    final ok = await _run(
      GroupErrorContext.changeRole,
      () => _repo.setMemberRole(groupId: groupId, userId: userId, role: role),
    );
    if (ok) await load();
    return ok;
  }

  /// Removes another member. The server enforces `MANAGE_MEMBERS`; this only
  /// avoids offering an action that is certain to fail, and never lets the
  /// owner be removed (the owner row must survive for the group to have one).
  Future<bool> removeMember(String userId) async {
    if (userId == _currentUserId) {
      _error = 'Use Leave group to remove yourself.';
      notifyListeners();
      return false;
    }
    final target = _members.where((m) => m.userId == userId).firstOrNull;
    if (target != null && GroupRole.fromDb(target.role).isOwner) {
      _error = 'The group owner cannot be removed.';
      notifyListeners();
      return false;
    }
    final ok = await _run(
      GroupErrorContext.removeMember,
      () => _repo.removeMember(groupId: groupId, userId: userId),
    );
    if (ok) await load();
    return ok;
  }

  /// Updates name / description / privacy. Server policy decides; a refusal
  /// surfaces as a permission message. Privacy is validated against the live
  /// CHECK values before anything is sent.
  Future<bool> updateBasics({
    required String name,
    String description = '',
    GroupPrivacy? privacy,
  }) async {
    final invalid = GroupErrors.validateName(name);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return false;
    }
    final ok = await _run(
      GroupErrorContext.update,
      () => _repo.updateBasics(
        groupId: groupId,
        name: name,
        description: description,
        privacy: privacy?.db,
      ),
    );
    if (ok) await load();
    return ok;
  }

  /// Removes the group logo (`logo_url = NULL`). Upload/replace wait on a
  /// group-scoped storage policy that does not exist live yet.
  Future<bool> clearLogo() async {
    final ok = await _run(
      GroupErrorContext.update,
      () => _repo.clearLogo(groupId),
    );
    if (ok) await load();
    return ok;
  }

  // ── Group Rules (G6) ──

  Future<void> _loadRules() async {
    _rulesLoading = true;
    _rulesError = null;
    try {
      _rules = await _repo.groupRules(groupId);
    } on AppError catch (e) {
      _rules = const [];
      _rulesError = e.message;
    } catch (e, st) {
      AppLogger.error('Group rules load failed: $e', stackTrace: st);
      _rules = const [];
      _rulesError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.load,
      );
    }
    _rulesLoading = false;
  }

  Future<void> retryRules() async {
    if (_rulesLoading) return;
    notifyListeners();
    await _loadRules();
    notifyListeners();
  }

  /// UX-only pre-check mirroring the live gate (GROUP_SETTINGS or owner);
  /// the `group_rules` RLS is the boundary and is exercised regardless.
  bool _ruleMutationAllowed() {
    if (canEditBasics) return true;
    _error = GroupErrors.map(
      'NOT_AUTHORIZED',
      context: GroupErrorContext.update,
    );
    notifyListeners();
    return false;
  }

  /// Creates a rule. Single-flight. Re-reads after success or failure.
  Future<bool> createRule(String ruleText) async {
    if (_rulesSaving || _busy) return false;
    if (!_ruleMutationAllowed()) return false;
    final trimmed = ruleText.trim();
    if (trimmed.isEmpty) {
      _error = 'Rule text cannot be empty.';
      notifyListeners();
      return false;
    }
    _rulesSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.createRule(groupId: groupId, ruleText: trimmed);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Create rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _rulesSaving = false;
      notifyListeners();
    }
  }

  /// Updates a rule's text. Single-flight per rule. Re-reads after.
  Future<bool> updateRule(GroupRule rule, String ruleText) async {
    if (_rulesSaving || _actingRuleId == rule.id || _busy) return false;
    if (!_ruleMutationAllowed()) return false;
    final trimmed = ruleText.trim();
    if (trimmed.isEmpty) {
      _error = 'Rule text cannot be empty.';
      notifyListeners();
      return false;
    }
    _actingRuleId = rule.id;
    _rulesSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.updateRule(ruleId: rule.id, ruleText: trimmed);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Update rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _actingRuleId = null;
      _rulesSaving = false;
      notifyListeners();
    }
  }

  /// Deletes a rule. Single-flight per rule. Re-reads after.
  Future<bool> deleteRule(GroupRule rule) async {
    if (_rulesSaving || _actingRuleId == rule.id || _busy) return false;
    if (!_ruleMutationAllowed()) return false;
    _actingRuleId = rule.id;
    _rulesSaving = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.deleteRule(rule.id);
      await _loadRules();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadRules();
      return false;
    } catch (e, st) {
      AppLogger.error('Delete rule failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.update);
      await _loadRules();
      return false;
    } finally {
      _actingRuleId = null;
      _rulesSaving = false;
      notifyListeners();
    }
  }

  Future<bool> _run(
    GroupErrorContext context,
    Future<void> Function() body,
  ) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      return false;
    } catch (e, st) {
      AppLogger.error('Group mutation failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: context);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── Group Announcements (G7) ──

  Future<void> _loadAnnouncements() async {
    _announcementsLoading = true;
    _announcementsError = null;
    try {
      _announcements = await _repo.announcements(groupId);
    } on AppError catch (e) {
      _announcements = const [];
      _announcementsError = e.message;
    } catch (e, st) {
      AppLogger.error('Group announcements load failed: $e', stackTrace: st);
      _announcements = const [];
      _announcementsError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.load,
      );
    }
    _announcementsLoading = false;
  }

  Future<void> retryAnnouncements() async {
    if (_announcementsLoading) return;
    notifyListeners();
    await _loadAnnouncements();
    notifyListeners();
  }

  /// Client mirror of the live CHECKs (title 1..120, body 1..2000 after
  /// trim). Returns the message to show, or null when acceptable. The server
  /// re-validates regardless.
  static String? validateAnnouncement({
    required String title,
    required String body,
  }) {
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty) return 'Announcement title cannot be empty.';
    if (t.length > GroupAnnouncement.maxTitleLength) {
      return 'Announcement title must be at most '
          '${GroupAnnouncement.maxTitleLength} characters.';
    }
    if (b.isEmpty) return 'Announcement text cannot be empty.';
    if (b.length > GroupAnnouncement.maxBodyLength) {
      return 'Announcement text must be at most '
          '${GroupAnnouncement.maxBodyLength} characters.';
    }
    return null;
  }

  /// UX-only pre-check mirroring the live gate (SEND_ANNOUNCEMENT or owner);
  /// the `group_announcements` RLS is the boundary and is exercised
  /// regardless.
  bool _announcementMutationAllowed() {
    if (canSendAnnouncement) return true;
    _error = GroupErrors.map(
      'NOT_AUTHORIZED',
      context: GroupErrorContext.announcement,
    );
    notifyListeners();
    return false;
  }

  Future<bool> _runAnnouncementMutation(
    String? actingId,
    Future<void> Function() body,
  ) async {
    _actingAnnouncementId = actingId;
    _announcementSaving = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      await _loadAnnouncements();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadAnnouncements();
      return false;
    } catch (e, st) {
      AppLogger.error('Announcement mutation failed: $e', stackTrace: st);
      _error = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.announcement,
      );
      await _loadAnnouncements();
      return false;
    } finally {
      _actingAnnouncementId = null;
      _announcementSaving = false;
      notifyListeners();
    }
  }

  /// Creates an announcement. Single-flight. Re-reads after success or
  /// failure (the server may also have fired its notification triggers).
  Future<bool> createAnnouncement({
    required String title,
    required String body,
  }) async {
    if (_announcementSaving || _busy) return false;
    if (!_announcementMutationAllowed()) return false;
    final invalid = validateAnnouncement(title: title, body: body);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return false;
    }
    return _runAnnouncementMutation(
      null,
      () => _repo.createAnnouncement(
        groupId: groupId,
        title: title.trim(),
        body: body.trim(),
      ),
    );
  }

  /// Edits title/body. Single-flight per announcement. Re-reads after.
  Future<bool> updateAnnouncement(
    GroupAnnouncement a, {
    required String title,
    required String body,
  }) async {
    if (_announcementSaving || _actingAnnouncementId == a.id || _busy) {
      return false;
    }
    if (!_announcementMutationAllowed()) return false;
    final invalid = validateAnnouncement(title: title, body: body);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return false;
    }
    return _runAnnouncementMutation(
      a.id,
      () => _repo.updateAnnouncement(
        announcementId: a.id,
        title: title.trim(),
        body: body.trim(),
      ),
    );
  }

  /// Deletes an announcement. Single-flight per announcement. Re-reads after.
  Future<bool> deleteAnnouncement(GroupAnnouncement a) async {
    if (_announcementSaving || _actingAnnouncementId == a.id || _busy) {
      return false;
    }
    if (!_announcementMutationAllowed()) return false;
    return _runAnnouncementMutation(
      a.id,
      () => _repo.deleteAnnouncement(a.id),
    );
  }

  // ── Group Chat (G8) ──

  /// Loads the latest window (newest [messagePageSize]) and stores it
  /// oldest → newest. A full page means older rows may exist.
  Future<void> _loadMessages() async {
    _messagesLoading = true;
    _messagesError = null;
    try {
      final page = await _repo.messages(groupId);
      _messages = page.reversed.toList(growable: false);
      _hasOlder = page.length >= messagePageSize;
    } on AppError catch (e) {
      _messages = const [];
      _hasOlder = false;
      _messagesError = e.message;
    } catch (e, st) {
      AppLogger.error('Group chat load failed: $e', stackTrace: st);
      _messages = const [];
      _hasOlder = false;
      _messagesError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.load,
      );
    }
    _messagesLoading = false;
  }

  /// Re-reads the latest window from the server (pull-to-refresh, the
  /// refresh button, and after every send). Single-flight.
  Future<void> refreshMessages() async {
    if (_messagesLoading) return;
    notifyListeners();
    await _loadMessages();
    notifyListeners();
  }

  /// Prepends the page before the oldest loaded message. Single-flight;
  /// keeps the current window on failure and reports the error inline.
  Future<void> loadOlderMessages() async {
    if (_olderLoading || _messagesLoading || !_hasOlder || _messages.isEmpty) {
      return;
    }
    _olderLoading = true;
    _messagesError = null;
    notifyListeners();
    try {
      final oldest = _messages.first.createdAt;
      final page = await _repo.messages(groupId, before: oldest);
      final known = {for (final m in _messages) m.id};
      _messages = [
        ...page.reversed.where((m) => !known.contains(m.id)),
        ..._messages,
      ];
      _hasOlder = page.length >= messagePageSize;
    } on AppError catch (e) {
      _messagesError = e.message;
    } catch (e, st) {
      AppLogger.error('Group chat older page failed: $e', stackTrace: st);
      _messagesError = GroupErrors.map(
        e.toString(),
        context: GroupErrorContext.load,
      );
    } finally {
      _olderLoading = false;
      notifyListeners();
    }
  }

  /// Client mirror of the live CHECK (`char_length(body) BETWEEN 1 AND
  /// 2000` after trim). Returns the message to show, or null.
  static String? validateMessage(String body) {
    final b = body.trim();
    if (b.isEmpty) return 'Message cannot be empty.';
    if (b.length > GroupMessage.maxBodyLength) {
      return 'Message must be at most ${GroupMessage.maxBodyLength} characters.';
    }
    return null;
  }

  /// Sends one message. Single-flight; the sender is always the signed-in
  /// user (the repository sets it, the live INSERT policy enforces it). The
  /// window is re-read from the server after success **and** failure — no
  /// optimistic row is ever kept.
  Future<bool> sendMessage(String body) async {
    if (_sending || _busy) return false;
    final invalid = validateMessage(body);
    if (invalid != null) {
      _error = invalid;
      notifyListeners();
      return false;
    }
    _sending = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.sendMessage(groupId: groupId, body: body.trim());
      await _loadMessages();
      return true;
    } on AppError catch (e) {
      _error = e.message;
      await _loadMessages();
      return false;
    } catch (e, st) {
      AppLogger.error('Send message failed: $e', stackTrace: st);
      _error = GroupErrors.map(e.toString(), context: GroupErrorContext.chat);
      await _loadMessages();
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
