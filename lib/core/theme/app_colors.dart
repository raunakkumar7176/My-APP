import 'package:flutter/material.dart';

/// Semantic color palette for "My Preparation".
///
/// Provides both Material 3 [ColorScheme] factories and individual tokens.
/// All legacy static fields are strictly preserved for backward compatibility.
abstract final class AppColors {
  // ── 1. Legacy Static Constants (Preserved for compatibility) ─────────────

  // Primary (Deep Command Blue / Scholarly Indigo)
  static const Color primaryLight = Color(0xFF254EDB);
  static const Color primaryDark = Color(0xFF6B8AFF);
  static const Color onPrimary = Colors.white;

  // Secondary (Slate Cyan)
  static const Color secondaryLight = Color(0xFF0284C7);
  static const Color secondaryDark = Color(0xFF38BDF8);
  static const Color onSecondary = Colors.white;

  // Background
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color backgroundDark = Color(0xFF0F172A);

  // Surface
  static const Color surfaceLight = Colors.white;
  static const Color surfaceDark = Color(0xFF1E293B);

  // Error
  static const Color error = Color(0xFFDC2626);
  static const Color onError = Colors.white;

  // Text
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  // Success & Warning
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);

  // ── 2. Extended Design Tokens ───────────────────────────────────────────

  // Primary containers
  static const Color primaryContainerLight = Color(0xFFEEF2FF);
  static const Color onPrimaryContainerLight = Color(0xFF1E3A8A);
  static const Color primaryContainerDark = Color(0xFF1E3A8A);
  static const Color onPrimaryContainerDark = Color(0xFFDBEAFE);

  // Secondary containers
  static const Color secondaryContainerLight = Color(0xFFF0F9FF);
  static const Color onSecondaryContainerLight = Color(0xFF075985);
  static const Color secondaryContainerDark = Color(0xFF075985);
  static const Color onSecondaryContainerDark = Color(0xFFE0F2FE);

  // Tertiary / Achievement (Focused Gold / Amber for Streaks & Milestones)
  static const Color tertiaryLight = Color(0xFFD97706);
  static const Color onTertiaryLight = Colors.white;
  static const Color tertiaryContainerLight = Color(0xFFFEF3C7);
  static const Color onTertiaryContainerLight = Color(0xFF78350F);

  static const Color tertiaryDark = Color(0xFFFBBF24);
  static const Color onTertiaryDark = Color(0xFF451A03);
  static const Color tertiaryContainerDark = Color(0xFF78350F);
  static const Color onTertiaryContainerDark = Color(0xFFFEF3C7);

  // Neutral Surface Containers (Material 3 surface tiers)
  static const Color surfaceContainerLowestLight = Colors.white;
  static const Color surfaceContainerLowLight = Color(0xFFF8FAFC);
  static const Color surfaceContainerMediumLight = Color(0xFFF1F5F9);
  static const Color surfaceContainerHighLight = Color(0xFFE2E8F0);
  static const Color surfaceContainerHighestLight = Color(0xFFCBD5E1);

  static const Color surfaceContainerLowestDark = Color(0xFF0B1120);
  static const Color surfaceContainerLowDark = Color(0xFF111827);
  static const Color surfaceContainerMediumDark = Color(0xFF1E293B);
  static const Color surfaceContainerHighDark = Color(0xFF334155);
  static const Color surfaceContainerHighestDark = Color(0xFF475569);

  // Outlines & Borders
  static const Color outlineLight = Color(0xFFCBD5E1);
  static const Color outlineVariantLight = Color(0xFFE2E8F0);
  static const Color outlineDark = Color(0xFF475569);
  static const Color outlineVariantDark = Color(0xFF334155);

  // Feedback & Status
  static const Color info = Color(0xFF2563EB);
  static const Color onInfo = Colors.white;
  static const Color infoContainerLight = Color(0xFFEFF6FF);
  static const Color infoContainerDark = Color(0xFF1E3A8A);

  static const Color successContainerLight = Color(0xFFF0FDF4);
  static const Color onGoldSuccess = Color(0xFF14532D);
  static const Color successContainerDark = Color(0xFF14532D);
  static const Color onSuccess = Colors.white;

  static const Color warningContainerLight = Color(0xFFFFFBEB);
  static const Color onWarning = Colors.white;
  static const Color warningContainerDark = Color(0xFF78350F);

  static const Color errorContainerLight = Color(0xFFFEF2F2);
  static const Color onErrorContainerLight = Color(0xFF991B1B);
  static const Color errorContainerDark = Color(0xFF7F1D1D);
  static const Color onErrorContainerDark = Color(0xFFFEE2E2);

  // Disabled states
  static const Color disabledLight = Color(0xFFE2E8F0);
  static const Color onDisabledLight = Color(0xFF94A3B8);
  static const Color disabledDark = Color(0xFF334155);
  static const Color onDisabledDark = Color(0xFF64748B);

  // ── 3. Material 3 ColorScheme Builders ──────────────────────────────────

  static ColorScheme get lightColorScheme => const ColorScheme(
    brightness: Brightness.light,
    primary: primaryLight,
    onPrimary: onPrimary,
    primaryContainer: primaryContainerLight,
    onPrimaryContainer: onPrimaryContainerLight,
    secondary: secondaryLight,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainerLight,
    onSecondaryContainer: onSecondaryContainerLight,
    tertiary: tertiaryLight,
    onTertiary: onTertiaryLight,
    tertiaryContainer: tertiaryContainerLight,
    onTertiaryContainer: onTertiaryContainerLight,
    error: error,
    onError: onError,
    errorContainer: errorContainerLight,
    onErrorContainer: onErrorContainerLight,
    surface: surfaceLight,
    onSurface: textPrimaryLight,
    surfaceContainerLowest: surfaceContainerLowestLight,
    surfaceContainerLow: surfaceContainerLowLight,
    surfaceContainer: surfaceContainerMediumLight,
    surfaceContainerHigh: surfaceContainerHighLight,
    surfaceContainerHighest: surfaceContainerHighestLight,
    onSurfaceVariant: textSecondaryLight,
    outline: outlineLight,
    outlineVariant: outlineVariantLight,
  );

  static ColorScheme get darkColorScheme => const ColorScheme(
    brightness: Brightness.dark,
    primary: primaryDark,
    onPrimary: Color(0xFF0F172A),
    primaryContainer: primaryContainerDark,
    onPrimaryContainer: onPrimaryContainerDark,
    secondary: secondaryDark,
    onSecondary: Color(0xFF0F172A),
    secondaryContainer: secondaryContainerDark,
    onSecondaryContainer: onSecondaryContainerDark,
    tertiary: tertiaryDark,
    onTertiary: onTertiaryDark,
    tertiaryContainer: tertiaryContainerDark,
    onTertiaryContainer: onTertiaryContainerDark,
    error: Color(0xFFEF4444),
    onError: Colors.white,
    errorContainer: errorContainerDark,
    onErrorContainer: onErrorContainerDark,
    surface: surfaceDark,
    onSurface: textPrimaryDark,
    surfaceContainerLowest: surfaceContainerLowestDark,
    surfaceContainerLow: surfaceContainerLowDark,
    surfaceContainer: surfaceContainerMediumDark,
    surfaceContainerHigh: surfaceContainerHighDark,
    surfaceContainerHighest: surfaceContainerHighestDark,
    onSurfaceVariant: textSecondaryDark,
    outline: outlineDark,
    outlineVariant: outlineVariantDark,
  );
}
