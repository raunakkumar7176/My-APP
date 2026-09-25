import 'package:flutter/material.dart';

import '../theme/app_icon_size.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Semantic status variants for [AppBadge].
enum AppBadgeVariant {
  live,
  upcoming,
  completed,
  draft,
  pass,
  fail,
  warning,
  info,
  neutral,
}

/// Central design system Badge component for "My Preparation".
///
/// Ensures single-line status indicators with proper contrast in both Light and Dark mode.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.variant = AppBadgeVariant.neutral,
    this.icon,
    this.usePillShape = false,
  }) : customBgColor = null,
       customFgColor = null;

  /// Custom badge with explicitly provided colors.
  const AppBadge.custom({
    super.key,
    required this.label,
    required Color backgroundColor,
    required Color foregroundColor,
    this.icon,
    this.usePillShape = false,
  }) : variant = AppBadgeVariant.neutral,
       customBgColor = backgroundColor,
       customFgColor = foregroundColor;

  /// Convenience constructor for LIVE test indicator.
  const AppBadge.live({
    super.key,
    this.label = 'LIVE',
    this.icon = Icons.fiber_manual_record,
    this.usePillShape = false,
  }) : variant = AppBadgeVariant.live,
       customBgColor = null,
       customFgColor = null;

  /// Convenience constructor for UPCOMING test indicator.
  const AppBadge.upcoming({
    super.key,
    this.label = 'UPCOMING',
    this.icon,
    this.usePillShape = false,
  }) : variant = AppBadgeVariant.upcoming,
       customBgColor = null,
       customFgColor = null;

  /// Convenience constructor for COMPLETED status.
  const AppBadge.completed({
    super.key,
    this.label = 'COMPLETED',
    this.icon = Icons.check,
    this.usePillShape = false,
  }) : variant = AppBadgeVariant.completed,
       customBgColor = null,
       customFgColor = null;

  /// Convenience constructor for DRAFT status.
  const AppBadge.draft({
    super.key,
    this.label = 'DRAFT',
    this.icon,
    this.usePillShape = false,
  }) : variant = AppBadgeVariant.draft,
       customBgColor = null,
       customFgColor = null;

  /// Convenience constructor for PASS / SUCCESS result.
  const AppBadge.pass({
    super.key,
    this.label = 'PASS',
    this.icon,
    this.usePillShape = false,
  }) : variant = AppBadgeVariant.pass,
       customBgColor = null,
       customFgColor = null;

  /// Convenience constructor for FAIL / NEEDS ATTENTION result.
  const AppBadge.fail({
    super.key,
    this.label = 'FAIL',
    this.icon,
    this.usePillShape = false,
  }) : variant = AppBadgeVariant.fail,
       customBgColor = null,
       customFgColor = null;

  final String label;
  final AppBadgeVariant variant;
  final IconData? icon;
  final bool usePillShape;
  final Color? customBgColor;
  final Color? customFgColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color bgColor;
    final Color fgColor;

    if (customBgColor != null && customFgColor != null) {
      bgColor = customBgColor!;
      fgColor = customFgColor!;
    } else {
      switch (variant) {
        case AppBadgeVariant.live:
          bgColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
          fgColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);
          break;

        case AppBadgeVariant.upcoming:
          bgColor = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE);
          fgColor = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
          break;

        case AppBadgeVariant.completed:
        case AppBadgeVariant.pass:
          bgColor = isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7);
          fgColor = isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D);
          break;

        case AppBadgeVariant.draft:
          bgColor = colorScheme.surfaceContainerHighest;
          fgColor = colorScheme.onSurfaceVariant;
          break;

        case AppBadgeVariant.fail:
          bgColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
          fgColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
          break;

        case AppBadgeVariant.warning:
          bgColor = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
          fgColor = isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309);
          break;

        case AppBadgeVariant.info:
          bgColor = colorScheme.primaryContainer;
          fgColor = colorScheme.onPrimaryContainer;
          break;

        case AppBadgeVariant.neutral:
          bgColor = colorScheme.surfaceContainerHigh;
          fgColor = colorScheme.onSurface;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3.0,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: usePillShape ? AppRadius.pillBorder : AppRadius.smBorder,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSize.inline - 4, color: fgColor),
            AppSpacing.hGapXs,
          ],
          Flexible(
            child: Text(
              label,
              style: AppTypography.badgeText.copyWith(color: fgColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
