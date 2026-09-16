import 'package:flutter/material.dart';

import '../../../core/constants/theme/app_colors.dart';
import '../../../core/models/test.dart';

/// Shared presentation helpers for the test system (one copy).
abstract final class TestFormatters {
  static String duration(int? seconds) {
    if (seconds == null) return '--';
    final minutes = seconds ~/ 60;
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${minutes}m';
  }

  /// Always renders in the device's local zone (server values are instants).
  static String dateTime(DateTime? value) {
    if (value == null) return '--';
    final d = value.toLocal();
    return '${d.day}/${d.month}/${d.year} '
        '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  static Color statusColor(TestStatus status) {
    switch (status) {
      case TestStatus.scheduled:
        return AppColors.warning;
      case TestStatus.live:
      case TestStatus.ready:
        return AppColors.success;
      case TestStatus.completed:
      case TestStatus.ended:
      case TestStatus.evaluated:
        return AppColors.primaryLight;
      case TestStatus.cancelled:
      case TestStatus.expired:
        return AppColors.error;
      case TestStatus.draft:
      case TestStatus.published:
      case TestStatus.archived:
      case TestStatus.unknown:
        return AppColors.textSecondaryLight;
    }
  }
}
