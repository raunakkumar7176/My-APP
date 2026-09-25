import 'package:flutter/material.dart';

import '../theme/app_dimensions.dart';
import '../theme/app_icon_size.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Button visual hierarchy variants.
enum AppButtonVariant {
  primary,
  secondary,
  outlined,
  text,
  destructive,
  onColor,
}

/// Button size presets.
enum AppButtonSize { sm, md, lg }

/// Central design system Button component for "My Preparation".
///
/// Ensures consistent minimum touch target (44–48px), loading state handling,
/// disabled states, and prevents visual collision with headers and cards.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  /// Convenience constructor for primary action button.
  const AppButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
  }) : variant = AppButtonVariant.primary;

  /// Convenience constructor for secondary action button.
  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
  }) : variant = AppButtonVariant.secondary;

  /// Convenience constructor for outlined action button.
  const AppButton.outlined({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
  }) : variant = AppButtonVariant.outlined;

  /// Convenience constructor for flat text action button.
  const AppButton.text({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
  }) : variant = AppButtonVariant.text;

  /// Convenience constructor for destructive / danger button.
  const AppButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
  }) : variant = AppButtonVariant.destructive;

  /// Convenience constructor for inverted button placed on hero / colored containers.
  const AppButton.onColor({
    super.key,
    required this.label,
    this.onPressed,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
  }) : variant = AppButtonVariant.onColor;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool isFullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = onPressed != null && !isLoading;

    final double height;
    final EdgeInsetsGeometry padding;
    final TextStyle textStyle;

    switch (size) {
      case AppButtonSize.sm:
        height = AppDimensions.buttonHeightSm;
        padding = AppSpacing.buttonPaddingSm;
        textStyle =
            theme.textTheme.labelMedium ??
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
        break;
      case AppButtonSize.md:
        height = AppDimensions.buttonHeightMd;
        padding = AppSpacing.buttonPaddingMd;
        textStyle =
            theme.textTheme.labelLarge ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
        break;
      case AppButtonSize.lg:
        height = AppDimensions.buttonHeightLg;
        padding = AppSpacing.buttonPaddingLg;
        textStyle =
            (theme.textTheme.labelLarge ??
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
                .copyWith(fontSize: 15);
        break;
    }

    final Color bgColor;
    final Color fgColor;
    final BorderSide? border;

    switch (variant) {
      case AppButtonVariant.primary:
        bgColor = isEnabled
            ? colorScheme.primary
            : colorScheme.onSurface.withValues(alpha: 0.12);
        fgColor = isEnabled
            ? colorScheme.onPrimary
            : colorScheme.onSurface.withValues(alpha: 0.38);
        border = null;
        break;

      case AppButtonVariant.secondary:
        bgColor = isEnabled
            ? colorScheme.secondaryContainer
            : colorScheme.onSurface.withValues(alpha: 0.08);
        fgColor = isEnabled
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurface.withValues(alpha: 0.38);
        border = null;
        break;

      case AppButtonVariant.outlined:
        bgColor = Colors.transparent;
        fgColor = isEnabled
            ? colorScheme.primary
            : colorScheme.onSurface.withValues(alpha: 0.38);
        border = BorderSide(
          color: isEnabled
              ? colorScheme.outline
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: AppDimensions.borderWidth,
        );
        break;

      case AppButtonVariant.text:
        bgColor = Colors.transparent;
        fgColor = isEnabled
            ? colorScheme.primary
            : colorScheme.onSurface.withValues(alpha: 0.38);
        border = null;
        break;

      case AppButtonVariant.destructive:
        bgColor = isEnabled
            ? colorScheme.error
            : colorScheme.onSurface.withValues(alpha: 0.12);
        fgColor = isEnabled
            ? colorScheme.onError
            : colorScheme.onSurface.withValues(alpha: 0.38);
        border = null;
        break;

      case AppButtonVariant.onColor:
        bgColor = isEnabled
            ? colorScheme.surface
            : Colors.white.withValues(alpha: 0.2);
        fgColor = isEnabled
            ? colorScheme.primary
            : Colors.white.withValues(alpha: 0.5);
        border = null;
        break;
    }

    Widget content;
    if (isLoading) {
      content = SizedBox(
        width: AppIconSize.button,
        height: AppIconSize.button,
        child: CircularProgressIndicator(
          strokeWidth: 2.0,
          valueColor: AlwaysStoppedAnimation<Color>(fgColor),
        ),
      );
    } else {
      final children = <Widget>[];

      if (icon != null) {
        children.add(Icon(icon, size: AppIconSize.button, color: fgColor));
        children.add(AppSpacing.hGapSm);
      }

      children.add(
        Flexible(
          child: Text(
            label,
            style: textStyle.copyWith(color: fgColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

      if (trailingIcon != null) {
        children.add(AppSpacing.hGapSm);
        children.add(
          Icon(trailingIcon, size: AppIconSize.button, color: fgColor),
        );
      }

      content = Row(
        mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      );
    }

    final buttonWidget = Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: border ?? BorderSide.none,
      ),
      child: InkWell(
        borderRadius: AppRadius.mdBorder,
        onTap: isEnabled ? onPressed : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: height,
            minWidth: height, // Ensures square minimum touch target
          ),
          child: Padding(
            padding: padding,
            child: Center(
              widthFactor: isFullWidth ? null : 1.0,
              child: content,
            ),
          ),
        ),
      ),
    );

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: buttonWidget);
    }
    return buttonWidget;
  }
}
