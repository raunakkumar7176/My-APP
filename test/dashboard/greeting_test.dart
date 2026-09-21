import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/dashboard/domain/greeting.dart';

void main() {
  group('Greeting.forHour', () {
    test('midnight is morning', () {
      expect(Greeting.forHour(0), 'Good Morning');
    });

    test('11:59 is still morning', () {
      expect(Greeting.forHour(11), 'Good Morning');
    });

    test('noon is afternoon', () {
      expect(Greeting.forHour(12), 'Good Afternoon');
    });

    test('16:59 is still afternoon', () {
      expect(Greeting.forHour(16), 'Good Afternoon');
    });

    test('17:00 is evening', () {
      expect(Greeting.forHour(17), 'Good Evening');
    });

    test('23:59 is still evening', () {
      expect(Greeting.forHour(23), 'Good Evening');
    });
  });

  group('Greeting.time12h', () {
    test('midnight formats as 12:00 AM', () {
      expect(Greeting.time12h(0, 0), '12:00 AM');
    });

    test('noon formats as 12:00 PM', () {
      expect(Greeting.time12h(12, 0), '12:00 PM');
    });

    test('afternoon hour formats correctly with padded minutes', () {
      expect(Greeting.time12h(14, 5), '2:05 PM');
    });

    test('morning hour formats correctly', () {
      expect(Greeting.time12h(9, 30), '9:30 AM');
    });
  });

  group('Greeting.weekdayName', () {
    test('1 is Monday', () {
      expect(Greeting.weekdayName(1), 'Monday');
    });

    test('7 is Sunday', () {
      expect(Greeting.weekdayName(7), 'Sunday');
    });
  });

  group('Greeting.monthName', () {
    test('1 is Jan', () {
      expect(Greeting.monthName(1), 'Jan');
    });

    test('12 is Dec', () {
      expect(Greeting.monthName(12), 'Dec');
    });
  });
}
