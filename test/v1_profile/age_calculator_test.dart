import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/profile/domain/age_calculator.dart';

void main() {
  group('AgeCalculator', () {
    test('returns null for null date of birth', () {
      expect(AgeCalculator.calculatePreciseAge(null), isNull);
    });

    test('returns null for future date', () {
      final now = DateTime(2025, 5, 20);
      final futureDob = DateTime(2025, 6, 1);
      expect(AgeCalculator.calculatePreciseAge(futureDob, now: now), isNull);
    });

    test('calculates exact age without borrowing', () {
      final now = DateTime(2025, 6, 20);
      final dob = DateTime(2004, 2, 8);
      // 2025 - 2004 = 21 years
      // 6 - 2 = 4 months
      // 20 - 8 = 12 days
      expect(AgeCalculator.calculatePreciseAge(dob, now: now), '21y 04m 12d');
    });

    test('calculates exact age with day borrow', () {
      final now = DateTime(2025, 3, 10);
      final dob = DateTime(2000, 1, 25);
      // Previous month is February 2025 (28 days).
      // Days: 10 + 28 - 25 = 13 days
      // Months: (3 - 1) - 1 = 1 month
      // Years: 2025 - 2000 = 25 years
      expect(AgeCalculator.calculatePreciseAge(dob, now: now), '25y 01m 13d');
    });
  });
}
