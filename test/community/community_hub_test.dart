import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/community/screens/community_hub_screen.dart';
import 'package:my_praperation/features/community/widgets/unique_id_search_sheet.dart';
import 'package:my_praperation/features/community/widgets/user_promotion_modal.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    home: child,
  );
}

void main() {
  group('CommunityHubScreen', () {
    testWidgets('renders public community hub for normal aspirants', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const CommunityHubScreen(isOwnerOverride: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Community Hub'), findsOneWidget);
      expect(find.text('My Preparation Cohort'), findsOneWidget);
      expect(find.text('Announcements & Updates'), findsOneWidget);
      expect(find.text('Code of Conduct & Guidelines'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Student Help & Support Desk'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Student Help & Support Desk'), findsOneWidget);

      // Founder Desk tab should NOT be present for normal aspirants
      expect(find.text('Founder Desk'), findsNothing);
    });

    testWidgets(
      'renders Founder Command Desk tab when isOwnerOverride is true',
      (tester) async {
        await tester.pumpWidget(
          _host(const CommunityHubScreen(isOwnerOverride: true)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Community Hub'), findsOneWidget);
        expect(find.text('Community'), findsOneWidget);
        expect(find.text('Founder Desk'), findsOneWidget);

        // Switch to Founder Desk tab
        await tester.tap(find.text('Founder Desk'));
        await tester.pumpAndSettle();

        expect(find.text('Founder & Owner Command Desk'), findsOneWidget);
        expect(find.text('Promote User'), findsOneWidget);
        expect(find.text('Broadcast'), findsOneWidget);
        expect(find.text('Sweep Badges'), findsOneWidget);
        expect(find.text('Verification Request Queue'), findsOneWidget);
      },
    );

    testWidgets('tapping Promote User opens UserPromotionModal', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const CommunityHubScreen(isOwnerOverride: true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Founder Desk'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Promote User'));
      await tester.pumpAndSettle();

      expect(find.text('Promote Student Role'), findsOneWidget);
      expect(find.text('Target Student ID'), findsOneWidget);
      expect(find.text('Select New Role'), findsOneWidget);
      expect(find.text('Core Team'), findsOneWidget);
      expect(find.text('Scholar'), findsOneWidget);
      expect(find.text('Aspirant'), findsOneWidget);
      expect(find.text('Custom Role Title (Optional)'), findsOneWidget);
      expect(find.text('Grant VIP Access'), findsOneWidget);
      expect(find.text('Grant Verified Blue Tick'), findsOneWidget);
      expect(find.text('Promote & Grant Privileges'), findsOneWidget);
    });
  });

  group('UniqueIdSearchSheet', () {
    testWidgets('renders search sheet with hint and ID input field', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => UniqueIdSearchSheet.show(ctx),
                child: const Text('Open Search'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Search'));
      await tester.pumpAndSettle();

      expect(find.text('Find Student by Unique ID'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.textContaining('Unique Student Codes protect cohort identity'),
        findsOneWidget,
      );
    });
  });

  group('UserPromotionModal', () {
    testWidgets(
      'renders with initial student code and validates empty submission',
      (tester) async {
        await tester.pumpWidget(
          _host(
            Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => UserPromotionModal.show(
                    ctx,
                    initialStudentCode: 'MP-12345',
                  ),
                  child: const Text('Open Promote Modal'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Promote Modal'));
        await tester.pumpAndSettle();

        expect(find.text('Promote Student Role'), findsOneWidget);
        expect(find.text('MP-12345'), findsOneWidget);

        // Clear student ID and submit to verify validation
        await tester.enterText(
          find.byKey(const Key('promote_student_code_field')),
          '',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('promote_submit_button')));
        await tester.pumpAndSettle();

        expect(
          find.text('Please enter a Student ID (e.g. MP-84920).'),
          findsOneWidget,
        );
      },
    );
  });
}
