import 'package:flutter/material.dart';

import '../theme/app_icon_size.dart';
import '../theme/app_spacing.dart';

/// Central design system full-screen or section loading component.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.message, this.isFullScreen = false});

  final String? message;
  final bool isFullScreen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: AppIconSize.section + 8,
            height: AppIconSize.section + 8,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          if (message != null) ...[
            AppSpacing.vGapMd,
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );

    if (isFullScreen) {
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLow,
        body: content,
      );
    }

    return Padding(padding: AppSpacing.paddingXl, child: content);
  }
}

/// Compact inline spinner for buttons, table cells, or trailing indicators.
class AppInlineSpinner extends StatelessWidget {
  const AppInlineSpinner({
    super.key,
    this.size = AppIconSize.inline,
    this.strokeWidth = 2.0,
    this.color,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
      ),
    );
  }
}
