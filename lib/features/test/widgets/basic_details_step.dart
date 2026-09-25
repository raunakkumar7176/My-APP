import 'package:flutter/material.dart';

import '../domain/test_kind.dart';
import 'section_card.dart';

/// Title, description and the product-level Test Type picker.
/// The picker works purely in [TestKind]; storage mapping happens in the
/// controller via BackendMapping.
class BasicDetailsStep extends StatelessWidget {
  const BasicDetailsStep({
    required this.title,
    required this.description,
    required this.kind,
    required this.onTitleChanged,
    required this.onDescriptionChanged,
    required this.onKindChanged,
    this.titleError,
    super.key,
  });

  final String title;
  final String description;
  final TestKind kind;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onDescriptionChanged;
  final ValueChanged<TestKind> onKindChanged;
  final String? titleError;

  static String? hintFor(TestKind kind) {
    switch (kind) {
      case TestKind.practice:
        return 'Practice: no schedule, repeat as often as you like. '
            'A time limit is still applied by the server for now.';
      case TestKind.quick:
        return 'Quick: a short test — aim for 5–10 questions, about 10 minutes.';
      case TestKind.sectional:
        return 'Sectional: cover several subjects/topics via the Syllabus step.';
      case TestKind.challengeWithFriends:
        return 'Share the join code so friends can take it with you.';
      case TestKind.group:
        return 'Visible to members of the group you select.';
      case TestKind.self:
      case TestKind.adaptive:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Basic Details',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter the basic information for your test.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // ── Test Information Card ──
          SectionCard(
            title: 'Test Information',
            children: [
              TextFormField(
                initialValue: title,
                decoration: InputDecoration(
                  labelText: 'Test Title *',
                  hintText: 'e.g., History Chapter 1 Mock Test',
                  errorText: titleError,
                  prefixIcon: const Icon(Icons.title, size: 20),
                ),
                onChanged: onTitleChanged,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Optional description or instructions',
                  prefixIcon: Icon(Icons.description_outlined, size: 20),
                  alignLabelWithHint: true,
                ),
                onChanged: onDescriptionChanged,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),

          // ── Test Type Card ──
          SectionCard(
            title: 'Test Type',
            subtitle: hintFor(kind),
            children: [
              for (final k in TestKind.creatable)
                _TestTypeTile(
                  kind: k,
                  isSelected: k == kind,
                  onSelect: () => onKindChanged(k),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TestTypeTile extends StatelessWidget {
  const _TestTypeTile({
    required this.kind,
    required this.isSelected,
    required this.onSelect,
  });

  final TestKind kind;
  final bool isSelected;
  final VoidCallback onSelect;

  IconData _iconForKind() {
    switch (kind) {
      case TestKind.self:
        return Icons.person_outline;
      case TestKind.practice:
        return Icons.fitness_center;
      case TestKind.quick:
        return Icons.bolt_outlined;
      case TestKind.challengeWithFriends:
        return Icons.group_add_outlined;
      case TestKind.group:
        return Icons.groups_outlined;
      case TestKind.sectional:
        return Icons.view_module_outlined;
      case TestKind.adaptive:
        return Icons.auto_graph_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _iconForKind(),
                  size: 20,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kind.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        kind.purpose,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, size: 20, color: colorScheme.primary)
                else
                  Icon(
                    Icons.radio_button_unchecked,
                    size: 20,
                    color: colorScheme.outline,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
