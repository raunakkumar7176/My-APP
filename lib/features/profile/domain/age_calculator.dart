/// Utility for computing exact chronological age in years, months, and days.
abstract final class AgeCalculator {
  /// Calculates precise age from a [dateOfBirth] relative to [now] (defaults to `DateTime.now()`).
  ///
  /// Returns a formatted string like `"21y 04m 12d"`, or `null` if [dateOfBirth] is `null`
  /// or if [dateOfBirth] is in the future.
  static String? calculatePreciseAge(DateTime? dateOfBirth, {DateTime? now}) {
    final parts = getAgeParts(dateOfBirth, now: now);
    if (parts == null) return null;
    final m = parts.months.toString().padLeft(2, '0');
    final d = parts.days.toString().padLeft(2, '0');
    return '${parts.years}y ${m}m ${d}d';
  }

  /// Returns raw breakdown of years, months, days.
  static ({int years, int months, int days})? getAgeParts(
    DateTime? dateOfBirth, {
    DateTime? now,
  }) {
    if (dateOfBirth == null) return null;

    final target = now ?? DateTime.now();
    if (dateOfBirth.isAfter(target)) return null;

    int years = target.year - dateOfBirth.year;
    int months = target.month - dateOfBirth.month;
    int days = target.day - dateOfBirth.day;

    if (days < 0) {
      // Days in the preceding month of target date
      final daysInPrevMonth = DateTime(target.year, target.month, 0).day;
      days += daysInPrevMonth;
      months -= 1;
    }

    if (months < 0) {
      months += 12;
      years -= 1;
    }

    if (years < 0) return null;

    return (years: years, months: months, days: days);
  }
}
