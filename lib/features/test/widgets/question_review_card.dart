import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/answer.dart';
import '../../../core/models/question.dart';

enum ReviewStatus { correct, wrong, answered, unanswered }

class QuestionReviewCard extends StatelessWidget {
  const QuestionReviewCard({
    required this.question,
    required this.answer,
    required this.questionNumber,
    required this.totalQuestions,
    super.key,
  });

  final Question question;
  final Answer? answer;
  final int questionNumber;
  final int totalQuestions;

  ReviewStatus get _status {
    if (answer == null || !(answer!.isAnswered || answer!.selectedOptionId != null)) {
      return ReviewStatus.unanswered;
    }
    return ReviewStatus.answered;
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = answer?.selectedOptionId;
    final status = _status;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, status),
            const SizedBox(height: 12),
            Text(
              question.question,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            if (question.hasOptions)
              ...question.options!.map((opt) => _buildOption(
                    context,
                    option: opt,
                    isSelected: selectedId == opt.id,
                  )),
            if (!question.hasOptions && answer?.textAnswer != null)
              _buildTextAnswer(context),
            if (!question.hasOptions && answer?.textAnswer == null)
              _buildUnanswered(context),
            if (question.explanation != null &&
                question.explanation!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildExplanation(context),
            ],
            if (question.explanation == null ||
                question.explanation!.isEmpty) ...[
              const SizedBox(height: 12),
              _buildNoExplanation(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ReviewStatus status) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case ReviewStatus.correct:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusText = 'Correct';
      case ReviewStatus.wrong:
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        statusText = 'Wrong';
      case ReviewStatus.answered:
        statusColor = AppColors.primaryLight;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Answered';
      case ReviewStatus.unanswered:
        statusColor = AppColors.textSecondaryLight;
        statusIcon = Icons.help_outline;
        statusText = 'Unanswered';
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Q $questionNumber / $totalQuestions',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.primaryLight,
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.success,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _buildDifficultyBadge(context),
      ],
    );
  }

  Widget _buildDifficultyBadge(BuildContext context) {
    Color color;
    String label;

    switch (question.difficulty) {
      case DifficultyLevel.easy:
        color = AppColors.success;
        label = 'Easy';
      case DifficultyLevel.medium:
        color = AppColors.warning;
        label = 'Medium';
      case DifficultyLevel.hard:
        color = AppColors.error;
        label = 'Hard';
      case DifficultyLevel.unknown:
        color = AppColors.textSecondaryLight;
        label = '--';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
            ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required QuestionOption option,
    required bool isSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryLight.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: isSelected ? AppColors.primaryLight : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isSelected
                          ? AppColors.primaryLight
                          : AppColors.textPrimaryLight,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextAnswer(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Your answer: ${answer!.textAnswer}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.primaryLight,
            ),
      ),
    );
  }

  Widget _buildUnanswered(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Not answered',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondaryLight,
              fontStyle: FontStyle.italic,
            ),
      ),
    );
  }

  Widget _buildExplanation(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Text(
                'Explanation',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            question.explanation!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildNoExplanation(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline,
            size: 14, color: AppColors.textSecondaryLight),
        const SizedBox(width: 6),
        Text(
          'Explanation not available',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondaryLight,
                fontStyle: FontStyle.italic,
              ),
        ),
      ],
    );
  }
}
