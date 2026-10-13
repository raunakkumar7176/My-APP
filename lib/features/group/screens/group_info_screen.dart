import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/theme/app_colors.dart' as premium;
import '../../../core/theme/app_radius.dart';
import '../../../core/models/group.dart';
import '../../../core/services/supabase_service.dart';
import '../../test/data/test_repository.dart';
import '../data/notification_repository.dart';
import '../state/group_hub_controller.dart';
import '../state/invite_code_controller.dart';
import '../widgets/group_action_row.dart';
import '../widgets/group_announcements_section.dart';
import '../widgets/group_avatar.dart';
import '../widgets/group_leaderboard_section.dart';
import '../widgets/group_media_section.dart';
import '../widgets/group_members_section.dart';
import '../widgets/group_rules_section.dart';
import '../widgets/group_tests_section.dart';
import '../widgets/invite_member_sheet.dart';
import '../widgets/role_permissions_sheet.dart';

/// Dedicated WhatsApp/Telegram-style Group Info & Management Screen.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({required this.groupId, this.controller, super.key});

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
    _c =
        widget.controller ??
        GroupHubController(
          groupId: widget.groupId,
          notifications: const SupabaseNotificationRepository(),
          tests: const SupabaseTestRepository(),
        );
    _c.addListener(_onChanged);
    // Unconditional, even for an injected controller: a caller that hands
    // in a controller it hasn't loaded yet must still see real data, not
    // this screen's "could not load" fallback. load() is cheap to call on
    // an already-loaded controller (guarded against re-entrancy) — this
    // matches the previous GroupHubScreen's behavior exactly.
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
    if (mounted) await _c.refresh();
  }

  Future<void> _openTests() async {
    await context.push('/groups/${widget.groupId}/tests');
    if (mounted) await _c.refresh();
  }

  Future<void> _openNotifications() async {
    await context.push('/groups/${widget.groupId}/notifications');
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

  Future<void> _openRequests() async {
    // Deliberately NOT folded into Settings: Settings is gated on
    // GROUP_SETTINGS-or-owner, but reviewing join requests only needs
    // MANAGE_MEMBERS — an admin with MANAGE_MEMBERS but not GROUP_SETTINGS
    // (the live default: leader/admin seeding grants everything except
    // GROUP_SETTINGS and MANAGE_ROLES) would be locked out of this
    // entirely if it only lived in Settings. The Settings screen also
    // shows a requests card (SettingsRequestsCard) as a convenience for
    // whoever is already there with GROUP_SETTINGS, but this dedicated,
    // more-permissively-gated screen stays the primary path.
    await context.push('/groups/${widget.groupId}/requests');
    if (mounted) await _c.refresh();
  }

  /// A real invite-code sheet (load, copy, rotate) — the same
  /// [InviteCodeController] the Settings screen uses, not a duplicate of
  /// its logic.
  Future<void> _shareInvite() async {
    final invite = InviteCodeController(groupId: widget.groupId);
    await invite.load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => AnimatedBuilder(
        animation: invite,
        builder: (ctx, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite code',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (invite.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (invite.code == null)
                  Text(invite.error ?? 'Could not load the invite code.')
                else
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: AppRadius.mdBorder,
                          ),
                          child: Text(
                            invite.code!,
                            key: const Key('group_info_invite_code'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: const Key('group_info_copy_invite'),
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: invite.code!));
                          _snack('Invite code copied');
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: invite.isBusy ? null : invite.rotate,
                    child: Text(invite.isRotating ? 'Rotating…' : 'Rotate code'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    invite.dispose();
  }

  // Leave/Delete/Transfer moved entirely to Settings' Danger Zone — Info
  // no longer carries its own.

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
                const Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: AppColors.error,
                ),
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
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
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
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Group Info'),
        elevation: 0.5,
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

            // Quick actions: Mute/Unmute, Share invite, Settings.
            GroupActionRow(
              controller: _c,
              onShareInvite: _shareInvite,
              onOpenSettings: _openSettings,
            ),
            const SizedBox(height: 20),

            // Members (search + local paging).
            GroupMembersSection(
              controller: _c,
              onInvite: _inviteMember,
              onOpenRolePermissions: _openRolePermissions,
              onOpenRequests: _openRequests,
            ),
            const SizedBox(height: 20),

            // Tests (Active / Past).
            GroupTestsSection(controller: _c, onOpenAllTests: _openTests),
            const SizedBox(height: 20),

            // Media & Files (honest empty state — no backend yet).
            const GroupMediaSection(),
            const SizedBox(height: 20),

            // Leaderboard (routes into per-test leaderboards; there is no
            // group-wide leaderboard).
            GroupLeaderboardSection(onOpenTests: _openTests),
            const SizedBox(height: 20),

            // Announcements — read-only here; posting/editing/deleting is
            // a Settings action now (every section appears exactly once).
            _sectionShell(
              isDark: isDark,
              icon: Icons.campaign_rounded,
              iconColor: const Color(0xFFD97706),
              child: GroupAnnouncementsSection(controller: _c, readOnly: true),
            ),
            const SizedBox(height: 20),

            // Group rules — same read-only treatment as Announcements.
            _sectionShell(
              isDark: isDark,
              icon: Icons.gavel_rounded,
              iconColor: const Color(0xFF7C3AED),
              child: GroupRulesSection(controller: _c, readOnly: true),
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        gradient: premium.AppColors.primaryGradient,
        borderRadius: AppRadius.xlBorder,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB)
                .withValues(alpha: isDark ? 0.25 : 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Large Group Avatar in a white ring, with camera overlay
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: GroupAvatar(
                  name: group.name,
                  logoUrl: group.logoUrl,
                  radius: 44,
                ),
              ),
              if (canEditAvatar)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      onTap: _showAvatarOptions,
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFF2563EB),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: Color(0xFF2563EB),
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
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_c.memberCount} ${_c.memberCount == 1 ? 'member' : 'members'} · '
            '${_c.myRole.label} · ${_c.privacy.label}',
            key: const Key('group_header_meta'),
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),

          // Privacy Pill Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
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
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  '${(group.privacy ?? 'private').toUpperCase()} GROUP',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: Colors.white,
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
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps a section (Announcements, Rules, …) in the same premium card
  /// shell as the rest of this screen, plus a colored icon badge in its
  /// corner so sections read apart from each other at a glance instead of
  /// all looking like identical white boxes.
  Widget _sectionShell({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: AppRadius.xlBorder,
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: child,
            ),
          ),
          Positioned(
            left: 16,
            top: -2,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.22 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }

}
