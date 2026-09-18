import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../domain/group_errors.dart';
import '../domain/group_privacy.dart';
import '../state/group_list_controller.dart';

/// Create a group through `fn_create_group`, which also creates the owner
/// membership row and the default leader permissions. Nothing is written from
/// the client, so there is no half-created group to clean up.
class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({this.controller, super.key});

  final GroupListController? controller;

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  late final GroupListController _c;
  late final bool _owns;
  final _name = TextEditingController();
  final _description = TextEditingController();
  GroupPrivacy _privacy = GroupPrivacy.public;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? GroupListController();
    _c.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_owns) _c.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final invalid = GroupErrors.validateName(_name.text);
    setState(() => _nameError = invalid);
    if (invalid != null) return;

    final id = await _c.create(
      name: _name.text,
      description: _description.text,
      privacy: _privacy.db,
    );
    if (!mounted || id == null) return;
    // Straight into the new group's hub; the list behind is refreshed by the
    // caller when this route pops.
    context.pushReplacement('/groups/$id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Group')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('group_name_field'),
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
            key: const Key('group_description_field'),
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
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
                    key: Key('privacy_${p.name}'),
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
              key: const Key('create_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('create_group_submit'),
            // Disabled while the RPC is in flight: this is what prevents a
            // duplicate group from a double tap.
            onPressed: _c.isBusy ? null : _submit,
            child: Text(_c.isBusy ? 'Creating…' : 'Create Group'),
          ),
        ],
      ),
    );
  }
}
