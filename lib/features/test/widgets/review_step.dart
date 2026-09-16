import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/question.dart';
import '../domain/publish_readiness.dart';
import '../domain/test_kind.dart';
import '../models/question_draft.dart';
import 'test_formatters.dart';

/// Review step (R4 restart): renders the shared [PublishReadiness] result
/// and lets the creator approve server questions via controller callbacks.
class ReviewStep extends StatelessWidget {
  const ReviewStep({
    required this.title,
    required this.kind,
    required this.durationSec,
    required this.marksPerQuestion,
    required this.negativeMarks,
    required this.startsAt,
    required this.endsAt,
    required this.readiness,
    required this.serverQuestions,
    required this.localQuestions,
    required this.syllabusCount,
    required this.onApprove,
    required this.onApproveAll,
    this.busy = false,
    super.key,
  });

  final String title;
  final TestKind kind;
  final int? durationSec;
  final double? marksPerQuestion;
  final double? negativeMarks;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<ReadinessItem> readiness;
  final List<Question> serverQuestions;
  final List<QuestionDraft> localQuestions;
  final int syllabusCount;

  /// Throw an [AppError] to show its message.
  final Future<void> Function(String questionId) onApprove;

  /// Returns the number of failures.
  final Future<int> Function() onApproveAll;
  final bool busy;

  int get _pending =>
      serverQuestions.where((q) => q.status != PublishReadiness.approvedStatus).length;

  @override
  Widget build(BuildContext context) {
    final ready = readiness.where((i) => i.isValid).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review Test',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _card(context, 'Summary', [
            _row(context, 'Title', title.isEmpty ? '--' : title),
            _row(context, 'Test Type', kind.label),
            _row(context, 'Duration', TestFormatters.duration(durationSec)),
            _row(context, 'Marks per question', marksPerQuestion?.toString() ?? '--'),
            _row(context, 'Negative marks', negativeMarks?.toString() ?? 'None'),
            if (startsAt != null) _row(context, 'Starts', TestFormatters.dateTime(startsAt)),
            if (endsAt != null) _row(context, 'Ends', TestFormatters.dateTime(endsAt)),
            _row(context, 'Questions', '${serverQuestions.length + localQuestions.length}'),
            _row(context, 'Syllabus nodes', '$syllabusCount'),
          ]),
          _card(context, 'Publish readiness ($ready / ${readiness.length})', [
            for (final item in readiness)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.isValid ? Icons.check_circle : Icons.error_outline,
                      size: 18,
                      color: item.isValid ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.label),
                          if (!item.isValid && item.reason != null)
                            Text(item.reason!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ]),
          if (serverQuestions.isNotEmpty)
            _card(
              context,
              'Approval status',
              [
                for (final q in serverQuestions) _approvalTile(context, q),
              ],
              trailing: _pending > 0
                  ? TextButton.icon(
                      onPressed: busy ? null : () => _approveAll(context),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve All'),
                    )
                  : null,
            ),
          if (localQuestions.isNotEmpty)
            _card(context, 'New questions (approved on publish)', [
              for (final d in localQuestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        d.isValid ? Icons.check_circle : Icons.error_outline,
                        size: 18,
                        color: d.isValid ? AppColors.success : AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(d.questionText,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context, String id) async {
    try {
      await onApprove(id);
      if (context.mounted) _snack(context, 'Question approved');
    } on AppError catch (e) {
      if (context.mounted) _snack(context, e.message, error: true);
    }
  }

  Future<void> _approveAll(BuildContext context) async {
    final failed = await onApproveAll();
    if (!context.mounted) return;
    _snack(context, failed == 0 ? 'All questions approved' : '$failed approval(s) failed',
        error: failed > 0);
  }

  void _snack(BuildContext context, String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? AppColors.error : AppColors.success,
    ));
  }

  Widget _approvalTile(BuildContext context, Question q) {
    final approved = q.status == PublishReadiness.approvedStatus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(approved ? Icons.check_circle : Icons.pending,
              size: 18, color: approved ? AppColors.success : Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Q${q.ordinal ?? '?'}: ${q.question}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(approved ? 'Approved' : 'Pending Review',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: approved ? AppColors.success : Colors.orange,
                          fontWeight: FontWeight.w500,
                        )),
              ],
            ),
          ),
          if (!approved)
            TextButton(
              onPressed: busy ? null : () => _approve(context, q.id),
              child: const Text('Approve'),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, String title, List<Widget> children,
      {Widget? trailing}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
