import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group.dart';
import '../../../core/models/group_member.dart';
import '../../../core/services/supabase_service.dart';
import '../../test/data/test_repository.dart';
import '../data/notification_repository.dart';
import '../domain/group_role.dart';
import '../state/group_hub_controller.dart';
import '../widgets/group_avatar.dart';
import '../widgets/invite_member_sheet.dart';
import '../widgets/join_request_queue.dart';
import '../widgets/outgoing_invitations_section.dart';
import '../widgets/role_permissions_sheet.dart';

/// Dedicated WhatsApp/Telegram-style Group Info & Management Screen.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    required this.groupId,
    this.controller,
    super.key,
  });

  final String groupId;
  final GroupHubController? controller;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late final GroupHubController _c;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ??
        GroupHubController(
          groupId: widget.groupId,
          notifications: const SupabaseNotificationRepository(),
          tests: const SupabaseTestRepository(),
        );
    _c.addListener(_onChanged);
    if (_owns) {
      _c.load();
    }
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
    if (mounted) await _c.refresh();
  }

  Future<void> _openTests() async {
    await context.push('/groups/${widget.groupId}/tests');
    if (mounted) await _c.refresh();
  }

  Future<void> _inviteMember() async {
    final sent = await InviteMemberSheet.show(context, hub: _c);
    if (sent == true && mounted) await _c.refresh();
  }

  Future<void> _openRolePermissions() async {
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
          'You will lose access to ${_c.group?.name ?? 'this group'}, its tests and discussions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_leave'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave Group'),
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
      _snack('Only the group owner can delete this group.', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this group?'),
        content: const Text(
          'This action cannot be undone. All messages, members, and group data will be permanently deleted.',
        ),
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
        await client.storage.from('group-avatars').uploadBinary(
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
        await client.storage.from('avatars').uploadBinary(
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

  void _showAvatarOptions() {
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
              'Change Group Avatar',
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!_c.hasLoaded && _c.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Info')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_c.accessDenied) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Info')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56, color: AppColors.error),
                const SizedBox(height: 16),
                Text(
                  _c.hasLeft ? 'You left this group' : 'Group not available',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _c.hasLeft
                      ? 'You no longer have access to this group.'
                      : 'This group does not exist, or you are not a member.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
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

    final group = _c.group;
    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Info')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_c.error ?? 'Could not load group info.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _c.load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Group Info'),
        elevation: 0.5,
        actions: [
          if (_c.canEditBasics)
            IconButton(
              key: const Key('group_settings_action'),
              tooltip: 'Group settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openSettings,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Top: Large Avatar + Name + Description
            _buildHeaderCard(context, group, isDark),
            const SizedBox(height: 16),

            // Section 1: Quick Stats (Tests hosted, Total members)
            _buildStatsSection(context, group, isDark),
            const SizedBox(height: 20),

            // Section 2: Member List with Role Badges
            _buildMembersSection(context, isDark),
            const SizedBox(height: 20),

            if (_c.canManageRoles) ...[
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: const Key('open_role_permissions'),
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Roles & Permissions'),
                  subtitle: const Text('Control what each role can do'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openRolePermissions,
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Section 3: Pending Invitations & Join Requests (Managers only)
            if (_c.canManageMembers) ...[
              JoinRequestQueue(controller: _c),
              const SizedBox(height: 16),
              OutgoingInvitationsSection(controller: _c),
              const SizedBox(height: 20),
            ],

            // Section 4: Danger Zone (Leave / Delete)
            _buildDangerZone(context, isDark),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, Group group, bool isDark) {
    final theme = Theme.of(context);
    final canEditAvatar = _c.canEditBasics || _c.isOwner;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          // Large Group Avatar with camera overlay
          Stack(
            children: [
              GroupAvatar(
                name: group.name,
                logoUrl: group.logoUrl,
                radius: 46,
              ),
              if (canEditAvatar)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Material(
                    color: theme.colorScheme.primary,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      onTap: _showAvatarOptions,
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(
                          Icons.camera_alt,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Group Name
          Text(
            group.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),

          // Privacy Pill Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  group.privacy == 'public'
                      ? Icons.public
                      : (group.privacy == 'restricted'
                          ? Icons.shield_outlined
                          : Icons.lock_outline),
                  size: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                Text(
                  '${(group.privacy ?? 'private').toUpperCase()} GROUP',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            (group.description ?? '').trim().isNotEmpty
                ? group.description!.trim()
                : 'No description provided for this group.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context, Group group, bool isDark) {
    final testsCount = _c.liveTestCount + _c.upcomingTestCount + _c.previousTestCount;
    final membersCount = _c.memberCount;

    return Row(
      children: [
        Expanded(
          child: _statCard(
            context: context,
            icon: Icons.people_alt_outlined,
            title: 'Members',
            value: '$membersCount',
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: _openTests,
            borderRadius: BorderRadius.circular(12),
            child: _statCard(
              context: context,
              icon: Icons.quiz_outlined,
              title: 'Group Tests',
              value: '$testsCount',
              actionLabel: 'View Tests ➔',
              isDark: isDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    String? actionLabel,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              actionLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersSection(BuildContext context, bool isDark) {
    final members = _c.members;
    final canManage = _c.canManageMembers;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Members (${members.length})',
                key: const Key('hub_members_heading'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (canManage)
                TextButton.icon(
                  key: const Key('invite_member_action'),
                  onPressed: _inviteMember,
                  icon: const Icon(Icons.person_add_alt, size: 16),
                  label: const Text('Invite'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No members found.'),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: members.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                final m = members[index];
                return _memberTile(context, m, isDark);
              },
            ),
        ],
      ),
    );
  }

  Widget _memberTile(BuildContext context, GroupMember m, bool isDark) {
    final isMe = m.userId == _c.currentUserId;
    final role = GroupRole.fromDb(m.role);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        child: Text(
          m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : 'U',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              m.displayName + (isMe ? ' (You)' : ''),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _roleBadge(role, isDark),
        ],
      ),
      subtitle: m.studentCode != null && m.studentCode!.isNotEmpty
          ? Text(
              m.studentCode!,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            )
          : null,
      trailing: _c.canManageRoles && !isMe && !role.isOwner
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (val) async {
                if (val == 'remove') {
                  final ok = await _c.removeMember(m.userId);
                  if (ok && mounted) _snack('Member removed');
                } else if (val == 'make_leader') {
                  final ok = await _c.changeRole(m.userId, GroupRole.leader);
                  if (ok && mounted) _snack('Role updated to Leader');
                } else if (val == 'make_mod') {
                  final ok = await _c.changeRole(m.userId, GroupRole.moderator);
                  if (ok && mounted) _snack('Role updated to Moderator');
                } else if (val == 'make_member') {
                  final ok = await _c.changeRole(m.userId, GroupRole.member);
                  if (ok && mounted) _snack('Role updated to Member');
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'make_leader',
                  child: Text('Promote to Leader'),
                ),
                const PopupMenuItem(
                  value: 'make_mod',
                  child: Text('Promote to Moderator'),
                ),
                const PopupMenuItem(
                  value: 'make_member',
                  child: Text('Set as Member'),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from Group', style: TextStyle(color: AppColors.error)),
                ),
              ],
            )
          : null,
    );
  }

  Widget _roleBadge(GroupRole role, bool isDark) {
    String label;
    Color bg;
    Color text;

    switch (role) {
      case GroupRole.owner:
        label = '👑 Owner';
        bg = isDark ? const Color(0xFF3B2814) : const Color(0xFFFEF3C7);
        text = isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
        break;
      case GroupRole.leader:
        label = '⭐ Leader';
        bg = isDark ? const Color(0xFF143026) : const Color(0xFFDCFCE7);
        text = isDark ? const Color(0xFF34D399) : const Color(0xFF15803D);
        break;
      case GroupRole.moderator:
        label = '🛡️ Mod';
        bg = isDark ? const Color(0xFF2E1C40) : const Color(0xFFF3E8FF);
        text = isDark ? const Color(0xFFC084FC) : const Color(0xFF7E22CE);
        break;
      case GroupRole.member:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  Widget _buildDangerZone(BuildContext context, bool isDark) {
    final isOwner = _c.isOwner;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A1215) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF5C1D24) : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
              SizedBox(width: 8),
              Text(
                'Danger Zone',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isOwner
                ? 'Deleting this group will remove all messages, tests, and member associations permanently.'
                : 'Leaving this group will revoke your access to its materials and discussions.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
            ),
          ),
          const SizedBox(height: 14),
          if (isOwner)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('delete_group_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _deleteGroup,
                icon: const Icon(Icons.delete_forever, size: 18),
                label: const Text(
                  'Delete Group',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('leave_group_button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _leave,
                icon: const Icon(Icons.exit_to_app, size: 18),
                label: const Text(
                  'Leave Group',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
