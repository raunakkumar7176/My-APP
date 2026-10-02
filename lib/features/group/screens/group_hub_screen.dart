import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group.dart';
import '../../../core/services/supabase_service.dart';
import '../../test/data/test_repository.dart';
import '../../test/domain/test_lifecycle.dart';
import '../../test/widgets/test_formatters.dart';
import '../data/notification_repository.dart';
import '../state/group_hub_controller.dart';
import '../widgets/group_announcements_section.dart';
import '../widgets/group_avatar.dart';
import '../widgets/group_management_section.dart';
import '../widgets/group_rules_section.dart';
import '../widgets/invite_member_sheet.dart';
import '../widgets/join_request_queue.dart';
import '../widgets/member_tile.dart';
import '../widgets/outgoing_invitations_section.dart';
import '../widgets/role_permissions_sheet.dart';

export 'group_info_screen.dart';

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
          // Overview: live upcoming-test preview (tests inject their own).
          tests: const SupabaseTestRepository(),
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

  Future<void> _deleteGroup() async {
    if (!_c.canDeleteGroup) {
      _snack(_c.error ?? 'This group still has other members.', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this study group?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_group'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Group'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _c.deleteGroup();
    if (!mounted) return;
    if (ok) {
      _snack('Group deleted.');
      context.go('/groups');
    } else {
      _snack(_c.error ?? 'Could not delete the group.', error: true);
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    Navigator.of(context).pop();
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final client = SupabaseService.client;
      final path =
          '${widget.groupId}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      String? publicUrl;
      try {
        await client.storage
            .from('group-avatars')
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        publicUrl = client.storage.from('group-avatars').getPublicUrl(path);
      } catch (_) {
        final fallbackPath = 'groups/${widget.groupId}/avatar.jpg';
        await client.storage
            .from('avatars')
            .uploadBinary(
              fallbackPath,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        publicUrl = client.storage.from('avatars').getPublicUrl(fallbackPath);
      }
      final ok = await _c.updateLogoUrl(publicUrl);
      if (mounted) {
        if (ok) {
          _snack('Group avatar updated!');
        } else {
          _snack(_c.error ?? 'Failed to update avatar.', error: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _snack('Could not upload group avatar: $e', error: true);
      }
    }
  }

  void _showAvatarEditSheet() {
    if (!_c.canEditBasics) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Group Avatar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => _pickAndUploadAvatar(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => _pickAndUploadAvatar(ImageSource.gallery),
            ),
            if (_c.group?.logoUrl != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _c.clearLogo();
                  if (mounted) _snack('Group avatar removed');
                },
              ),
          ],
        ),
      ),
    );
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
              if (value == 'delete') _deleteGroup();
            },
            itemBuilder: (_) => [
              if (_c.canDeleteGroup)
                PopupMenuItem(
                  key: const Key('delete_group_menu_item'),
                  value: 'delete',
                  child: Text(
                    'Delete group',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                )
              else
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
            _headerCard(context, group),
            const SizedBox(height: 24),
            // Overview: "what's happening in my study group" — study-test
            // counts, the next upcoming test, and the caller's own recent
            // activity for this group. Additive only; every section below
            // is unchanged.
            _overviewSection(context),
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
            _dangerZone(context),
          ],
        ),
      ),
    );
  }

  Widget _dangerZone(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0x22450A0A) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFCA5A5),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Danger Zone',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_c.canLeave)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('leave_group_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
                onPressed: _c.isBusy ? null : _leave,
                icon: const Icon(Icons.logout),
                label: const Text('Leave group'),
              ),
            )
          else
            Text(
              _c.leaveBlockedReason,
              key: const Key('leave_blocked_note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF991B1B),
              ),
            ),
          if (_c.canDeleteGroup) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('delete_group_button'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: _c.isBusy ? null : _deleteGroup,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete group'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "What's happening in my study group?" — active/upcoming/completed test
  /// counts, the next upcoming test (if any), and the caller's own recent
  /// notifications for this group. Every count/row is real data already
  /// loaded by the hub controller (`_loadGroupTests`/`_loadRecentActivity`,
  /// both best-effort) — nothing here is invented or guessed.
  Widget _overviewSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Overview', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          key: const Key('overview_stats_row'),
          children: [
            Expanded(
              child: _statCard(
                theme,
                'Live',
                _c.liveTestCount,
                Icons.podcasts_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                theme,
                'Upcoming',
                _c.upcomingTestCount,
                Icons.event_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                theme,
                'Completed',
                _c.previousTestCount,
                Icons.check_circle_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _upcomingTestCard(context),
        const SizedBox(height: 12),
        _recentActivityCard(context),
      ],
    );
  }

  Widget _statCard(ThemeData theme, String label, int count, IconData icon) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text('$count', style: theme.textTheme.titleLarge),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _upcomingTestCard(BuildContext context) {
    final theme = Theme.of(context);
    final test = _c.upcomingTest;
    if (test == null) {
      return Card(
        key: const Key('overview_no_upcoming_test'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            "No tests yet\nYour group hasn't scheduled an upcoming test.",
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    return Card(
      key: Key('overview_upcoming_test_${test.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upcoming test', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(test.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${TestLifecycle.statusLabel(test.status)} · '
              '${TestFormatters.duration(test.durationSec)}'
              '${test.startsAt != null ? ' · starts ${TestFormatters.dateTime(test.startsAt)}' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('overview_view_test_${test.id}'),
                onPressed: () => context.push('/tests/${test.id}'),
                child: const Text('View Test'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The caller's own recent notifications for this group. Labelled
  /// honestly as personal activity — the app has no member-readable,
  /// cross-user activity log for group events today, so this can never be a
  /// shared "Alice joined / Bob completed a test" timeline without new
  /// backend work.
  Widget _recentActivityCard(BuildContext context) {
    final theme = Theme.of(context);
    final activity = _c.recentActivity;
    if (activity == null) {
      // Not loaded / failed — never worth a red error state on Overview.
      return const SizedBox.shrink();
    }
    return Card(
      key: const Key('overview_recent_activity'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent activity', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            if (activity.isEmpty)
              Text(
                'No recent activity',
                key: const Key('overview_activity_empty'),
                style: theme.textTheme.bodySmall,
              )
            else
              for (final n in activity)
                Padding(
                  key: Key('overview_activity_${n.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.title, style: theme.textTheme.bodyMedium),
                      Text(
                        n.body,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Header card: avatar, name, the exact "N members · Role · Privacy" line
  /// (kept verbatim under `group_header_meta` — existing tests assert its
  /// text), description, and a small strip of real counts only (pending
  /// join requests / unread notifications) when the caller can see them.
  Widget _headerCard(BuildContext context, Group group) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: _c.canEditBasics ? _showAvatarEditSheet : null,
                  borderRadius: BorderRadius.circular(32),
                  child: Stack(
                    children: [
                      GroupAvatar(
                        name: group.name,
                        logoUrl: group.logoUrl,
                        radius: 28,
                      ),
                      if (_c.canEditBasics)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        '${_c.memberCount} ${_c.memberCount == 1 ? 'member' : 'members'} · '
                        '${_c.myRole.label} · ${_c.privacy.label}',
                        key: const Key('group_header_meta'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
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
            if (_c.canManageMembers && _c.pendingRequestCount > 0 ||
                _c.hasUnreadNotifications) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_c.canManageMembers && _c.pendingRequestCount > 0)
                    _statChip(
                      theme,
                      Icons.person_add_alt_1_outlined,
                      '${_c.pendingRequestCount} pending request'
                      '${_c.pendingRequestCount == 1 ? '' : 's'}',
                    ),
                  if (_c.hasUnreadNotifications)
                    _statChip(
                      theme,
                      Icons.notifications_outlined,
                      '${_c.unreadNotifications} unread',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statChip(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/groups'),
                    child: const Text('Back to Groups'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
