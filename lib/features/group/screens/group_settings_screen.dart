import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/theme/app_colors.dart' as premium;
import '../../../core/theme/app_radius.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/group_errors.dart';
import '../domain/group_privacy.dart';
import '../state/group_hub_controller.dart';
import '../state/invite_code_controller.dart';
import '../widgets/group_announcements_section.dart';
import '../widgets/group_avatar.dart';
import '../widgets/group_rules_section.dart';
import '../widgets/settings_danger_zone.dart';
import '../widgets/settings_invite_card.dart';
import '../widgets/settings_permissions_card.dart';
import '../widgets/settings_reports_card.dart';
import '../widgets/settings_requests_card.dart';

/// Full group settings: profile/logo, privacy, invite (code/share/QR/
/// expiry/max-uses), permissions, rules, announcements, join requests +
/// invitation history, and a danger zone (transfer ownership / delete /
/// leave). Editability comes from the server (`fn_has_permission
/// (GROUP_SETTINGS)`, true for the owner) — the UI only hides controls;
/// the live `groups` UPDATE policy is the boundary.
class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({
    required this.groupId,
    this.controller,
    this.inviteCodeController,
    super.key,
  });

  final String groupId;
  final GroupHubController? controller;

  /// Injectable for tests; created lazily otherwise, and only once the
  /// caller is known to hold GROUP_SETTINGS / be the owner.
  final InviteCodeController? inviteCodeController;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late final GroupHubController _c;
  late final bool _owns;
  InviteCodeController? _invite;
  bool _ownsInvite = false;
  final _name = TextEditingController();
  final _description = TextEditingController();
  GroupPrivacy _privacy = GroupPrivacy.public;
  String _initialName = '';
  String _initialDescription = '';
  GroupPrivacy _initialPrivacy = GroupPrivacy.public;
  bool _seeded = false;
  String? _nameError;
  bool _saving = false;
  bool _saved = false;

  bool get _dirty =>
      _name.text.trim() != _initialName ||
      _description.text.trim() != _initialDescription ||
      _privacy != _initialPrivacy;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? GroupHubController(groupId: widget.groupId);
    _c.addListener(_onChanged);
    _name.addListener(_onFieldEdited);
    _description.addListener(_onFieldEdited);
    if (_c.hasLoaded) {
      _seedFromGroup();
      _ensureInviteController();
    } else {
      _c.load();
    }
  }

  void _onFieldEdited() {
    if (mounted) setState(() => _saved = false);
  }

  void _onChanged() {
    if (!mounted) return;
    if (!_seeded && _c.group != null) _seedFromGroup();
    _ensureInviteController();
    setState(() {});
  }

  /// The invite code is requested only after the server-derived permission
  /// says this caller may manage settings. Nobody else ever triggers the read.
  void _ensureInviteController() {
    if (_invite != null ||
        !_c.hasLoaded ||
        _c.group == null ||
        !_c.canEditBasics) {
      return;
    }
    _ownsInvite = widget.inviteCodeController == null;
    _invite =
        widget.inviteCodeController ??
        InviteCodeController(groupId: widget.groupId);
    _invite!.addListener(_onChanged);
    if (!_invite!.hasLoaded) _invite!.load();
  }

  /// Seeds the fields once from the loaded group; a later reload (after
  /// save) re-seeds so "unsaved changes" reflects the new baseline.
  void _seedFromGroup() {
    final g = _c.group;
    if (g == null) return;
    _name.text = g.name;
    _description.text = g.description ?? '';
    _privacy = GroupPrivacy.fromDb(g.privacy);
    _initialName = _name.text.trim();
    _initialDescription = _description.text.trim();
    _initialPrivacy = _privacy;
    _seeded = true;
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    _invite?.removeListener(_onChanged);
    if (_ownsInvite) _invite?.dispose();
    _name.removeListener(_onFieldEdited);
    _description.removeListener(_onFieldEdited);
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final invalid = GroupErrors.validateName(_name.text);
    setState(() {
      _nameError = invalid;
      _saved = false;
    });
    if (invalid != null) return;
    setState(() => _saving = true);
    final ok = await _c.updateBasics(
      name: _name.text,
      description: _description.text,
      privacy: _privacy,
    );
    if (!mounted) return;
    // Re-seed BEFORE flipping _saved: reassigning the controllers' .text
    // (even to the value they already hold) resets TextEditingValue's
    // selection, which notifies _onFieldEdited and would otherwise clear
    // _saved right back to false.
    if (ok) _seedFromGroup(); // new baseline — the sticky bar disappears
    setState(() {
      _saving = false;
      _saved = ok;
    });
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group settings saved.')));
    }
    // On failure, the inline `settings_error` text below already shows
    // _c.error — no separate SnackBar, so the message isn't shown twice.
  }

  void _discardChanges() {
    setState(() {
      _name.text = _initialName;
      _description.text = _initialDescription;
      _privacy = _initialPrivacy;
      _nameError = null;
    });
  }

  Future<bool> _confirmDiscardAndLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes to this group\'s settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const Key('confirm_discard_changes'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _removeLogo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove logo?'),
        content: const Text('The group will show its initial instead.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_remove_logo'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _c.clearLogo();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Logo removed.' : (_c.error ?? 'Could not remove the logo.'),
        ),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  /// Client-side guard before any upload: a reasonable size cap and an
  /// image-only type check. The actual storage bucket/policy are assumed
  /// already provisioned server-side (group-avatars, falling back to the
  /// shared avatars bucket) — unchanged from before this screen's rebuild.
  static const _maxLogoBytes = 5 * 1024 * 1024; // 5 MB

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    Navigator.of(context).pop();
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxLogoBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That image is too large (max 5 MB).'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Group logo updated.' : (_c.error ?? 'Failed to update logo.'),
          ),
          backgroundColor: ok ? null : AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not upload group logo: $e'),
          backgroundColor: AppColors.error,
        ),
      );
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
              'Change Group Logo',
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
            if ((_c.group?.logoUrl ?? '').trim().isNotEmpty)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Remove Logo',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _removeLogo();
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
        appBar: AppBar(title: const Text('Group Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final group = _c.group;
    if (_c.accessDenied || group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Settings')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _c.error ?? 'This group is not available.',
              key: const Key('settings_unavailable'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    // "Forbidden" means no card on this screen applies to this caller at
    // all — Basics/Privacy/Invite/Permissions/Rules still need
    // canEditBasics specifically, but Announcements (SEND_ANNOUNCEMENT)
    // and Requests (MANAGE_MEMBERS) are real, narrower capabilities a
    // leader/admin can hold without GROUP_SETTINGS (the live default
    // seeding grants everything except GROUP_SETTINGS and MANAGE_ROLES) —
    // locking them out of posting an announcement here just because they
    // lack GROUP_SETTINGS would be a real regression, not a UX nicety.
    final hasAnySettingsCapability =
        _c.canEditBasics ||
        _c.canSendAnnouncement ||
        _c.canManageMembers ||
        _c.canManageRolePermissions;
    if (!hasAnySettingsCapability) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Settings')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Only the group owner or a member with a settings-related '
                  'permission can change these.',
                  key: Key('settings_forbidden'),
                  textAlign: TextAlign.center,
                ),
                // Leaving needs no permission at all — never hidden behind
                // the capability gate above.
                if (_c.canLeave) ...[
                  const SizedBox(height: 16),
                  SettingsDangerZone(controller: _c),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final hasLogo = (group.logoUrl ?? '').trim().isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dirty = _dirty;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardAndLeave()) {
          _discardChanges();
          if (mounted) Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC),
        appBar: AppBar(title: const Text('Group Settings')),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  if (_c.canEditBasics) ...[
                    Container(
                      padding: const EdgeInsets.all(18),
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
                      child: Row(
                        children: [
                          InkWell(
                            onTap: _showAvatarOptions,
                            borderRadius: AppRadius.pillBorder,
                            child: Stack(
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
                                    radius: 30,
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF2563EB),
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 13,
                                      color: Color(0xFF2563EB),
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
                                Text(
                                  'Logo',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasLogo
                                      ? 'Tap to change group logo.'
                                      : 'Tap to set group logo.',
                                  key: const Key('logo_status'),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12.5,
                                  ),
                                ),
                                if (hasLogo)
                                  TextButton.icon(
                                    key: const Key('remove_logo_button'),
                                    onPressed: _c.isBusy ? null : _removeLogo,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Remove logo'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      isDark: isDark,
                      icon: Icons.edit_outlined,
                      iconColor: const Color(0xFF2563EB),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Basics',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const Key('settings_name_field'),
                            controller: _name,
                            enabled: true,
                            maxLength: GroupErrors.nameMaxLength,
                            decoration: InputDecoration(
                              labelText: 'Group name',
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              border: const OutlineInputBorder(
                                borderRadius: AppRadius.mdBorder,
                              ),
                              errorText: _nameError,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('settings_description_field'),
                            controller: _description,
                            enabled: true,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: 'Description',
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              border: const OutlineInputBorder(
                                borderRadius: AppRadius.mdBorder,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      isDark: isDark,
                      icon: Icons.policy_outlined,
                      iconColor: const Color(0xFF0EA5E9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Privacy',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          RadioGroup<GroupPrivacy>(
                            groupValue: _privacy,
                            onChanged: (v) =>
                                setState(() => _privacy = v ?? _privacy),
                            child: Column(
                              children: [
                                for (final p in GroupPrivacy.values)
                                  RadioListTile<GroupPrivacy>(
                                    key: Key('settings_privacy_${p.name}'),
                                    contentPadding: EdgeInsets.zero,
                                    value: p,
                                    title: Text(p.label),
                                    subtitle: Text(p.description),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_c.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _c.error!,
                        key: const Key('settings_error'),
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                    if (_saved && _c.error == null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Saved.',
                        key: Key('settings_saved'),
                        style: TextStyle(color: AppColors.success),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_invite != null)
                      _sectionCard(
                        isDark: isDark,
                        icon: Icons.vpn_key_outlined,
                        iconColor: const Color(0xFF059669),
                        child: SettingsInviteCard(controller: _invite!),
                      ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      isDark: isDark,
                      icon: Icons.admin_panel_settings_outlined,
                      iconColor: const Color(0xFF7C3AED),
                      child: SettingsPermissionsCard(controller: _c),
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      isDark: isDark,
                      icon: Icons.gavel_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      child: GroupRulesSection(controller: _c),
                    ),
                  ], // end canEditBasics-only cards (Logo/Basics/Privacy/Invite/Permissions/Rules)
                  if (_c.canSendAnnouncement || _c.canEditBasics) ...[
                    const SizedBox(height: 16),
                    _sectionCard(
                      isDark: isDark,
                      icon: Icons.campaign_rounded,
                      iconColor: const Color(0xFFD97706),
                      child: GroupAnnouncementsSection(controller: _c),
                    ),
                  ],
                  if (_c.canManageMembers) ...[
                    const SizedBox(height: 16),
                    _sectionCard(
                      isDark: isDark,
                      icon: Icons.how_to_reg_outlined,
                      iconColor: const Color(0xFF2563EB),
                      child: SettingsRequestsCard(controller: _c),
                    ),
                  ],
                  if (_c.canModerateReports) ...[
                    const SizedBox(height: 16),
                    _sectionCard(
                      isDark: isDark,
                      icon: Icons.flag_outlined,
                      iconColor: AppColors.error,
                      child: SettingsReportsCard(controller: _c),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SettingsDangerZone(controller: _c),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () async {
                        if (await _confirmDiscardAndLeave()) {
                          _discardChanges();
                          if (mounted) context.pop();
                        }
                      },
                      child: const Text('Back to group'),
                    ),
                  ),
                  SizedBox(height: dirty ? 72 : 8),
                ],
              ),
            ),
            if (dirty)
              _StickySaveBar(
                key: const Key('settings_sticky_save_bar'),
                saving: _saving,
                onDiscard: _discardChanges,
                onSave: _save,
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required bool isDark,
    required Widget child,
    IconData? icon,
    Color? iconColor,
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
          // ListTile/RadioListTile paint their background/ink on the
          // nearest Material ancestor — without this, Flutter asserts
          // (their splash and selected-background effects would otherwise
          // be invisible, painted underneath this card's own background).
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, icon != null ? 20 : 16, 16, 16),
              child: child,
            ),
          ),
          if (icon != null)
            Positioned(
              left: 16,
              top: -2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (iconColor ?? const Color(0xFF2563EB)).withValues(
                    alpha: isDark ? 0.22 : 0.12,
                  ),
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

class _StickySaveBar extends StatelessWidget {
  const _StickySaveBar({
    required this.saving,
    required this.onDiscard,
    required this.onSave,
    super.key,
  });

  final bool saving;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 8,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              const Expanded(child: Text('You have unsaved changes')),
              TextButton(
                key: const Key('settings_discard_button'),
                onPressed: saving ? null : onDiscard,
                child: const Text('Discard'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('settings_save'),
                onPressed: saving ? null : onSave,
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
