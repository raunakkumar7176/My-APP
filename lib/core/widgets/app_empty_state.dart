import 'package:flutter/material.dart';

import '../theme/app_icon_size.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';

/// Central design system Empty State component for "My Preparation".
///
/// Standardizes zero-data views, search misses, and initial empty screens.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: AppSpacing.paddingXl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: AppSpacing.paddingLg,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: AppIconSize.empty,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            AppSpacing.vGapMd,
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              AppSpacing.vGapXs,
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              AppSpacing.vGapLg,
              action!,
            ] else if (actionLabel != null && onAction != null) ...[
              AppSpacing.vGapLg,
              AppButton.primary(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
