import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/answer.dart';
import '../../../core/models/question.dart';

class QuestionCard extends StatelessWidget {
  const QuestionCard({
    required this.question,
    required this.shuffledOptions,
    required this.answer,
    required this.questionNumber,
    required this.totalQuestions,
    required this.onOptionSelected,
    required this.onMarkReview,
    this.interactive = true,
    this.showProgressHeader = true,
    this.kindLabel,
    super.key,
  });

  final Question question;
  final List<QuestionOption> shuffledOptions;
  final Answer? answer;
  final int questionNumber;
  final int totalQuestions;
  final bool showProgressHeader;
  final String? kindLabel;

  /// Called with the option's index in the server's `options` array
  /// (`QuestionOption.index`), which is what the backend stores and scores.
  final ValueChanged<int?> onOptionSelected;
  final VoidCallback onMarkReview;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = answer?.selectedOption;
    final isMarked = answer?.markedForReview ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, isMarked),
          const SizedBox(height: 16),
          _buildQuestionText(context),
          const SizedBox(height: 20),
          if (question.hasOptions)
            ...shuffledOptions.map(
              (opt) => _buildOptionTile(
                context,
                option: opt,
                isSelected: selectedIndex == opt.index,
              ),
            ),
          if (!question.hasOptions) _buildUnsupported(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isMarked) {
    final theme = Theme.of(context);
    if (!showProgressHeader) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '+${question.marks} mark${question.marks != 1 ? 's' : ''}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if ((question.negativeMarks ?? 0) > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '-${question.negativeMarks}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (kindLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                kindLabel!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              question.difficulty.name.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Q $questionNumber / $totalQuestions',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${question.marks} mark${question.marks != 1 ? 's' : ''}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.success,
            ),
          ),
        ),
        const Spacer(),
        if (interactive)
          IconButton(
            icon: Icon(
              isMarked ? Icons.bookmark : Icons.bookmark_border,
              color: isMarked
                  ? AppColors.warning
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            onPressed: onMarkReview,
            tooltip: 'Mark for review',
          ),
        if (!interactive && isMarked)
          const Icon(Icons.bookmark, color: AppColors.warning, size: 24),
      ],
    );
  }

  Widget _buildQuestionText(BuildContext context) {
    return Text(
      question.question,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
    );
  }

  Widget _buildOptionTile(
    BuildContext context, {
    required QuestionOption option,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: interactive ? () => onOptionSelected(option.index) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _buildRadioIndicator(context, isSelected),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    option.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadioIndicator(BuildContext context, bool isSelected) {
    final theme = Theme.of(context);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: 2,
        ),
        color: isSelected ? theme.colorScheme.primary : Colors.transparent,
      ),
      child: isSelected
          ? Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimary)
          : null,
    );
  }

  /// BACKEND GAP (verified live 2026-09-16): `answers` has no text column and
  /// `rpc_save_answers` only accepts an option index, so typed-answer
  /// questions cannot be answered or scored yet. Say so instead of faking it.
  Widget _buildUnsupported(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
        color: AppColors.warning.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Typed answers are not supported on this backend yet. '
              'This question cannot be answered or scored.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
