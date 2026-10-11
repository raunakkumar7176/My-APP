import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system typography hierarchy for "My Preparation".
///
/// Follows Material 3 standard scales while providing specialized study
/// figures (stats, numbers, badge pills, and section headers).
///
/// Typeface: Plus Jakarta Sans (via `google_fonts`) — a modern, premium
/// geometric sans used app-wide, replacing the previous bare system
/// default. Every size/weight/letter-spacing below is unchanged from the
/// original scale; only the font itself was swapped in, via
/// `GoogleFonts.plusJakartaSansTextTheme`, which preserves those
/// properties and only overrides the family. Hindi text automatically
/// falls back to the platform's own Devanagari font for the characters
/// Plus Jakarta Sans doesn't cover — same behavior this app already
/// relied on with the previous font.
abstract final class AppTypography {
  static TextStyle _font(TextStyle base) =>
      GoogleFonts.plusJakartaSans(textStyle: base);

  // ── 1. TextTheme Factory ────────────────────────────────────────────────

  static TextTheme createTextTheme(Color textColor, Color mutedColor) {
    final base = TextTheme(
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        color: textColor,
      ),
      displayMedium: TextStyle(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: textColor,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: textColor,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: textColor,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: textColor,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: mutedColor,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: textColor,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: textColor,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: mutedColor,
      ),
    );

    return GoogleFonts.plusJakartaSansTextTheme(base);
  }

  // ── 2. Specialized Study Metric Styles ──────────────────────────────────

  /// Prominent stat numbers (e.g. 98%, 45/50 score).
  static TextStyle get statLarge => _font(
    const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5),
  );

  /// Medium card stat numbers (e.g. 24 Tests, Rank 3).
  static TextStyle get statMedium =>
      _font(const TextStyle(fontSize: 24, fontWeight: FontWeight.w700));

  /// Compact metric figures (e.g. 15m, 4h).
  static TextStyle get statSmall =>
      _font(const TextStyle(fontSize: 18, fontWeight: FontWeight.w600));

  /// Status badge & pill text.
  static TextStyle get badgeText => _font(
    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
  );

  /// Uppercase section header label.
  static TextStyle get sectionHeader => _font(
    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6),
  );
}
