// Auth screen: neumorphic login/signup card with a 3D flip. No Supabase is
// touched (submit is never triggered); the logo falls back to its vector
// painter when the PNG asset is absent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/auth/auth_screen.dart';
import 'package:my_praperation/features/auth/widgets/app_logo.dart';

void main() {
  testWidgets('login face renders, flips to signup and back', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.text('Create Account'), findsNothing, reason: 'back face not painted');

    await tester.tap(find.byTooltip('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing);

    await tester.tap(find.byTooltip('Back to login'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('/signup entry starts on the signup face', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen(startWithSignup: true)));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets('validation blocks submit without any network call', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOGIN'));
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
