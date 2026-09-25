import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/question_bank_item.dart';
import '../models/question_draft.dart';
import '../screens/ai_generation_screen.dart';
import 'section_card.dart';

/// Where the test's questions come from.
/// - [manual]: Write questions yourself
/// - [document]: Extract from PDF/Word/Excel (V1 — implemented)
/// - [ai]: AI-generated questions (V1 — implemented)
/// - [books]: Select from the question bank (R7 - implemented)
enum QuestionSource { manual, document, ai, books }

extension QuestionSourceInfo on QuestionSource {
  String get label {
    switch (this) {
      case QuestionSource.manual:
        return 'Manual';
      case QuestionSource.document:
        return 'Smart Document & AI Intake';
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
        return 'Upload PDF / Word / TXT / Image → auto-detects MCQs or synthesizes via Gemini AI.';
      case QuestionSource.ai:
        return 'Subject, concept, count, difficulty and language → generated questions → review before publish.';
      case QuestionSource.books:
        return 'Subject → Book → Chapter → Topic → question bank → test.';
    }
  }

  /// True only when a real backend pipeline exists in this build.
  bool get isAvailable =>
      this == QuestionSource.manual ||
      this == QuestionSource.document ||
      this == QuestionSource.ai ||
      this == QuestionSource.books;

  IconData get icon {
    switch (this) {
      case QuestionSource.manual:
        return Icons.edit_note;
      case QuestionSource.document:
        return Icons.document_scanner_outlined;
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
  const QuestionSourceStep({
    required this.selected,
    required this.onChanged,
    this.onBankQuestionsSelected,
    this.onDocumentQuestionsSelected,
    this.onAiQuestionsSelected,
    this.groupId,
    this.testMode = 'self',
    this.subject = '',
    this.topic = '',
    this.chapter = '',
    this.marksPerQuestion = 1,
    super.key,
  });

  final QuestionSource selected;
  final ValueChanged<QuestionSource> onChanged;

  /// Called when user selects questions from the bank.
  /// Only invoked when [QuestionSource.books] is selected and questions are chosen.
  final ValueChanged<List<QuestionBankItem>>? onBankQuestionsSelected;

  /// Called when user confirms questions from a document import.
  final ValueChanged<List<QuestionDraft>>? onDocumentQuestionsSelected;

  /// Called when user completes AI generation and review.
  final ValueChanged<List<QuestionDraft>>? onAiQuestionsSelected;

  /// Group context for document upload (for group-scoped storage).
  final String? groupId;

  /// Test mode for AI generation context.
  final String testMode;

  /// Pre-filled subject for AI generation.
  final String subject;

  /// Pre-filled topic for AI generation.
  final String topic;

  /// Pre-filled chapter for AI generation.
  final String chapter;

  /// Marks per question for AI generation.
  final double marksPerQuestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question Source',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose how questions get into this test.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // ── Source Selection ──
          SectionCard(
            title: 'Select Source',
            children: [
              for (final s in QuestionSource.values)
                _SourceTile(
                  source: s,
                  isSelected: s == selected,
                  onSelect: () {
                    onChanged(s);
                    if (s == QuestionSource.books) {
                      _openQuestionBank(context);
                    } else if (s == QuestionSource.document) {
                      _openDocumentImport(context);
                    } else if (s == QuestionSource.ai) {
                      _openAiGeneration(context);
                    }
                  },
                ),
            ],
          ),

          // ── Unavailable Source Banner ──
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

  Future<void> _openQuestionBank(BuildContext context) async {
    final result = await context.push<List<QuestionBankItem>>(
      '/question-bank',
      extra: {
        'selectionMode': true,
        'onSelectionConfirmed': onBankQuestionsSelected,
      },
    );

    if (result != null &&
        result.isNotEmpty &&
        onBankQuestionsSelected != null) {
      onBankQuestionsSelected!(result);
    }
  }

  Future<void> _openDocumentImport(BuildContext context) async {
    final drafts = await context.push<List<QuestionDraft>>(
      '/tests/create/document-import',
      extra: {'groupId': groupId},
    );

    if (drafts != null &&
        drafts.isNotEmpty &&
        onDocumentQuestionsSelected != null) {
      onDocumentQuestionsSelected!(drafts);
    }
  }

  Future<void> _openAiGeneration(BuildContext context) async {
    final choice = await showModalBottomSheet<_AiSourceChoice>(
      context: context,
      builder: (ctx) => const _AiSourceChooser(),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case _AiSourceChoice.topic:
        await _pushAiGeneration(context, const AiGenerationPrefill());
      case _AiSourceChoice.camera:
      case _AiSourceChoice.file:
        await _openDocumentImport(context);
    }
  }

  Future<void> _pushAiGeneration(
    BuildContext context,
    AiGenerationPrefill base,
  ) async {
    final result = await context.push<AiGenerationComplete>(
      '/tests/create/ai-generate',
      extra: AiGenerationPrefill(
        subject: subject.isNotEmpty ? subject : base.subject,
        topic: topic.isNotEmpty ? topic : base.topic,
        chapter: chapter.isNotEmpty ? chapter : base.chapter,
        groupId: groupId,
        testMode: testMode,
        marksPerQuestion: marksPerQuestion,
        sourceText: base.sourceText,
        sourceLabel: base.sourceLabel,
      ),
    );

    if (result != null &&
        result.questions.isNotEmpty &&
        onAiQuestionsSelected != null) {
      onAiQuestionsSelected!(result.questions);
    }
  }
}

enum _AiSourceChoice { camera, file, topic }

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.isSelected,
    required this.onSelect,
  });

  final QuestionSource source;
  final bool isSelected;
  final VoidCallback onSelect;

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
          onTap: source.isAvailable ? onSelect : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    source.icon,
                    size: 22,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              source.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (!source.isAvailable)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'N/A',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AiSourceChooser extends StatelessWidget {
  const _AiSourceChooser();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How should AI get the topic?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const Key('ai_source_camera'),
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photos'),
              onTap: () => Navigator.of(context).pop(_AiSourceChoice.camera),
            ),
            ListTile(
              key: const Key('ai_source_file'),
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Choose File'),
              onTap: () => Navigator.of(context).pop(_AiSourceChoice.file),
            ),
            ListTile(
              key: const Key('ai_source_topic'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Enter Topic'),
              onTap: () => Navigator.of(context).pop(_AiSourceChoice.topic),
            ),
          ],
        ),
      ),
    );
  }
}
