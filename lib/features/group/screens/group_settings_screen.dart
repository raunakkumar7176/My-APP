import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../domain/group_errors.dart';
import '../domain/group_privacy.dart';
import '../state/group_hub_controller.dart';
import '../widgets/group_avatar.dart';

/// Basic group settings: name, description, privacy, and logo removal.
///
/// Editability comes from the server (`fn_has_permission(GROUP_SETTINGS)`,
/// which is true for the owner) — the UI only hides controls; the live
/// `groups` UPDATE policy is the boundary. Logo upload/replace is not offered:
/// no group-scoped storage policy exists live (see G2 report).
class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({
    required this.groupId,
    this.controller,
    super.key,
  });

  final String groupId;
  final GroupHubController? controller;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late final GroupHubController _c;
  late final bool _owns;
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
    } else {
      _c.load();
    }
  }

  void _onChanged() {
    if (!mounted) return;
    if (!_seeded && _c.group != null) _seedFromGroup();
    setState(() {});
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
