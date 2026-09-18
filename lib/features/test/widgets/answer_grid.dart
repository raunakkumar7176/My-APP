import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/answer.dart';

enum AnswerStatus { answered, unanswered, markedReview, markedAndAnswered }

class AnswerGrid extends StatelessWidget {
  const AnswerGrid({
    required this.questionIds,
    required this.answers,
    required this.currentQuestionIndex,
    required this.onQuestionTap,
    super.key,
  });

  final List<String> questionIds;
  final Map<String, Answer> answers;
  final int currentQuestionIndex;
  final ValueChanged<int> onQuestionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Questions',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildLegend(context),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: questionIds.length,
            itemBuilder: (context, index) => _buildCell(context, index),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _legendItem(context, 'Answered', AppColors.success),
        _legendItem(context, 'Unanswered', AppColors.textSecondaryLight),
        _legendItem(context, 'Marked', AppColors.warning),
      ],
    );
  }

  Widget _legendItem(BuildContext context, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  Widget _buildCell(BuildContext context, int index) {
    final isCurrent = index == currentQuestionIndex;
    final questionId = questionIds[index];
    final answer = answers[questionId];
    final status = _getStatus(answer);

    Color bgColor;
    Color fgColor;
    switch (status) {
      case AnswerStatus.answered:
        bgColor = AppColors.success;
        fgColor = Colors.white;
      case AnswerStatus.unanswered:
        bgColor = Colors.grey.shade200;
        fgColor = AppColors.textPrimaryLight;
      case AnswerStatus.markedReview:
        bgColor = AppColors.warning;
        fgColor = Colors.white;
      case AnswerStatus.markedAndAnswered:
        bgColor = AppColors.primaryLight;
        fgColor = Colors.white;
    }

    return GestureDetector(
      onTap: () => onQuestionTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: isCurrent
              ? Border.all(color: AppColors.primaryLight, width: 3)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '${index + 1}',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: fgColor, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  AnswerStatus _getStatus(Answer? answer) {
    if (answer == null) return AnswerStatus.unanswered;
    final isAnswered = answer.isAnswered;
    final isMarked = answer.markedForReview;
    if (isMarked && isAnswered) return AnswerStatus.markedAndAnswered;
    if (isMarked) return AnswerStatus.markedReview;
    if (isAnswered) return AnswerStatus.answered;
    return AnswerStatus.unanswered;
  }
}
