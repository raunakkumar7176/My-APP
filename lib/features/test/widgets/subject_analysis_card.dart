import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/result_analytics.dart';

class SubjectAnalysisCard extends StatelessWidget {
  const SubjectAnalysisCard({required this.items, super.key});

  final List<SubjectBreakdownItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subject Analysis',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'Subject-wise data is not available for this test.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondaryLight),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subject Analysis',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...items.map((item) => _buildSubjectRow(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectRow(BuildContext context, SubjectBreakdownItem item) {
    final accuracy = item.accuracy;
    Color accuracyColor;
    if (accuracy >= 70) {
      accuracyColor = AppColors.success;
    } else if (accuracy >= 40) {
      accuracyColor = AppColors.warning;
    } else {
      accuracyColor = AppColors.error;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.subjectName,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${accuracy.toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: accuracyColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _miniStat(
                  context,
                  'Attempted',
                  '${item.attempted}',
                  AppColors.primaryLight,
                ),
                const SizedBox(width: 12),
                _miniStat(
                  context,
                  'Correct',
                  '${item.correct}',
                  AppColors.success,
                ),
                const SizedBox(width: 12),
                _miniStat(context, 'Wrong', '${item.wrong}', AppColors.error),
                const SizedBox(width: 12),
                _miniStat(
                  context,
                  'Skipped',
                  '${item.unanswered}',
                  AppColors.textSecondaryLight,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: item.total > 0 ? item.correct / item.total : 0,
                minHeight: 5,
                backgroundColor: AppColors.success.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(AppColors.success),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AppColors.textSecondaryLight, fontSize: 10),
        ),
      ],
    );
  }
}
