import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/test_template.dart';
import '../domain/test_kind.dart';
import '../state/test_template_controller.dart';
import '../widgets/test_formatters.dart';

/// G19 — Displays the user's saved test templates.
/// Supports: loading, empty state, refresh, error + retry, delete.
class TemplateListingScreen extends StatefulWidget {
  const TemplateListingScreen({this.controller, super.key});

  final TestTemplateController? controller;

  @override
  State<TemplateListingScreen> createState() => _TemplateListingScreenState();
}

class _TemplateListingScreenState extends State<TemplateListingScreen> {
  late final TestTemplateController _c;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _c = widget.controller ?? TestTemplateController();
    _c.addListener(_onChanged);
    _c.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    if (_ownsController) _c.dispose();
    super.dispose();
  }

  Future<void> _pushThenRefresh(String location) async {
    await context.push(location);
    if (mounted) await _c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          IconButton(
            key: const Key('templates_refresh'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _c.refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_template_fab'),
        onPressed: () => _pushThenRefresh('/tests/templates/create'),
        icon: const Icon(Icons.add),
        label: const Text('Create Template'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_c.isLoading && !_c.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_c.error != null) return _errorState(_c.error!);

    final templates = _c.myTemplates;
    if (templates.isEmpty) return _emptyState();

    return RefreshIndicator(
      onRefresh: _c.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: templates.length,
        itemBuilder: (_, i) => _TemplateCard(
          template: templates[i],
          onTap: () => _pushThenRefresh(
            '/tests/templates/${templates[i].id}/edit',
          ),
          onUse: () => _useTemplate(templates[i]),
          onDelete: () => _confirmDelete(templates[i]),
        ),
      ),
    );
  }

  Future<void> _useTemplate(TestTemplate template) async {
    final configuration = template.configuration;
    final kindName = configuration['kind'] as String?;
    final kind = TestKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => TestKind.self,
    );

    final uri = Uri(
      path: '/tests/create',
      queryParameters: {
        if (template.groupId != null) 'group': template.groupId,
        'fromTemplate': template.id,
      },
    );
    await context.push(uri.toString(), extra: template);
    if (mounted) await _c.refresh();
  }

  Future<void> _confirmDelete(TestTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Delete "${template.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _c.delete(template.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _c.refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No templates yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Save a test configuration as a template to reuse it later.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onTap,
    required this.onUse,
    required this.onDelete,
  });

  final TestTemplate template;
  final VoidCallback onTap;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final kindName = template.kind;
    final kindLabel = kindName != null
        ? TestKind.values
            .firstWhere(
              (k) => k.name == kindName,
              orElse: () => TestKind.self,
            )
            .label
        : 'Unknown';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    key: Key('template_menu_${template.id}'),
                    onSelected: (value) {
                      if (value == 'edit') onTap();
                      if (value == 'use') onUse();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'use',
                        child: Text('Use Template'),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              if (template.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  template.description,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _chip(context, Icons.category_outlined, kindLabel),
                  if (template.durationSec != null)
                    _chip(
                      context,
                      Icons.timer_outlined,
                      TestFormatters.duration(template.durationSec),
                    ),
                  if (template.isGroupTemplate)
                    _chip(context, Icons.group_outlined, 'Group'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
