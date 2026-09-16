import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/question.dart';
import '../../../core/services/question_service.dart';
import '../models/question_draft.dart';
import 'question_editor.dart';

class StepQuestions extends StatefulWidget {
  const StepQuestions({
    required this.questions,
    required this.serverQuestions,
    required this.onQuestionsChanged,
    required this.onServerQuestionDeleted,
    required this.onServerQuestionUpdated,
    required this.onNewQuestionFromServer,
    this.guidance,
    super.key,
  });

  final List<QuestionDraft> questions;
  final List<Question> serverQuestions;
  final ValueChanged<List<QuestionDraft>> onQuestionsChanged;
  final ValueChanged<String> onServerQuestionDeleted;
  final ValueChanged<Question> onServerQuestionUpdated;
  final ValueChanged<Question> onNewQuestionFromServer;

  /// Optional non-blocking hint shown above the list (e.g. Quick Test
  /// question-count guidance). Purely informational — nothing enforces it.
  final String? guidance;

  @override
  State<StepQuestions> createState() => _StepQuestionsState();
}

class _StepQuestionsState extends State<StepQuestions> {
  bool _isProcessing = false;

  // ─── LOCAL DRAFT OPERATIONS ────────────────────────────────

  void _addQuestion() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: QuestionEditor(
          onSave: (question) {
            widget.onQuestionsChanged([...widget.questions, question]);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _editLocalQuestion(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: QuestionEditor(
          initial: widget.questions[index],
          onSave: (question) {
            final updated = List<QuestionDraft>.from(widget.questions);
            updated[index] = question;
            widget.onQuestionsChanged(updated);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _deleteLocalQuestion(int index) {
    final updated = List<QuestionDraft>.from(widget.questions);
    updated.removeAt(index);
    widget.onQuestionsChanged(updated);
  }

  // ─── SERVER QUESTION OPERATIONS ────────────────────────────

  Future<void> _deleteServerQuestion(Question question) async {
    if (_isProcessing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Question'),
        content: const Text('Are you sure you want to delete this question?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      await QuestionService.deleteQuestion(question.id);
      widget.onServerQuestionDeleted(question.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Question deleted'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on AppError catch (e) {
      AppLogger.error('Delete server question AppError: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Delete server question unexpected error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete question. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _editServerQuestion(Question question) async {
    if (_isProcessing) return;

    // Convert server question to draft for editing
    final draft = QuestionDraft(
      id: question.id,
      questionText: question.question,
      questionType: question.questionType ?? QuestionType.mcqSingle,
      options: question.options
          ?.map((o) => QuestionOptionDraft(id: o.id, text: o.text))
          .toList() ?? [],
      correctOptionIndex: null, // Server doesn't expose this
      explanation: question.explanation,
      subjectId: question.subjectId,
      topicNodeId: question.topicNodeId,
      difficulty: question.difficulty,
      marks: question.marks,
      negativeMarks: question.negativeMarks,
      language: question.language,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: QuestionEditor(
          initial: draft,
          onSave: (updatedDraft) async {
            Navigator.of(context).pop();
            await _saveServerQuestionEdit(question, updatedDraft);
          },
        ),
      ),
    );
  }

  Future<void> _saveServerQuestionEdit(
    Question original,
    QuestionDraft updated,
  ) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      await QuestionService.updateQuestion(
        questionId: original.id,
        questionText: updated.questionText,
        questionType: updated.questionType,
        options: updated.options
            .map((o) => {'id': o.id ?? '', 'text': o.text})
            .toList(),
        // The client never receives the stored answer key, so the editor
        // starts with no selection. Send it only when the user picked one;
        // null is omitted by the service and leaves the server value as-is.
        correctOption: updated.correctOptionIndex,
        explanation: updated.explanation,
        subjectId: updated.subjectId,
        topicNodeId: updated.topicNodeId,
        difficulty: updated.difficulty.name,
        marks: updated.marks,
        negativeMarks: updated.negativeMarks,
        language: updated.language,
      );

      final updatedQuestion = Question(
        id: original.id,
        testId: original.testId,
        ordinal: original.ordinal,
        question: updated.questionText,
        options: updated.options
            .map((o) => QuestionOption(id: o.id ?? '', text: o.text))
            .toList(),
        explanation: updated.explanation,
        subjectId: updated.subjectId,
        topicNodeId: updated.topicNodeId,
        difficulty: updated.difficulty,
        marks: updated.marks,
        negativeMarks: updated.negativeMarks,
        status: original.status,
        language: updated.language,
        questionType: updated.questionType,
      );

      widget.onServerQuestionUpdated(updatedQuestion);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Question updated'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on AppError catch (e) {
      AppLogger.error('Update server question AppError: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Update server question unexpected error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update question. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasQuestions =
        widget.questions.isNotEmpty || widget.serverQuestions.isNotEmpty;

    return Column(
      children: [
        if (widget.guidance != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.guidance!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: hasQuestions
              ? _buildQuestionList(context)
              : _buildEmpty(context),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _addQuestion,
              icon: const Icon(Icons.add),
              label: const Text('Add Question'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.question_answer_outlined,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No questions yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add Question" to create your first question.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionList(BuildContext context) {
    final allItems = <_QuestionListItem>[];

    // Add server questions
    for (final q in widget.serverQuestions) {
      allItems.add(_QuestionListItem.server(q));
    }

    // Add local draft questions
    for (var i = 0; i < widget.questions.length; i++) {
      allItems.add(_QuestionListItem.draft(widget.questions[i], index: i));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: item.isServer
                  ? AppColors.primaryLight.withValues(alpha: 0.1)
                  : Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.5),
              child: Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            title: Text(
              item.questionText.isEmpty ? 'Untitled Question' : item.questionText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_questionTypeLabel(item.questionType)} • ${item.marks} marks',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
            trailing: PopupMenuButton<String>(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
              onSelected: (value) {
                if (value == 'edit') {
                  if (item.isServer) {
                    _editServerQuestion(item.serverQuestion!);
                  } else {
                    _editLocalQuestion(item.localIndex!);
                  }
                } else if (value == 'delete') {
                  if (item.isServer) {
                    _deleteServerQuestion(item.serverQuestion!);
                  } else {
                    _deleteLocalQuestion(item.localIndex!);
                  }
                }
              },
            ),
          ),
        );
      },
    );
  }

  String _questionTypeLabel(QuestionType type) {
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

class _QuestionListItem {
  final Question? serverQuestion;
  final QuestionDraft? draftQuestion;
  final int? localIndex;

  _QuestionListItem.server(this.serverQuestion)
      : draftQuestion = null,
        localIndex = null;

  _QuestionListItem.draft(this.draftQuestion, {required int index})
      : serverQuestion = null,
        localIndex = index;

  bool get isServer => serverQuestion != null;

  String get questionText =>
      serverQuestion?.question ?? draftQuestion?.questionText ?? '';

  QuestionType get questionType =>
      serverQuestion?.questionType ?? draftQuestion?.questionType ?? QuestionType.mcqSingle;

  int get marks =>
      serverQuestion?.marks ?? draftQuestion?.marks ?? 1;
}
