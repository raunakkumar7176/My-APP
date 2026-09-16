import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/result_analytics.dart';

class DifficultyAnalysisExtendedCard extends StatelessWidget {
  const DifficultyAnalysisExtendedCard({required this.items, super.key});

  final List<DifficultyBreakdownItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

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
            ...items.map((item) => _buildRow(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, DifficultyBreakdownItem item) {
    Color color;
    String label;

    switch (item.difficulty) {
      case 'easy':
        color = AppColors.success;
        label = 'Easy';
      case 'medium':
        color = AppColors.warning;
        label = 'Medium';
      case 'hard':
        color = AppColors.error;
        label = 'Hard';
      default:
        color = AppColors.textSecondaryLight;
        label = item.difficulty;
    }

    final accuracy = item.accuracy;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
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
                  '${item.correct}/${item.attempted} correct',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondaryLight,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${accuracy.toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            if (item.wrong > 0 || item.unanswered > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (item.wrong > 0)
                    Text(
                      '${item.wrong} wrong',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.error,
                          ),
                    ),
                  if (item.wrong > 0 && item.unanswered > 0)
                    Text(' · ',
                        style: Theme.of(context).textTheme.labelSmall),
                  if (item.unanswered > 0)
                    Text(
                      '${item.unanswered} skipped',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondaryLight,
                          ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
