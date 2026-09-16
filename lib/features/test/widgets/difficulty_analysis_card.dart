import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/answer.dart';
import '../../../core/models/question.dart';

class DifficultyAnalysisCard extends StatelessWidget {
  const DifficultyAnalysisCard({
    required this.questions,
    required this.answers,
    super.key,
  });

  final List<Question> questions;
  final Map<String, Answer> answers;

  @override
  Widget build(BuildContext context) {
    final easy = _categorize(DifficultyLevel.easy);
    final medium = _categorize(DifficultyLevel.medium);
    final hard = _categorize(DifficultyLevel.hard);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Difficulty Analysis',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            if (easy.$1.isNotEmpty || medium.$1.isNotEmpty || hard.$1.isNotEmpty)
              _buildDifficultyRow(
                context,
                level: DifficultyLevel.easy,
                label: 'Easy',
                color: AppColors.success,
                answered: easy.$2,
                total: easy.$1.length,
                marks: easy.$3,
                maxMarks: easy.$4,
              ),
            if (easy.$1.isNotEmpty || medium.$1.isNotEmpty)
              const SizedBox(height: 8),
            if (medium.$1.isNotEmpty || hard.$1.isNotEmpty)
              _buildDifficultyRow(
                context,
                level: DifficultyLevel.medium,
                label: 'Medium',
                color: AppColors.warning,
                answered: medium.$2,
                total: medium.$1.length,
                marks: medium.$3,
                maxMarks: medium.$4,
              ),
            if (medium.$1.isNotEmpty && hard.$1.isNotEmpty)
              const SizedBox(height: 8),
            if (hard.$1.isNotEmpty)
              _buildDifficultyRow(
                context,
                level: DifficultyLevel.hard,
                label: 'Hard',
                color: AppColors.error,
                answered: hard.$2,
                total: hard.$1.length,
                marks: hard.$3,
                maxMarks: hard.$4,
              ),
          ],
        ),
      ),
    );
  }

  (List<Question>, int, int, int) _categorize(DifficultyLevel level) {
    final qs = questions.where((q) => q.difficulty == level).toList();
    int answered = 0;
    int marks = 0;
    int maxMarks = 0;
    for (final q in qs) {
      maxMarks += q.marks;
      final answer = answers[q.id];
      if (answer != null &&
          (answer.isAnswered || answer.selectedOptionId != null)) {
        answered++;
        marks += q.marks;
      }
    }
    return (qs, answered, marks, maxMarks);
  }

  Widget _buildDifficultyRow(
    BuildContext context, {
    required DifficultyLevel level,
    required String label,
    required Color color,
    required int answered,
    required int total,
    required int marks,
    required int maxMarks,
  }) {
    final percentage = total > 0 ? (answered / total) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Text(
                '$answered / $total answered',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? answered / total : 0,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$marks / $maxMarks marks',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
              ),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
