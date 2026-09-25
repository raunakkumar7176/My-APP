import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Supported visual variants for [AppCard].
enum AppCardVariant {
  /// Subtle shadow elevation with clean surface.
  elevated,

  /// Clean surface with 1px outline border (default).
  outlined,

  /// Flat subtle surface container without prominent border.
  filled,

  /// Primary or accent tinted card for highlighted / hero information.
  highlight,
}

/// Central design system Card component for "My Preparation".
///
/// Ensures consistent borders, radius, padding, elevation and theme-awareness
/// across all features.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.variant = AppCardVariant.outlined,
    this.padding = AppSpacing.cardPadding,
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
    this.onTap,
  });

  /// Factory for a compact card with smaller padding ([AppSpacing.cardPaddingCompact]).
  const AppCard.compact({
    super.key,
    required this.child,
    this.variant = AppCardVariant.outlined,
    this.padding = AppSpacing.cardPaddingCompact,
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
    this.onTap,
  });

  final Widget child;
  final AppCardVariant variant;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveRadius = borderRadius ?? AppRadius.lgBorder;

    final Color effectiveBg;
    final Border? effectiveBorder;
    final List<BoxShadow>? effectiveShadow;

    switch (variant) {
      case AppCardVariant.elevated:
        effectiveBg = backgroundColor ?? colorScheme.surface;
        effectiveBorder = Border.all(
          color:
              borderColor ?? colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: AppDimensions.borderWidth,
        );
        effectiveShadow = [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.3 : 0.05,
            ),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ];
        break;

      case AppCardVariant.outlined:
        effectiveBg = backgroundColor ?? colorScheme.surface;
        effectiveBorder = Border.all(
          color: borderColor ?? colorScheme.outlineVariant,
          width: AppDimensions.borderWidth,
        );
        effectiveShadow = null;
        break;

      case AppCardVariant.filled:
        effectiveBg = backgroundColor ?? colorScheme.surfaceContainer;
        effectiveBorder = null;
        effectiveShadow = null;
        break;

      case AppCardVariant.highlight:
        effectiveBg =
            backgroundColor ??
            colorScheme.primaryContainer.withValues(alpha: 0.6);
        effectiveBorder = Border.all(
          color: borderColor ?? colorScheme.primary.withValues(alpha: 0.3),
          width: AppDimensions.borderWidth,
        );
        effectiveShadow = null;
        break;
    }

    Widget content = Padding(padding: padding, child: child);

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: effectiveRadius,
          onTap: onTap,
          child: content,
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: effectiveRadius,
        border: effectiveBorder,
        boxShadow: effectiveShadow,
      ),
      child: content,
    );
  }
}
