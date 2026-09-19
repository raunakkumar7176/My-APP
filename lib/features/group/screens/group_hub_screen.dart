import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../data/notification_repository.dart';
import '../state/group_hub_controller.dart';
import '../widgets/group_announcements_section.dart';
import '../widgets/group_avatar.dart';
import '../widgets/group_chat_section.dart';
import '../widgets/group_management_section.dart';
import '../widgets/group_rules_section.dart';
import '../widgets/invite_member_sheet.dart';
import '../widgets/join_request_queue.dart';
import '../widgets/member_tile.dart';
import '../widgets/outgoing_invitations_section.dart';
import '../widgets/role_permissions_sheet.dart';

/// One group's hub: profile header, roster, and the G1 membership actions.
/// Later phases (leaderboard) attach here; nothing is stubbed for them yet.
class GroupHubScreen extends StatefulWidget {
  const GroupHubScreen({required this.groupId, this.controller, super.key});

  final String groupId;
  final GroupHubController? controller;

  @override
  State<GroupHubScreen> createState() => _GroupHubScreenState();
}

class _GroupHubScreenState extends State<GroupHubScreen> {
  late final GroupHubController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c =
        widget.controller ??
        GroupHubController(
          groupId: widget.groupId,
          // G16: live inbox for the unread badge (tests inject their own).
          notifications: const SupabaseNotificationRepository(),
        );
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _openSettings() async {
    await context.push('/groups/${widget.groupId}/settings');
    // Name / description / privacy / logo may have changed: reload, never
    // show a stale header.
    if (mounted) await _c.refresh();
  }

  Future<void> _inviteMember() async {
    // Manager-only (server-reported MANAGE_MEMBERS); the sheet never runs
    // the lookup for anyone else because it is never opened for them.
    final sent = await InviteMemberSheet.show(context, hub: _c);
    if (sent == true && mounted) await _c.refresh();
  }

  Future<void> _openTests() async {
    // G10: group test management; the screen probes its own permissions.
    await context.push('/groups/${widget.groupId}/tests');
    if (mounted) await _c.refresh();
  }

  Future<void> _openMembers() async {
    await context.push('/groups/${widget.groupId}/members');
    // Roles / roster / count may have changed there.
    if (mounted) await _c.refresh();
  }

  Future<void> _openNotifications() async {
    await context.push('/groups/${widget.groupId}/notifications');
    // Rows were marked read there: re-read the count, never keep a stale badge.
    if (mounted) await _c.refresh();
  }

  Future<void> _openRolePermissions() async {
    // G14: MANAGE_ROLES (server-reported) or owner; the sheet re-reads the
    // matrix from the server and the controller re-probes after each change.
    await RolePermissionsSheet.show(context, hub: _c);
    if (mounted) await _c.refresh();
  }

  Future<void> _leave() async {
    if (!_c.canLeave) {
      _snack(_c.leaveBlockedReason, error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: Text(
          'You will lose access to ${_c.group?.name ?? 'this group'}, its '
          'tests and its members. You can rejoin later with the invite code '
          'if the group allows it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_leave'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _c.leave();
    if (!mounted) return;
    if (ok) {
      _snack('You left the group.');
      context.go('/groups');
    } else {
      _snack(_c.error ?? 'Could not leave the group.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.hasLoaded && _c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_c.accessDenied) {
      return _message(
        icon: Icons.lock_outline,
        title: _c.hasLeft ? 'You left this group' : 'Group not available',
        // One honest message: the server does not distinguish "deleted" from
        // "you are not a member", and guessing would leak that a group exists.
        body: _c.hasLeft
            ? 'You no longer have access to this group.'
            : 'This group does not exist, or you are not a member of it.',
      );
    }
    if (_c.group == null) {
      return _message(
        icon: Icons.error_outline,
        title: 'Could not open this group',
        body: _c.error ?? 'Please try again.',
        action: FilledButton(onPressed: _c.load, child: const Text('Retry')),
      );
    }

    final group = _c.group!;
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          if (_c.hasNotifications)
            IconButton(
              key: const Key('group_notifications_action'),
              tooltip: 'Notifications',
              icon: Badge.count(
                key: const Key('group_notifications_badge'),
                count: _c.unreadNotifications ?? 0,
                isLabelVisible: _c.hasUnreadNotifications,
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: _openNotifications,
            ),
          if (_c.canManageMembers)
            IconButton(
              key: const Key('invite_member_action'),
              tooltip: 'Invite member',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: _c.isBusy ? null : _inviteMember,
            ),
          if (_c.canEditBasics)
            IconButton(
              key: const Key('group_settings_action'),
              tooltip: 'Group settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openSettings,
            ),
          PopupMenuButton<String>(
            key: const Key('group_menu'),
            onSelected: (value) {
              if (value == 'leave') _leave();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'leave',
                enabled: _c.canLeave,
                child: const Text('Leave group'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                GroupAvatar(
                  name: group.name,
                  logoUrl: group.logoUrl,
                  radius: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_c.memberCount} ${_c.memberCount == 1 ? 'member' : 'members'} · '
                        '${_c.myRole.label} · ${_c.privacy.label}',
                        key: const Key('group_header_meta'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if ((group.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(group.description!.trim()),
            ],
            const SizedBox(height: 24),
            // G14: one Manage surface, rows gated by server-reported
            // permissions (owner bypass); renders nothing for a plain member.
            if (_c.hasManagementControls) ...[
              GroupManagementSection(
                controller: _c,
                onOpenSettings: _openSettings,
                onOpenMembers: _openMembers,
                onOpenTests: _openTests,
                onOpenRolePermissions: _openRolePermissions,
              ),
              const SizedBox(height: 24),
            ],
            // Announcements then rules: visible to all members; manager
            // controls are inside each section.
            GroupAnnouncementsSection(controller: _c),
            const SizedBox(height: 24),
            GroupRulesSection(controller: _c),
            const SizedBox(height: 24),
            // Chat: every member reads and sends; server-backed, no realtime.
            GroupChatSection(controller: _c),
            const SizedBox(height: 24),
            // G10: every member may view the group's tests; managers act there.
            OutlinedButton.icon(
              key: const Key('open_group_tests'),
              onPressed: _c.isBusy ? null : _openTests,
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('Group tests'),
            ),
            const SizedBox(height: 24),
            if (_c.canManageMembers) ...[
              JoinRequestQueue(controller: _c),
              const SizedBox(height: 24),
              OutgoingInvitationsSection(controller: _c),
              const SizedBox(height: 24),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Members · ${_c.memberCount}',
                    key: const Key('hub_members_heading'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  key: const Key('view_all_members'),
                  onPressed: () => _openMembers(),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final m in _c.members)
              MemberTile(
                member: m,
                controller: _c,
                onTap: () => MemberDetailSheet.show(
                  context,
                  member: m,
                  groupName: group.name,
                  isMe: m.userId == _c.currentUserId,
                ),
              ),
            const SizedBox(height: 24),
            if (_c.canLeave)
              OutlinedButton.icon(
                key: const Key('leave_group_button'),
                onPressed: _c.isBusy ? null : _leave,
                icon: const Icon(Icons.logout),
                label: const Text('Leave group'),
              )
            else
              Text(
                _c.leaveBlockedReason,
                key: const Key('leave_blocked_note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action ??
                  FilledButton(
                    onPressed: () => context.go('/groups'),
                    child: const Text('Back to Groups'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
