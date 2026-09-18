import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/result_analytics.dart';

class TopicAnalysisCard extends StatelessWidget {
  const TopicAnalysisCard({required this.items, super.key});

  final List<TopicBreakdownItem> items;

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
                'Topic Analysis',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'Topic analysis is not available for this test.',
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
              'Topic Analysis',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...items.map((item) => _buildTopicRow(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicRow(BuildContext context, TopicBreakdownItem item) {
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              item.topicName,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${item.correct}/${item.attempted} correct',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondaryLight),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${accuracy.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: accuracyColor, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
