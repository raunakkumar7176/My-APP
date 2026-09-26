import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/about/screens/about_app_screen.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    home: child,
  );
}

void main() {
  group('AboutAppScreen', () {
    testWidgets('renders top header, vision, and version badge', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AboutAppScreen()));
      await tester.pumpAndSettle();

      expect(find.text('My Preparation'), findsOneWidget);
      expect(
        find.textContaining('Built for serious competitive exam preparation'),
        findsOneWidget,
      );
      expect(find.textContaining('v1.0.0'), findsOneWidget);
    });

    testWidgets('renders Founder Desk VIP Card with Raunak and golden tick', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AboutAppScreen()));
      await tester.pumpAndSettle();

      expect(find.text('The Founder Desk'), findsOneWidget);
      expect(find.text('Raunak'), findsOneWidget);
      expect(find.text('Founder & Lead Architect'), findsOneWidget);
      expect(find.text('A Message to Every Aspirant'), findsOneWidget);
      expect(find.text('View Founder Profile'), findsOneWidget);

      // Verify Golden Verified Tick icon exists with #F59E0B
      final goldenTickFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon == Icons.verified_rounded &&
            widget.color == const Color(0xFFF59E0B),
      );
      expect(goldenTickFinder, findsWidgets);
    });

    testWidgets('renders Core Team & Contributors section', (tester) async {
      await tester.pumpWidget(_host(const AboutAppScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Core Team & Contributors'), findsOneWidget);
      expect(find.text('Lead Developer'), findsOneWidget);
      expect(find.text('Academic Mentor'), findsOneWidget);
      expect(find.text('Content Advisor'), findsOneWidget);
      expect(find.text('⭐ Verified Core'), findsNWidgets(3));
    });

    testWidgets('renders App Philosophy accordion with all 3 pillars', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AboutAppScreen()));
      await tester.pumpAndSettle();

      expect(find.text('App Philosophy & How It Works'), findsOneWidget);
      expect(
        find.text('How Chapters (Learn + Assessment Hub) Work'),
        findsOneWidget,
      );
      expect(
        find.text('How 1,000 Points & 90-Day Blue Tick Work'),
        findsOneWidget,
      );
      expect(
        find.text('Strict Unique Student ID Policy (Anti-Spam)'),
        findsOneWidget,
      );
    });

    testWidgets(
      'renders Help Desk FAQ and opens Contact Support bottom sheet',
      (tester) async {
        await tester.pumpWidget(_host(const AboutAppScreen()));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('💬 Contact Support / Report Issue'),
          300,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          find.text('Help Desk & Problem Solutions (FAQ)'),
          findsOneWidget,
        );
        expect(find.text('💬 Contact Support / Report Issue'), findsOneWidget);

        await tester.tap(find.text('💬 Contact Support / Report Issue'));
        await tester.pumpAndSettle();

        expect(find.text('Contact Support / Report Issue'), findsOneWidget);
        expect(find.text('Copy Email'), findsOneWidget);
        expect(find.text('Send Ticket'), findsOneWidget);
      },
    );
  });
}
