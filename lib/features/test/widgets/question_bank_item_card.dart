import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/question_bank_item.dart';

/// Card widget for displaying a single question bank item.
class QuestionBankItemCard extends StatelessWidget {
  const QuestionBankItemCard({
    required this.item,
    this.isSelected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final QuestionBankItem item;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'pending_review':
        return AppColors.warning;
      case 'archived':
        return AppColors.textSecondaryLight;
      case 'needs_revision':
        return AppColors.error;
      default:
        return AppColors.textSecondaryLight;
    }
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return AppColors.success;
      case 'medium':
        return AppColors.warning;
      case 'hard':
        return AppColors.error;
      default:
        return AppColors.textSecondaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: Key('bank_item_${item.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: status + selection checkbox
              Row(
                children: [
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        size: 20,
                      ),
                    ),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(item.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.status.replaceAll('_', ' '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _statusColor(item.status),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Difficulty chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _difficultyColor(item.difficulty)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.difficulty,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _difficultyColor(item.difficulty),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Times used
                  if (item.timesUsed > 0)
                    Text(
                      'Used ${item.timesUsed}x',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Question text
              Text(
                item.question,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),

              // Metadata row
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (item.subjectName.isNotEmpty)
                    _MetaChip(
                      icon: Icons.subject,
                      label: item.subjectName,
                    ),
                  if (item.chapter.isNotEmpty)
                    _MetaChip(
                      icon: Icons.book_outlined,
                      label: item.chapter,
                    ),
                  _MetaChip(
                    icon: Icons.language,
                    label: item.language.toUpperCase(),
                  ),
                  _MetaChip(
                    icon: Icons.quiz,
                    label: item.questionType.toUpperCase(),
                  ),
                ],
              ),

              // Options preview
              if (item.options.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${item.options.length} options',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small metadata chip with icon and label.
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: AppColors.textSecondaryLight,
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}
