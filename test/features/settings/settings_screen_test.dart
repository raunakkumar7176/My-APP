import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/settings/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    home: child,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsScreen Widget & Interaction Tests', () {
    testWidgets('renders compact profile header card and edit profile button', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pumpAndSettle();

      // Profile header elements
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.textContaining('🆔'), findsOneWidget);
      expect(find.text('📚 Aspirant'), findsOneWidget);
      expect(find.text('Student Aspirant'), findsOneWidget);
    });

    testWidgets('renders all 5 main settings section cards', (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pumpAndSettle();

      // Section Titles
      expect(find.text('EXAM & PREPARATION'), findsOneWidget);
      expect(find.text('DISPLAY & EXPERIENCE'), findsOneWidget);
      expect(find.text('STUDY NUDGES & ALERTS'), findsOneWidget);
      expect(find.text('PRIVACY & ACCESS'), findsOneWidget);
      expect(find.text('ABOUT & COMMUNITY'), findsOneWidget);

      // Tiles in Group 1
      expect(find.text('Target Exam'), findsOneWidget);
      expect(find.text('Daily Study Goal'), findsOneWidget);
      expect(find.text('Language & Medium'), findsOneWidget);

      // Tiles in Group 2
      expect(find.text('Theme Mode'), findsOneWidget);
      expect(find.text('Haptic Feedback (Vibration)'), findsOneWidget);
      expect(find.text('Sound Effects'), findsOneWidget);

      // Tiles in Group 3
      expect(find.text('Daily Revision Reminder'), findsOneWidget);
      expect(find.text('Community & Founder Announcements'), findsOneWidget);
      expect(find.text('Group Activity Alerts'), findsOneWidget);

      // Tiles in Group 4
      expect(find.text('Allow Group Invites'), findsOneWidget);
      expect(find.text('Show Age Badge on Portfolio'), findsOneWidget);
      expect(find.text('Change Password / Security'), findsOneWidget);

      // Tiles in Group 5
      expect(find.text('About App & Founder Desk'), findsOneWidget);
      expect(find.text('Help Desk & Diagnostics'), findsOneWidget);
      expect(find.text('Clear Offline Cache'), findsOneWidget);
      expect(find.text('Terms & Privacy Policy'), findsOneWidget);
    });

    testWidgets('renders footer version and danger zone buttons', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pumpAndSettle();

      // Version badge
      expect(find.text('My Preparation v1.2.0 (Build 58)'), findsOneWidget);

      // Logout button
      expect(find.text('🚪 Log Out'), findsOneWidget);

      // Account deletion link
      expect(find.text('Request Account Deletion'), findsOneWidget);
    });

    testWidgets('toggling switches updates UI state', (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pumpAndSettle();

      final hapticFinder = find.widgetWithText(
        SwitchListTile,
        'Haptic Feedback (Vibration)',
      );
      expect(hapticFinder, findsOneWidget);

      // Tap to toggle off
      await tester.tap(hapticFinder);
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<SwitchListTile>(hapticFinder);
      expect(switchWidget.value, isFalse);
    });

    testWidgets(
      'clearing offline cache resets cache to 0.0 MB and shows SnackBar',
      (tester) async {
        await tester.pumpWidget(_host(const SettingsScreen()));
        await tester.pumpAndSettle();

        // Find the Clear button on cache tile
        final clearBtnFinder = find.widgetWithText(TextButton, 'Clear');
        expect(clearBtnFinder, findsOneWidget);

        await tester.ensureVisible(clearBtnFinder);
        await tester.tap(clearBtnFinder);
        await tester.pumpAndSettle();

        // Cache size updated
        expect(find.text('Cached data: 0.0 MB'), findsOneWidget);
        expect(
          find.text(
            'Offline cache and temporary test data cleared successfully.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('tapping Log Out opens confirmation dialog', (tester) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('🚪 Log Out'));
      await tester.tap(find.text('🚪 Log Out'));
      await tester.pumpAndSettle();

      expect(find.text('Log Out of My Preparation?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Log Out of My Preparation?'), findsNothing);
    });

    testWidgets('tapping Request Account Deletion opens confirmation dialog', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Request Account Deletion'));
      await tester.tap(find.text('Request Account Deletion'));
      await tester.pumpAndSettle();

      expect(find.text('Request Account Deletion'), findsWidgets);
      expect(
        find.textContaining('14-day security grace period'),
        findsOneWidget,
      );

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('14-day security grace period'), findsNothing);
    });
  });
}
