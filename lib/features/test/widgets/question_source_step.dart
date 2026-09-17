import 'package:flutter/material.dart';

/// Where the test's questions come from. Only [manual] has a pipeline in
/// this build; the others are real product concepts shown truthfully as
/// "Not configured" (no fake extraction, no AI calls, no book content).
enum QuestionSource { manual, document, ai, books }

extension QuestionSourceInfo on QuestionSource {
  String get label {
    switch (this) {
      case QuestionSource.manual:
        return 'Manual';
      case QuestionSource.document:
        return 'Via Document';
      case QuestionSource.ai:
        return 'AI Generated';
      case QuestionSource.books:
        return 'From Books';
    }
  }

  String get description {
    switch (this) {
      case QuestionSource.manual:
        return 'Write questions yourself in the Questions step.';
      case QuestionSource.document:
        return 'PDF / Word / Excel → extracted content → questions → review → approval.';
      case QuestionSource.ai:
        return 'Subject, concept, count, difficulty and language → generated questions → review before publish.';
      case QuestionSource.books:
        return 'Subject → Book → Chapter → Topic → question bank → test.';
    }
  }

  /// True only when a real backend pipeline exists in this build.
  bool get isAvailable => this == QuestionSource.manual;

  IconData get icon {
    switch (this) {
      case QuestionSource.manual:
        return Icons.edit_note;
      case QuestionSource.document:
        return Icons.upload_file_outlined;
      case QuestionSource.ai:
        return Icons.auto_awesome_outlined;
      case QuestionSource.books:
        return Icons.menu_book_outlined;
    }
  }

  /// `tests.creation_method` value (`manual|upload|ai`) — sent only for
  /// sources that actually run; the wizard always persists `manual` today.
  String get creationMethod {
    switch (this) {
      case QuestionSource.manual:
        return 'manual';
      case QuestionSource.document:
        return 'upload';
      case QuestionSource.ai:
        return 'ai';
      case QuestionSource.books:
        return 'manual';
    }
  }
}

/// Question Source step. Selecting an unavailable source shows its honest
/// "Not configured" state and keeps Next disabled; nothing is faked.
class QuestionSourceStep extends StatelessWidget {
  const QuestionSourceStep({required this.selected, required this.onChanged, super.key});

  final QuestionSource selected;
  final ValueChanged<QuestionSource> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Question Source',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Choose how questions get into this test.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 16),
          for (final s in QuestionSource.values)
            Card(
              key: Key('source_${s.name}'),
              child: RadioListTile<QuestionSource>(
                value: s,
                groupValue: selected,
                onChanged: (v) => v == null ? null : onChanged(v),
                secondary: Icon(s.icon),
                title: Row(children: [
                  Expanded(child: Text(s.label)),
                  if (!s.isAvailable)
                    Chip(
                      label: const Text('Not configured'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                ]),
                subtitle: Text(s.description),
              ),
            ),
          if (!selected.isAvailable) ...[
            const SizedBox(height: 12),
            MaterialBanner(
              key: const Key('source_unavailable'),
              leading: const Icon(Icons.info_outline),
              content: Text(
                '${selected.label} has no processing pipeline in this build yet. '
                'Nothing is generated or extracted; switch to Manual to add questions.',
              ),
              actions: [
                TextButton(
                  onPressed: () => onChanged(QuestionSource.manual),
                  child: const Text('Use Manual'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
