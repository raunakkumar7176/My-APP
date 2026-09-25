import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/group_rule.dart';
import '../state/group_hub_controller.dart';

/// Rules section in the group hub. Members see the rules; callers whose
/// server-reported GROUP_SETTINGS permission (or owner, via the function's
/// own bypass) is true see Add/Edit/Delete controls — the same gate as the
/// group settings screen. The live RLS is the boundary: member SELECT,
/// GROUP_SETTINGS-or-owner INSERT/UPDATE/DELETE. UI visibility is UX only.
class GroupRulesSection extends StatelessWidget {
  const GroupRulesSection({required this.controller, super.key});

  final GroupHubController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return Column(
      key: const Key('group_rules_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Group rules', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            if (c.rules.isNotEmpty)
              Text(
                '${c.rules.length}',
                key: const Key('rules_count'),
                style: theme.textTheme.bodySmall,
              ),
            const Spacer(),
            if (c.canEditBasics)
              TextButton.icon(
                key: const Key('add_rule_button'),
                onPressed: c.rulesSaving ? null : () => _addRule(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add rule'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.rulesLoading && c.rules.isEmpty && c.rulesError == null)
          const LinearProgressIndicator(key: Key('rules_loading'))
        else if (c.rulesError != null && c.rules.isEmpty)
          Row(
            key: const Key('rules_error'),
            children: [
              Expanded(
                child: Text(
                  c.rulesError!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              TextButton(
                key: const Key('rules_retry'),
                onPressed: c.rulesSaving ? null : c.retryRules,
                child: const Text('Retry'),
              ),
            ],
          )
        else if (c.rules.isEmpty)
          Text(
            'No rules yet.',
            key: const Key('rules_empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final rule in c.rules) _tile(context, rule),
        if (c.rulesError != null && c.rules.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              c.rulesError!,
              key: const Key('rules_action_error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, GroupRule rule) {
    final c = controller;
    final acting = c.actingRuleId == rule.id;
    final disabled = acting || c.rulesSaving;
    return ListTile(
      key: Key('rule_${rule.id}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.gavel_outlined),
      title: Text(rule.ruleText),
      subtitle: Text(_when(rule.createdAt)),
      trailing: c.canEditBasics
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('edit_rule_${rule.id}'),
                  tooltip: 'Edit rule',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: disabled ? null : () => _editRule(context, rule),
                ),
                IconButton(
                  key: Key('delete_rule_${rule.id}'),
                  tooltip: 'Delete rule',
                  icon: acting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 20),
                  onPressed: disabled ? null : () => _deleteRule(context, rule),
                ),
              ],
            )
          : null,
    );
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _addRule(BuildContext context) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add group rule'),
        content: TextField(
          key: const Key('new_rule_field'),
          controller: controller,
          maxLines: 3,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Enter rule text',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_add_rule'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final done = await this.controller.createRule(controller.text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Rule added.'
              : (this.controller.error ?? 'Could not add rule.'),
        ),
        backgroundColor: done ? null : AppColors.error,
      ),
    );
  }

  Future<void> _editRule(BuildContext context, GroupRule rule) async {
    final controller = TextEditingController(text: rule.ruleText);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit rule'),
        content: TextField(
          key: const Key('edit_rule_field'),
          controller: controller,
          maxLines: 3,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Enter rule text',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_edit_rule'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final done = await this.controller.updateRule(rule, controller.text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Rule updated.'
              : (this.controller.error ?? 'Could not update rule.'),
        ),
        backgroundColor: done ? null : AppColors.error,
      ),
    );
  }

  Future<void> _deleteRule(BuildContext context, GroupRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete rule?'),
        content: const Text('This rule will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_rule'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final done = await controller.deleteRule(rule);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'Rule deleted.'
              : (controller.error ?? 'Could not delete rule.'),
        ),
        backgroundColor: done ? null : AppColors.error,
      ),
    );
  }
}
