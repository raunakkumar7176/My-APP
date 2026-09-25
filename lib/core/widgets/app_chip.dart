import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/app_icon_size.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Central design system Chip component for "My Preparation".
///
/// Use for filters, tag selections, subject chips, and selectable categories.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool isSelected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color bgColor = isSelected
        ? colorScheme.primary
        : colorScheme.surface;
    final Color fgColor = isSelected
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    final Border? border = isSelected
        ? null
        : Border.all(
            color: colorScheme.outlineVariant,
            width: AppDimensions.borderWidth,
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.smBorder,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6.0,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: AppRadius.smBorder,
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIconSize.inline, color: fgColor),
                AppSpacing.hGapXs,
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fgColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
