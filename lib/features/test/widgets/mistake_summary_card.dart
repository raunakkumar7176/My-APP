import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';

class MistakeSummaryCard extends StatelessWidget {
  const MistakeSummaryCard({
    required this.totalMistakes,
    required this.totalUnanswered,
    required this.accuracy,
    required this.mistakesBySubject,
    required this.mistakesByDifficulty,
    this.onReviewMistakes,
    super.key,
  });

  final int totalMistakes;
  final int totalUnanswered;
  final double accuracy;
  final Map<String, int> mistakesBySubject;
  final Map<String, int> mistakesByDifficulty;
  final VoidCallback? onReviewMistakes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Answer Summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (onReviewMistakes != null)
                  TextButton.icon(
                    onPressed: onReviewMistakes,
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Review Unanswered'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statBox(context, 'Wrong', '$totalMistakes', AppColors.error),
                const SizedBox(width: 12),
                _statBox(context, 'Unanswered', '$totalUnanswered',
                    AppColors.textSecondaryLight),
                const SizedBox(width: 12),
                _statBox(
                  context,
                  'Accuracy',
                  '${accuracy.toStringAsFixed(1)}%',
                  AppColors.primaryLight,
                ),
              ],
            ),
            if (mistakesBySubject.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Unanswered by subject:',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
              ),
              const SizedBox(height: 4),
              ...mistakesBySubject.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${e.key}: ${e.value} unanswered',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondaryLight,
                          ),
                    ),
                  )),
            ],
            if (mistakesByDifficulty.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Unanswered by difficulty:',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
              ),
              const SizedBox(height: 4),
              ...mistakesByDifficulty.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${e.key}: ${e.value} unanswered',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondaryLight,
                          ),
                    ),
                  )),
            ],
            if (totalMistakes == 0 && totalUnanswered == 0)
              Text(
                'No unanswered questions.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(
      BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondaryLight,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
