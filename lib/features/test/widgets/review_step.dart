import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/question.dart';
import '../domain/publish_readiness.dart';
import '../domain/test_kind.dart';
import '../models/question_draft.dart';
import 'section_card.dart';
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
    this.extraRows = const [],
    super.key,
  });

  /// Additional summary rows (label, value) from the creation controller.
  final List<(String, String)> extraRows;

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

  int get _pending => serverQuestions
      .where((q) => q.status != PublishReadiness.approvedStatus)
      .length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ready = readiness.where((i) => i.isValid).length;
    final allReady = ready == readiness.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review Test',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Review your test configuration before publishing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // ── Summary Card ──
          SectionCard(
            title: 'Test Summary',
            children: [
              _SummaryRow(label: 'Title', value: title.isEmpty ? '--' : title),
              _SummaryRow(label: 'Type', value: kind.label),
              _SummaryRow(
                label: 'Duration',
                value: TestFormatters.duration(durationSec),
              ),
              _SummaryRow(
                label: 'Marks per question',
                value: marksPerQuestion?.toString() ?? '--',
              ),
              _SummaryRow(
                label: 'Negative marks',
                value: negativeMarks?.toString() ?? 'None',
              ),
              _SummaryRow(
                label: 'Questions',
                value: '${serverQuestions.length + localQuestions.length}',
              ),
              _SummaryRow(
                label: 'Syllabus topics',
                value: '$syllabusCount',
              ),
              if (startsAt != null)
                _SummaryRow(
                  label: 'Starts',
                  value: TestFormatters.dateTime(startsAt),
                ),
              if (endsAt != null)
                _SummaryRow(
                  label: 'Ends (calculated)',
                  value: TestFormatters.dateTime(endsAt),
                ),
              for (final (label, value) in extraRows)
                _SummaryRow(label: label, value: value),
            ],
          ),

          // ── Readiness Card ──
          SectionCard(
            title: 'Publish Readiness',
            subtitle: '$ready / ${readiness.length} checks passed',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: allReady
                    ? colorScheme.primaryContainer
                    : colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                allReady ? 'Ready' : 'Not Ready',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: allReady
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            children: [
              for (final item in readiness)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.isValid
                            ? Icons.check_circle
                            : Icons.error_outline,
                        size: 18,
                        color: item.isValid
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (!item.isValid && item.reason != null)
                              Text(
                                item.reason!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // ── Approval Status (server questions) ──
          if (serverQuestions.isNotEmpty)
            SectionCard(
              title: 'Approval Status',
              subtitle: '$_pending question${_pending == 1 ? '' : 's'} pending',
              trailing: _pending > 0
                  ? TextButton.icon(
                      onPressed: busy ? null : () => _approveAll(context),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Approve All'),
                    )
                  : null,
              children: [
                for (final q in serverQuestions) _approvalTile(context, q),
              ],
            ),

          // ── Local Questions ──
          if (localQuestions.isNotEmpty)
            SectionCard(
              title: 'New Questions',
              subtitle: 'Approved automatically on publish',
              children: [
                for (final d in localQuestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          d.isValid
                              ? Icons.check_circle
                              : Icons.error_outline,
                          size: 18,
                          color: d.isValid
                              ? AppColors.success
                              : AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            d.questionText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
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
    _snack(
      context,
      failed == 0 ? 'All questions approved' : '$failed approval(s) failed',
      error: failed > 0,
    );
  }

  void _snack(BuildContext context, String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Widget _approvalTile(BuildContext context, Question q) {
    final approved = q.status == PublishReadiness.approvedStatus;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            approved ? Icons.check_circle : Icons.pending,
            size: 18,
            color: approved ? AppColors.success : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q${q.ordinal ?? '?'}: ${q.question}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  approved ? 'Approved' : 'Pending Review',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: approved ? AppColors.success : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
