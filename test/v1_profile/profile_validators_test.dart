// Profile — pure validation rules. No Supabase, no widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/profile/state/profile_controller.dart';

void main() {
  group('ProfileValidators.name', () {
    test('rejects empty', () {
      expect(ProfileValidators.name(''), isNotNull);
    });

    test('rejects whitespace-only', () {
      expect(ProfileValidators.name('   '), isNotNull);
    });

    test('accepts a normal name', () {
      expect(ProfileValidators.name('Aditi Sharma'), isNull);
    });

    test('rejects a name over the max length', () {
      final tooLong = 'A' * (ProfileValidators.nameMaxLength + 1);
      expect(ProfileValidators.name(tooLong), isNotNull);
    });

    test('accepts a name exactly at the max length', () {
      final exact = 'A' * ProfileValidators.nameMaxLength;
      expect(ProfileValidators.name(exact), isNull);
    });
  });

  group('ProfileValidators.mobile', () {
    test('empty is valid — phone is optional', () {
      expect(ProfileValidators.mobile(''), isNull);
    });

    test('accepts a plain 10-digit number', () {
      expect(ProfileValidators.mobile('9876543210'), isNull);
    });

    test('accepts a number with a country code and separators', () {
      expect(ProfileValidators.mobile('+91 98765 43210'), isNull);
    });

    test('rejects letters', () {
      expect(ProfileValidators.mobile('not-a-phone'), isNotNull);
    });

    test('rejects something too short to be a real number', () {
      expect(ProfileValidators.mobile('123'), isNotNull);
    });

    test('rejects something absurdly long', () {
      expect(ProfileValidators.mobile('1' * 30), isNotNull);
    });
  });

  group('ProfileValidators.bio', () {
    test('empty is valid', () {
      expect(ProfileValidators.bio(''), isNull);
    });

    test('accepts text under the limit', () {
      expect(ProfileValidators.bio('Aspiring civil servant, JEE 2027.'), isNull);
    });

    test('rejects text over the limit', () {
      final tooLong = 'x' * (ProfileValidators.bioMaxLength + 1);
      expect(ProfileValidators.bio(tooLong), isNotNull);
    });
  });
}
