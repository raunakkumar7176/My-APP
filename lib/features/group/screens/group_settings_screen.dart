import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../domain/group_errors.dart';
import '../domain/group_privacy.dart';
import '../state/group_hub_controller.dart';
import '../state/invite_code_controller.dart';
import '../widgets/group_avatar.dart';

/// Full group settings: profile, privacy, invite code, rules summary,
/// members summary, and a danger zone (leave).
///
/// Editability comes from the server (`fn_has_permission(GROUP_SETTINGS)`,
/// which is true for the owner) — the UI only hides controls; the live
/// `groups` UPDATE policy is the boundary. Logo upload/replace is not offered:
/// no group-scoped storage policy exists live (see G2 report).
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
  bool _seeded = false;
  String? _nameError;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? GroupHubController(groupId: widget.groupId);
    _c.addListener(_onChanged);
    if (_c.hasLoaded) {
      _seedFromGroup();
      _ensureInviteController();
    } else {
      _c.load();
    }
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
  /// save) must not overwrite what the user is typing.
  void _seedFromGroup() {
    final g = _c.group;
    if (g == null) return;
    _name.text = g.name;
    _description.text = g.description ?? '';
    _privacy = GroupPrivacy.fromDb(g.privacy);
    _seeded = true;
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    _invite?.removeListener(_onChanged);
    if (_ownsInvite) _invite?.dispose();
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
    final ok = await _c.updateBasics(
      name: _name.text,
      description: _description.text,
      privacy: _privacy,
    );
    if (!mounted) return;
    setState(() => _saved = ok);
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group settings saved.')));
    }
  }

  // ── invite code (G5.1) ──
  // Rendered only when canEditBasics (the controller is only created then).
  // The value is displayed, copied and rotated here and nowhere else.
  Widget _inviteSection(BuildContext context) {
    final i = _invite;
    if (i == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      key: const Key('invite_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Invite code', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Share this code so people can join. Rotating it invalidates the old '
          'code immediately.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (i.isLoading && !i.hasLoaded)
          const Padding(
            key: Key('invite_loading'),
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (i.code == null)
          Row(
            children: [
              Expanded(
                child: Text(
                  i.error ?? 'Invite code is not available.',
                  key: const Key('invite_error'),
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              TextButton(
                key: const Key('invite_retry'),
                onPressed: i.isBusy ? null : i.retry,
                child: const Text('Retry'),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  i.code!,
                  key: const Key('invite_code_value'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
              ),
              IconButton(
                key: const Key('invite_copy'),
                tooltip: 'Copy invite code',
                icon: const Icon(Icons.copy_outlined),
                onPressed: i.isBusy ? null : () => _copyInvite(i.code!),
              ),
            ],
          ),
          if (i.error != null)
            Text(
              i.error!,
              key: const Key('invite_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          if (i.justRotated && i.error == null)
            const Text(
              'New code generated.',
              key: Key('invite_rotated'),
              style: TextStyle(color: AppColors.success),
            ),
          OutlinedButton.icon(
            key: const Key('invite_rotate'),
            onPressed: i.isBusy ? null : _rotateInvite,
            icon: const Icon(Icons.refresh),
            label: Text(i.isRotating ? 'Rotating…' : 'Rotate invite code'),
          ),
        ],
      ],
    );
  }

  Future<void> _copyInvite(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Invite code copied.')));
  }

  Future<void> _rotateInvite() async {
    final i = _invite;
    if (i == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rotate invite code?'),
        content: const Text(
          'The current code will stop working immediately. Anyone who has not '
          'joined yet will need the new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_rotate'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Rotate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await i.rotate();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Invite code rotated.'
              : (i.error ?? 'Could not rotate the code.'),
        ),
        backgroundColor: ok ? null : AppColors.error,
      ),
    );
  }

  Widget _rulesSummary(BuildContext context) {
    final rules = _c.rules;
    final isLoading = _c.rulesLoading && rules.isEmpty;
    final error = _c.rulesError;
    final theme = Theme.of(context);
    return Column(
      key: const Key('settings_rules_summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.gavel_outlined,
              size: 20,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text('Group rules', style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            if (!isLoading)
              Text(
                '${rules.length}',
                key: const Key('settings_rules_count'),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (isLoading)
          const LinearProgressIndicator(key: Key('settings_rules_loading'))
        else if (error != null && rules.isEmpty)
          Text(
            error,
            key: const Key('settings_rules_error'),
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          )
        else if (rules.isEmpty)
          Text(
            'No rules yet.',
            key: const Key('settings_rules_empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final rule in rules.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                rule.ruleText,
                key: Key('settings_rule_${rule.id}'),
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        if (rules.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+${rules.length - 3} more',
              key: const Key('settings_rules_more'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (rules.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('settings_manage_rules'),
            onPressed: () => context.push('/groups/${widget.groupId}'),
            child: const Text('Manage rules'),
          ),
        ],
      ],
    );
  }

  Widget _membersSummary(BuildContext context) {
    final group = _c.group;
    if (group == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final myRole = _c.myRole;
    return Column(
      key: const Key('settings_members_summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.people_outlined,
              size: 20,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text('Members', style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              '${_c.memberCount}',
              key: const Key('settings_members_count'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Your role: ${myRole.label}',
          key: const Key('settings_my_role'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('settings_manage_members'),
          onPressed: () => context.push('/groups/${widget.groupId}/members'),
          child: const Text('Manage members'),
        ),
      ],
    );
  }

  Widget _leaveSection(BuildContext context) {
    final theme = Theme.of(context);
    final canLeave = _c.canLeave;
    final blockedReason = _c.leaveBlockedReason;
    return Column(
      key: const Key('settings_leave_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.logout, size: 20, color: AppColors.error),
            const SizedBox(width: 8),
            Text(
              'Danger zone',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (canLeave)
          OutlinedButton.icon(
            key: const Key('settings_leave_button'),
            onPressed: _c.isBusy ? null : _leaveGroup,
            icon: const Icon(Icons.logout, color: AppColors.error),
            label: const Text(
              'Leave group',
              style: TextStyle(color: AppColors.error),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.error),
            ),
          )
        else
          Text(
            blockedReason,
            key: const Key('settings_leave_blocked'),
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
      ],
    );
  }

  Future<void> _leaveGroup() async {
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('You left the group.')));
      context.go('/groups');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_c.error ?? 'Could not leave the group.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
    if (!_c.canEditBasics) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group Settings')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Only the group owner or a member with the settings permission '
              'can change these.',
              key: Key('settings_forbidden'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final hasLogo = (group.logoUrl ?? '').trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Group Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              GroupAvatar(name: group.name, logoUrl: group.logoUrl, radius: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Logo', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      hasLogo
                          ? 'A logo is set for this group.'
                          : 'No logo yet. Uploading a logo needs a group-scoped '
                                'storage policy that is not available yet.',
                      key: const Key('logo_status'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (hasLogo)
                      TextButton.icon(
                        key: const Key('remove_logo_button'),
                        onPressed: _c.isBusy ? null : _removeLogo,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove logo'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 24),
          _inviteSection(context),
          TextField(
            key: const Key('settings_name_field'),
            controller: _name,
            maxLength: GroupErrors.nameMaxLength,
            decoration: InputDecoration(
              labelText: 'Group name',
              border: const OutlineInputBorder(),
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('settings_description_field'),
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Privacy', style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<GroupPrivacy>(
            groupValue: _privacy,
            onChanged: (v) => setState(() => _privacy = v ?? _privacy),
            child: Column(
              children: [
                for (final p in GroupPrivacy.values)
                  RadioListTile<GroupPrivacy>(
                    key: Key('settings_privacy_${p.name}'),
                    value: p,
                    title: Text(p.label),
                    subtitle: Text(p.description),
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
          FilledButton(
            key: const Key('settings_save'),
            // Disabled while the update is in flight: no duplicate submission.
            onPressed: _c.isBusy ? null : _save,
            child: Text(_c.isBusy ? 'Saving…' : 'Save'),
          ),
          const SizedBox(height: 24),
          // ── Rules summary ──
          const Divider(),
          const SizedBox(height: 8),
          _rulesSummary(context),
          const SizedBox(height: 24),
          // ── Members summary ──
          const Divider(),
          const SizedBox(height: 8),
          _membersSummary(context),
          const SizedBox(height: 24),
          // ── Danger zone: leave ──
          const Divider(),
          const SizedBox(height: 8),
          _leaveSection(context),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Back to group'),
          ),
        ],
      ),
    );
  }
}
