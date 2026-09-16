import 'package:flutter/material.dart';

abstract final class AppColors {
  // Primary
  static const Color primaryLight = Color(0xFF3F51B5);
  static const Color primaryDark = Color(0xFF5C6BC0);
  static const Color onPrimary = Colors.white;

  // Secondary
  static const Color secondaryLight = Color(0xFF00BCD4);
  static const Color secondaryDark = Color(0xFF26C6DA);
  static const Color onSecondary = Colors.white;

  // Background
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color backgroundDark = Color(0xFF121212);

  // Surface
  static const Color surfaceLight = Colors.white;
  static const Color surfaceDark = Color(0xFF1E1E1E);

  // Error
  static const Color error = Color(0xFFB00020);
  static const Color onError = Colors.white;

  // Text
  static const Color textPrimaryLight = Color(0xFF212121);
  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textPrimaryDark = Color(0xFFE0E0E0);
  static const Color textSecondaryDark = Color(0xFF9E9E9E);

  // Success
  static const Color success = Color(0xFF4CAF50);

  // Warning
  static const Color warning = Color(0xFFFF9800);
}
