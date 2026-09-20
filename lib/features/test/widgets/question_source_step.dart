import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/question_bank_item.dart';
import '../models/question_draft.dart';
import '../screens/ai_generation_screen.dart';

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
  bool get isAvailable =>
      this == QuestionSource.manual ||
      this == QuestionSource.document ||
      this == QuestionSource.books;

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
          const SizedBox(height: 8),
          Text(
            'Choose how questions get into this test.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          for (final s in QuestionSource.values)
            Card(
              key: Key('source_${s.name}'),
              child: RadioListTile<QuestionSource>(
                value: s,
                groupValue: selected,
                onChanged: (v) {
                  if (v == null) return;
                  onChanged(v);
                  if (v == QuestionSource.books) {
                    _openQuestionBank(context);
                  } else if (v == QuestionSource.document) {
                    _openDocumentImport(context);
                  } else if (v == QuestionSource.ai) {
                    _openAiGeneration(context);
                  }
                },
                secondary: Icon(s.icon),
                title: Row(
                  children: [
                    Expanded(child: Text(s.label)),
                    if (!s.isAvailable)
                      Chip(
                        label: const Text('Not configured'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                  ],
                ),
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
      extra: {
        'groupId': groupId,
      },
    );

    if (drafts != null &&
        drafts.isNotEmpty &&
        onDocumentQuestionsSelected != null) {
      onDocumentQuestionsSelected!(drafts);
    }
  }

  Future<void> _openAiGeneration(BuildContext context) async {
    final result = await context.push<AiGenerationComplete>(
      '/tests/create/ai-generate',
      extra: AiGenerationPrefill(
        subject: subject,
        topic: topic,
        chapter: chapter,
        groupId: groupId,
        testMode: testMode,
        marksPerQuestion: marksPerQuestion,
      ),
    );

    if (result != null &&
        result.questions.isNotEmpty &&
        onAiQuestionsSelected != null) {
      onAiQuestionsSelected!(result.questions);
    }
  }
}
