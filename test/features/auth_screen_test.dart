// Auth screen widget tests for the modernized "My Preparation" design system.
// Tests login and signup faces, 3D flip interaction, form validation,
// password visibility toggling, branding, and footer rendering.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/auth/auth_screen.dart';
import 'package:my_praperation/features/auth/widgets/app_logo.dart';

void main() {
  testWidgets(
    'login face renders branding, card, footer, and flips to signup and back',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
      await tester.pumpAndSettle();

      // Branding and header
      expect(find.text('My Preparation'), findsOneWidget);
      expect(find.text('Learn • Practice • Test • Improve'), findsOneWidget);
      expect(find.byType(AppLogo), findsOneWidget);

      // Login card
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('Continue your preparation from where you left off.'),
        findsOneWidget,
      );
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text("Don't have an account?"), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(
        find.text('Create Account'),
        findsNothing,
        reason: 'back face not painted',
      );

      // Footer
      expect(
        find.text('Made in India • Presented by Sharda Group'),
        findsOneWidget,
      );

      // Flip to signup face
      await tester.tap(find.byTooltip('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Create Account'), findsWidgets);
      expect(
        find.text('Start your preparation journey with us.'),
        findsOneWidget,
      );
      expect(find.text('Welcome back'), findsNothing);

      // Flip back to login face
      await tester.tap(find.byTooltip('Back to login'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
    },
  );

  testWidgets('/signup entry starts on the signup face', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AuthScreen(startWithSignup: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsWidgets);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets('validation blocks submit without any network call', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('password visibility toggles', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });
}
