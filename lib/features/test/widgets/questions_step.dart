import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/question.dart';
import '../models/question_draft.dart';
import 'question_editor.dart';

/// Questions step (R4 restart). Local drafts are edited in place; server
/// questions are edited/deleted through the controller callbacks — this
/// widget never talks to Supabase.
class QuestionsStep extends StatefulWidget {
  const QuestionsStep({
    required this.localQuestions,
    required this.serverQuestions,
    required this.onLocalQuestionsChanged,
    required this.onDeleteServerQuestion,
    required this.onUpdateServerQuestion,
    this.guidance,
    this.busy = false,
    super.key,
  });

  final List<QuestionDraft> localQuestions;
  final List<Question> serverQuestions;
  final ValueChanged<List<QuestionDraft>> onLocalQuestionsChanged;

  /// Throw an [AppError] to show its message.
  final Future<void> Function(Question question) onDeleteServerQuestion;
  final Future<void> Function(Question original, QuestionDraft updated)
      onUpdateServerQuestion;

  /// Non-blocking hint (e.g. Quick Test size guidance).
  final String? guidance;
  final bool busy;

  @override
  State<QuestionsStep> createState() => _QuestionsStepState();
}

class _QuestionsStepState extends State<QuestionsStep> {
  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _openEditor({
    QuestionDraft? initial,
    required ValueChanged<QuestionDraft> onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: QuestionEditor(
          initial: initial,
          onSave: (draft) {
            Navigator.of(ctx).pop();
            onSave(draft);
          },
        ),
      ),
    );
  }

  void _addLocal() => _openEditor(
        onSave: (d) =>
            widget.onLocalQuestionsChanged([...widget.localQuestions, d]),
      );

  void _editLocal(int index) => _openEditor(
        initial: widget.localQuestions[index],
        onSave: (d) {
          final updated = List<QuestionDraft>.from(widget.localQuestions);
          updated[index] = d;
          widget.onLocalQuestionsChanged(updated);
        },
      );

  void _deleteLocal(int index) {
    final updated = List<QuestionDraft>.from(widget.localQuestions)
      ..removeAt(index);
    widget.onLocalQuestionsChanged(updated);
  }

  Future<void> _editServer(Question q) => _openEditor(
        initial: QuestionDraft(
          id: q.id,
          questionText: q.question,
          questionType: q.questionType ?? QuestionType.mcqSingle,
          options: [
            for (final o in q.options ?? const <QuestionOption>[])
              QuestionOptionDraft(id: o.id, text: o.text),
          ],
          correctOptionIndex: null, // never exposed by the safe RPC
          explanation: q.explanation,
          subjectId: q.subjectId,
          topicNodeId: q.topicNodeId,
          difficulty: q.difficulty,
          marks: q.marks,
          negativeMarks: q.negativeMarks,
          language: q.language,
        ),
        onSave: (d) async {
          try {
            await widget.onUpdateServerQuestion(q, d);
            if (mounted) _snack('Question updated');
          } on AppError catch (e) {
            if (mounted) _snack(e.message, error: true);
          }
        },
      );

  Future<void> _deleteServer(Question q) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Question'),
        content: const Text('Are you sure you want to delete this question?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.onDeleteServerQuestion(q);
      if (mounted) _snack('Question deleted');
    } on AppError catch (e) {
      if (mounted) _snack(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <_Item>[
      for (final q in widget.serverQuestions) _Item.server(q),
      for (var i = 0; i < widget.localQuestions.length; i++)
        _Item.local(widget.localQuestions[i], i),
    ];
    final totalCount = items.length;

    return Column(
      children: [
        // ── Header with count ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                'Questions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$totalCount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Guidance banner ──
        if (widget.guidance != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.guidance!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),

        // ── Question list or empty state ──
        Expanded(
          child: items.isEmpty
              ? _buildEmpty(context)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _tile(context, items[index], index),
                ),
        ),

        // ── Add Question button ──
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.busy ? null : _addLocal,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Question'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, _Item item, int index) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: item.isServer
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.secondaryContainer,
          child: Text(
            '${index + 1}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          item.text.isEmpty ? 'Untitled Question' : item.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_typeLabel(item.type)} \u2022 ${item.marks} marks'
          '${item.isServer ? ' \u2022 ${item.server!.status == 'approved' ? 'Approved' : 'Pending'}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          enabled: !widget.busy,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
          onSelected: (value) {
            if (value == 'edit') {
              item.isServer
                  ? _editServer(item.server!)
                  : _editLocal(item.localIndex!);
            } else {
              item.isServer
                  ? _deleteServer(item.server!)
                  : _deleteLocal(item.localIndex!);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.quiz_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No questions yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add Question" below to create your first question.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(QuestionType type) {
    switch (type) {
      case QuestionType.mcqSingle:
        return 'MCQ';
      case QuestionType.mcqMultiple:
        return 'Multi-MCQ';
      case QuestionType.trueFalse:
        return 'True/False';
      case QuestionType.integer:
        return 'Numeric';
      case QuestionType.shortAnswer:
        return 'Short Answer';
      case QuestionType.unknown:
        return 'MCQ';
    }
  }
}

class _Item {
  _Item.server(this.server) : local = null, localIndex = null;
  _Item.local(this.local, this.localIndex) : server = null;

  final Question? server;
  final QuestionDraft? local;
  final int? localIndex;

  bool get isServer => server != null;
  String get text => server?.question ?? local?.questionText ?? '';
  QuestionType get type =>
      server?.questionType ?? local?.questionType ?? QuestionType.mcqSingle;
  int get marks => server?.marks ?? local?.marks ?? 1;
}
