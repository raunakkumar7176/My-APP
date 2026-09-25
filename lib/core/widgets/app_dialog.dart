import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';

/// Central design system Dialog component for "My Preparation".
///
/// Standardizes confirmation, alert, and destructive prompt dialogs.
abstract final class AppDialog {
  /// Shows a standardized confirmation dialog.
  ///
  /// Returns `true` if the user confirmed, `false` or `null` if cancelled.
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgBorder),
        title: Text(title, style: theme.textTheme.titleLarge),
        content: Text(message, style: theme.textTheme.bodyMedium),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        actions: [
          AppButton.text(
            label: cancelLabel,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          isDestructive
              ? AppButton.destructive(
                  label: confirmLabel,
                  onPressed: () => Navigator.of(ctx).pop(true),
                )
              : AppButton.primary(
                  label: confirmLabel,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
        ],
      ),
    );
  }
}
