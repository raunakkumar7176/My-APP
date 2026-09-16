import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/result.dart';

class ResultHistoryCard extends StatelessWidget {
  const ResultHistoryCard({
    required this.results,
    required this.currentResultId,
    super.key,
  });

  final List<Result> results;
  final String currentResultId;

  @override
  Widget build(BuildContext context) {
    if (results.length <= 1) {
      return const SizedBox.shrink();
    }

    final sorted = List<Result>.from(results)
      ..sort((a, b) =>
          (b.computedAt ?? DateTime(0)).compareTo(a.computedAt ?? DateTime(0)));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Result History',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${sorted.length} attempts for this test',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryLight,
                  ),
            ),
            const SizedBox(height: 12),
            ...sorted.asMap().entries.map((entry) {
              final index = entry.key;
              final result = entry.value;
              final isCurrent = result.id == currentResultId;
              return _buildHistoryRow(context, result, index, isCurrent);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryRow(
      BuildContext context, Result result, int index, bool isCurrent) {
    final percentage = result.percentage ?? 0;
    final isPassed = result.isPassed ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primaryLight.withValues(alpha: 0.08)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: isCurrent
            ? Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (isPassed ? AppColors.success : AppColors.error)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isPassed ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attempt ${index + 1}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                if (result.computedAt != null)
                  Text(
                    _formatDate(result.computedAt!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondaryLight,
                        ),
                  ),
              ],
            ),
          ),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isPassed ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Current',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
