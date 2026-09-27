import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/models/profile.dart';
import 'package:my_praperation/core/services/profile_service.dart';
import 'package:my_praperation/features/profile/domain/social_platform.dart';
import 'package:my_praperation/features/profile/profile_screen.dart';
import 'package:my_praperation/features/profile/state/profile_controller.dart';

void main() {
  group('SocialPlatform Domain Tests', () {
    test('looks up platform correctly by key, handling case and aliases', () {
      expect(SocialPlatform.fromKey('linkedin'), SocialPlatform.linkedin);
      expect(SocialPlatform.fromKey('LINKEDIN'), SocialPlatform.linkedin);
      expect(SocialPlatform.fromKey('twitter'), SocialPlatform.x);
      expect(SocialPlatform.fromKey('x'), SocialPlatform.x);
      expect(SocialPlatform.fromKey('youtube'), SocialPlatform.youtube);
      expect(SocialPlatform.fromKey('telegram'), SocialPlatform.telegram);
      expect(SocialPlatform.fromKey('instagram'), SocialPlatform.instagram);
      expect(SocialPlatform.fromKey('github'), SocialPlatform.github);
      expect(SocialPlatform.fromKey('website'), SocialPlatform.website);
      expect(SocialPlatform.fromKey('unknown_key'), isNull);
    });

    test('normalizes URLs correctly across platforms', () {
      // Handles with @
      expect(
        SocialPlatform.normalizeUrl(SocialPlatform.x, '@raunak'),
        'https://x.com/raunak',
      );
      expect(
        SocialPlatform.normalizeUrl(SocialPlatform.youtube, '@raunakkumar'),
        'https://youtube.com/@raunakkumar',
      );

      // Clean usernames
      expect(
        SocialPlatform.normalizeUrl(SocialPlatform.linkedin, 'raunak-kumar'),
        'https://linkedin.com/in/raunak-kumar',
      );
      expect(
        SocialPlatform.normalizeUrl(SocialPlatform.github, 'raunakkumar'),
        'https://github.com/raunakkumar',
      );
      expect(
        SocialPlatform.normalizeUrl(SocialPlatform.telegram, 'raunakofficial'),
        'https://t.me/raunakofficial',
      );

      // Full HTTPS URLs preserved
      expect(
        SocialPlatform.normalizeUrl(
          SocialPlatform.github,
          'https://github.com/raunak-custom',
        ),
        'https://github.com/raunak-custom',
      );

      // Website domain without scheme
      expect(
        SocialPlatform.normalizeUrl(
          SocialPlatform.website,
          'mypreparation.app',
        ),
        'https://mypreparation.app',
      );
    });
  });

  group('Founder Profile & Responsive Polish Tests', () {
    Widget createTestApp(Widget child, {Size size = const Size(390, 844)}) {
      final router = GoRouter(
        initialLocation: '/test',
        routes: [GoRoute(path: '/test', builder: (_, _) => child)],
      );

      return MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets(
      'renders founder profile with golden tick, credentials & social chips',
      (tester) async {
        final founderProfile = ProfileService.fallbackFounderProfile;

        final controller = ProfileController(
          targetUserId: founderProfile.id,
          initialProfile: founderProfile,
        );

        await tester.pumpWidget(
          createTestApp(
            ProfileScreen(
              userId: founderProfile.id,
              initialProfile: founderProfile,
              controller: controller,
            ),
          ),
        );
        await tester.pump();

        // Verify Founder identity (header and view card)
        expect(find.text('Raunak Kumar'), findsNWidgets(2));
        expect(find.text('🛡️ FOUNDER'), findsOneWidget);
        expect(find.text('MP-FOUNDER'), findsOneWidget);

        // Verify Golden Verified Tick icon
        final iconFinder = find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              w.icon == Icons.verified_rounded &&
              w.color == const Color(0xFFF59E0B),
        );
        expect(iconFinder, findsOneWidget);

        // Verify Founder Credentials Card
        expect(find.text('Founder & System Architect'), findsOneWidget);
        expect(
          find.text('Official App Creator & Academic Lead'),
          findsOneWidget,
        );
        expect(find.textContaining('Vision:'), findsOneWidget);
        expect(find.textContaining('Invigilator & Integrity:'), findsOneWidget);
        expect(find.textContaining('Mentorship:'), findsOneWidget);

        // Verify Social Media Chips
        expect(find.text('Social Handles & Links'), findsOneWidget);
        expect(find.text('LinkedIn'), findsOneWidget);
        expect(find.text('GitHub'), findsOneWidget);
        expect(find.text('YouTube'), findsOneWidget);

        // Verify edit button is not present when viewing other/founder
        expect(find.byKey(const Key('profile_edit_button')), findsNothing);
      },
    );

    testWidgets(
      'renders cleanly at 320x640 small screen with 0 overflow errors',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final founderProfile = ProfileService.fallbackFounderProfile;
        final controller = ProfileController(
          targetUserId: founderProfile.id,
          initialProfile: founderProfile,
        );

        await tester.pumpWidget(
          createTestApp(
            ProfileScreen(
              userId: founderProfile.id,
              initialProfile: founderProfile,
              controller: controller,
            ),
            size: const Size(320, 640),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Metrics strip is visible without overflow
        expect(find.text('Followers'), findsOneWidget);
        expect(find.text('Following'), findsOneWidget);
        expect(find.text('Study Points'), findsOneWidget);
      },
    );

    testWidgets(
      'renders cleanly at 800x1280 tablet screen with 0 overflow errors',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1280);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final founderProfile = ProfileService.fallbackFounderProfile;
        final controller = ProfileController(
          targetUserId: founderProfile.id,
          initialProfile: founderProfile,
        );

        await tester.pumpWidget(
          createTestApp(
            ProfileScreen(
              userId: founderProfile.id,
              initialProfile: founderProfile,
              controller: controller,
            ),
            size: const Size(800, 1280),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Raunak Kumar'), findsNWidgets(2));
        expect(find.text('Founder & System Architect'), findsOneWidget);
      },
    );

    testWidgets(
      'opening social links editor on own profile displays dynamic dropdown and add button',
      (tester) async {
        final myProfile = Profile(
          id: 'me_123',
          fullName: 'Student Candidate',
          avatarUrl: null,
          timezone: 'Asia/Kolkata',
          createdAt: DateTime(2026, 1, 1),
          studentCode: 'MP-9999',
          bio: 'Aspiring officer',
          mobile: '9999999999',
          examTargets: const ['UPSC'],
          socialLinks: const {'linkedin': 'https://linkedin.com/in/student'},
        );

        ProfileService.setProfileForTesting(myProfile);

        final controller = ProfileController(
          targetUserId: null,
          initialProfile: myProfile,
        );

        await tester.pumpWidget(
          createTestApp(
            ProfileScreen(
              controller: controller,
              currentUserEmail: () => 'candidate@example.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tapping "Edit" on Social Handles & Links
        final editBtn = find.text('Edit');
        expect(editBtn, findsOneWidget);
        await tester.tap(editBtn);
        await tester.pumpAndSettle();

        // Dialog opens
        expect(find.text('Social Media Handles'), findsOneWidget);
        expect(find.text('+ Add Social Link'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);

        // Tapping Cancel dismisses the dialog
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Social Media Handles'), findsNothing);
      },
    );
  });
}
