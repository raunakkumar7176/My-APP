import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_icon_size.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Central theme architecture for "My Preparation".
///
/// Provides complete, accessible Material 3 [ThemeData] for Light and Dark modes.
///
/// CRITICAL PRODUCT RULE:
/// Header color NEVER equals primary action button color.
/// - AppBar uses [colorScheme.surface], keeping it clean and neutral.
/// - Primary buttons use [colorScheme.primary], ensuring sharp visual separation
///   from headers, cards, and navigation surfaces.
abstract final class AppTheme {
  // ── Light Theme ──────────────────────────────────────────────────────────

  static final ThemeData light = _buildLight();
  static final ThemeData dark = _buildDark();

  static ThemeData _buildLight() {
    final colorScheme = AppColors.lightColorScheme;
    final textTheme = AppTypography.createTextTheme(
      colorScheme.onSurface,
      colorScheme.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLow,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,

      // 1. AppBar Theme (Surface neutral — decoupled from primary button)
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
          size: AppIconSize.section,
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // 2. Card Theme (Flat with refined 1px border and 12px radius)
      cardTheme: CardThemeData(
        elevation: AppDimensions.cardElevation,
        color: colorScheme.surface,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.lgBorder,
          side: BorderSide(
            color: AppColors.outlineVariantLight,
            width: AppDimensions.borderWidth,
          ),
        ),
      ),

      // 3. Button Themes
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppDimensions.buttonHeightMd),
          padding: AppSpacing.buttonPaddingMd,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, AppDimensions.buttonHeightMd),
          padding: AppSpacing.buttonPaddingMd,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          elevation: 1,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppDimensions.buttonHeightMd),
          padding: AppSpacing.buttonPaddingMd,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          side: BorderSide(
            color: colorScheme.outline,
            width: AppDimensions.borderWidth,
          ),
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppDimensions.buttonHeightSm),
          padding: AppSpacing.buttonPaddingSm,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelMedium,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            AppDimensions.minTouchTarget,
            AppDimensions.minTouchTarget,
          ),
          iconSize: AppIconSize.button,
          foregroundColor: colorScheme.onSurfaceVariant,
        ),
      ),

      // 4. Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14.0,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant,
            width: AppDimensions.borderWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant,
            width: AppDimensions.borderWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: AppDimensions.activeBorderWidth,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: AppDimensions.borderWidth,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: AppDimensions.activeBorderWidth,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: AppDimensions.borderWidth,
          ),
        ),
      ),

      // 5. Dialog & Bottom Sheet Theme
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 3.0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgBorder),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceLight,
        elevation: 4.0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.topLgBorder),
      ),

      // 6. Navigation Bar & TabBar Theme
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 1,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: colorScheme.primary,
              size: AppIconSize.section,
            );
          }
          return IconThemeData(
            color: colorScheme.onSurfaceVariant,
            size: AppIconSize.section,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            );
          }
          return textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.bodyMedium,
      ),

      // 7. Divider, SnackBar, Chip & Progress Indicators
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: AppDimensions.borderWidth,
        space: 1.0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.surface,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: AppDimensions.borderWidth,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smBorder),
        labelStyle: textTheme.labelSmall,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2.0,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }

  // ── Dark Theme ───────────────────────────────────────────────────────────

  static ThemeData _buildDark() {
    final colorScheme = AppColors.darkColorScheme;
    final textTheme = AppTypography.createTextTheme(
      colorScheme.onSurface,
      colorScheme.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLow,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,

      // 1. AppBar Theme
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
          size: AppIconSize.section,
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // 2. Card Theme
      cardTheme: CardThemeData(
        elevation: AppDimensions.cardElevation,
        color: colorScheme.surface,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.lgBorder,
          side: BorderSide(
            color: AppColors.outlineVariantDark,
            width: AppDimensions.borderWidth,
          ),
        ),
      ),

      // 3. Button Themes
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppDimensions.buttonHeightMd),
          padding: AppSpacing.buttonPaddingMd,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, AppDimensions.buttonHeightMd),
          padding: AppSpacing.buttonPaddingMd,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          elevation: 1,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppDimensions.buttonHeightMd),
          padding: AppSpacing.buttonPaddingMd,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          side: BorderSide(
            color: colorScheme.outline,
            width: AppDimensions.borderWidth,
          ),
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppDimensions.buttonHeightSm),
          padding: AppSpacing.buttonPaddingSm,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelMedium,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            AppDimensions.minTouchTarget,
            AppDimensions.minTouchTarget,
          ),
          iconSize: AppIconSize.button,
          foregroundColor: colorScheme.onSurfaceVariant,
        ),
      ),

      // 4. Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14.0,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant,
            width: AppDimensions.borderWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant,
            width: AppDimensions.borderWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: AppDimensions.activeBorderWidth,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: AppDimensions.borderWidth,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.error,
            width: AppDimensions.activeBorderWidth,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: AppDimensions.borderWidth,
          ),
        ),
      ),

      // 5. Dialog & Bottom Sheet Theme
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 3.0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgBorder),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceDark,
        elevation: 4.0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.topLgBorder),
      ),

      // 6. Navigation Bar & TabBar Theme
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        elevation: 1,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: colorScheme.onPrimaryContainer,
              size: AppIconSize.section,
            );
          }
          return IconThemeData(
            color: colorScheme.onSurfaceVariant,
            size: AppIconSize.section,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelSmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            );
          }
          return textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.bodyMedium,
      ),

      // 7. Divider, SnackBar, Chip & Progress Indicators
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: AppDimensions.borderWidth,
        space: 1.0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: AppDimensions.borderWidth,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smBorder),
        labelStyle: textTheme.labelSmall,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2.0,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }
}
