// Profile screen — widget tests. Seeds ProfileService.currentProfile
// directly (bypassing Supabase, via the same setProfileForTesting seam
// SupabaseService already uses) so the loaded view/edit UI is fully
// testable. currentUserEmail is injected for the same reason
// (AuthService.currentUser touches the live Supabase client).
//
// Save/avatar-upload NETWORK success is not exercised here — see
// profile_controller_test.dart's header comment for why (no fake Supabase
// client exists anywhere in this project's test infra). What IS verified:
// the screen never crashes when that network call fails, and shows a
// clear, non-crashing error instead.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/models/profile.dart';
import 'package:my_praperation/core/services/avatar_service.dart';
import 'package:my_praperation/core/services/profile_service.dart';
import 'package:my_praperation/features/profile/profile_screen.dart';
import 'package:my_praperation/features/profile/screens/avatar_viewer_screen.dart';
import 'package:my_praperation/features/profile/state/profile_controller.dart';

class _FakeAvatarService implements AvatarService {
  Uint8List? nextPicked;
  Object? uploadError;
  final List<String> calls = [];

  @override
  Future<Uint8List?> pickFromGallery() async {
    calls.add('pickFromGallery');
    return nextPicked ?? Uint8List.fromList([0xFF, 0xD8, 0xFF]);
  }

  @override
  Future<Uint8List?> pickFromCamera() async {
    calls.add('pickFromCamera');
    return nextPicked ?? Uint8List.fromList([0xFF, 0xD8, 0xFF]);
  }

  @override
  void validateImageBytes(Uint8List bytes) {}

  @override
  Future<String> uploadAvatar(Uint8List bytes) async {
    calls.add('uploadAvatar');
    if (uploadError != null) throw uploadError!;
    return 'https://example.com/avatars/u1/profile.jpg?v=1';
  }

  @override
  Future<void> deleteAvatar() async {
    calls.add('deleteAvatar');
  }
}

Profile _testProfile({String? avatarUrl}) => Profile(
  id: 'u1',
  fullName: 'Aditi Sharma',
  avatarUrl: avatarUrl,
  timezone: 'Asia/Kolkata',
  createdAt: DateTime(2026, 1, 15),
  studentCode: 'MP-1042',
  bio: 'Preparing for JEE 2027.',
  mobile: '9876543210',
  examTargets: const ['JEE'],
);

void main() {
  Widget host(Widget child) {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, _) => child),
        GoRoute(
          path: '/profile/avatar',
          builder: (_, state) {
            final params = state.uri.queryParameters;
            return AvatarViewerScreen(
              avatarUrl: params['url'],
              initials: params['initials'] ?? '?',
            );
          },
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  tearDown(() {
    ProfileService.setProfileForTesting(null);
  });

  group('Loaded view mode', () {
    testWidgets('shows the profile name, email, phone, bio, and student code', (
      tester,
    ) async {
      ProfileService.setProfileForTesting(_testProfile());
      final controller = ProfileController(avatarService: _FakeAvatarService());
      await tester.pumpWidget(
        host(
          ProfileScreen(
            controller: controller,
            currentUserEmail: () => 'aditi@example.com',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aditi Sharma'), findsWidgets); // header + info tile
      expect(find.text('aditi@example.com'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Preparing for JEE 2027.'), findsOneWidget);
      expect(find.text('MP-1042'), findsOneWidget);
    });

    testWidgets(
      'no avatar set: shows the initials avatar, not a broken image',
      (tester) async {
        ProfileService.setProfileForTesting(_testProfile());
        final controller = ProfileController(
          avatarService: _FakeAvatarService(),
        );
        await tester.pumpWidget(
          host(
            ProfileScreen(
              controller: controller,
              currentUserEmail: () => 'a@x.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('profile_avatar_initials')),
          findsOneWidget,
        );
      },
    );

    testWidgets('empty optional fields show a placeholder, not blank/crash', (
      tester,
    ) async {
      ProfileService.setProfileForTesting(
        Profile(
          id: 'u2',
          fullName: 'New User',
          timezone: 'Asia/Kolkata',
          createdAt: DateTime(2026, 1, 1),
          bio: '',
          mobile: '',
          examTargets: const [],
        ),
      );
      final controller = ProfileController(avatarService: _FakeAvatarService());
      await tester.pumpWidget(
        host(
          ProfileScreen(controller: controller, currentUserEmail: () => null),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not set'), findsNWidgets(2)); // phone + bio
      expect(find.text('—'), findsWidgets); // email placeholder
    });
  });

  group('Edit mode', () {
    testWidgets(
      'tapping the edit icon shows editable fields with current values pre-filled',
      (tester) async {
        ProfileService.setProfileForTesting(_testProfile());
        final controller = ProfileController(
          avatarService: _FakeAvatarService(),
        );
        await tester.pumpWidget(
          host(
            ProfileScreen(
              controller: controller,
              currentUserEmail: () => 'a@x.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('profile_edit_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('profile_edit_name')), findsOneWidget);
        final nameField = tester.widget<TextFormField>(
          find.byKey(const Key('profile_edit_name')),
        );
        expect(nameField.controller!.text, 'Aditi Sharma');
      },
    );

    testWidgets('cancel restores the original values and exits edit mode', (
      tester,
    ) async {
      ProfileService.setProfileForTesting(_testProfile());
      final controller = ProfileController(avatarService: _FakeAvatarService());
      await tester.pumpWidget(
        host(
          ProfileScreen(
            controller: controller,
            currentUserEmail: () => 'a@x.com',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_edit_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('profile_edit_name')),
        'Changed Name',
      );
      await tester.ensureVisible(
        find.byKey(const Key('profile_cancel_button')),
      );
      await tester.tap(find.byKey(const Key('profile_cancel_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('profile_edit_name')),
        findsNothing,
      ); // back to view mode
      expect(find.text('Aditi Sharma'), findsWidgets); // unchanged
      expect(find.text('Changed Name'), findsNothing);
    });

    testWidgets(
      'saving an invalid (empty) name shows a validation error, no crash',
      (tester) async {
        ProfileService.setProfileForTesting(_testProfile());
        final controller = ProfileController(
          avatarService: _FakeAvatarService(),
        );
        await tester.pumpWidget(
          host(
            ProfileScreen(
              controller: controller,
              currentUserEmail: () => 'a@x.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('profile_edit_button')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('profile_edit_name')), '');
        await tester.ensureVisible(
          find.byKey(const Key('profile_save_button')),
        );
        await tester.tap(find.byKey(const Key('profile_save_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('profile_save_error')), findsOneWidget);
      },
    );

    testWidgets(
      'saving valid data without a live backend fails gracefully, not a crash',
      (tester) async {
        ProfileService.setProfileForTesting(_testProfile());
        final controller = ProfileController(
          avatarService: _FakeAvatarService(),
        );
        await tester.pumpWidget(
          host(
            ProfileScreen(
              controller: controller,
              currentUserEmail: () => 'a@x.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('profile_edit_button')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('profile_save_button')),
        );
        await tester.tap(find.byKey(const Key('profile_save_button')));
        await tester.pumpAndSettle();

        // No Supabase in this test environment -> the save must fail
        // visibly, not throw out of the widget tree.
        expect(find.byKey(const Key('profile_save_error')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Tap to view', () {
    testWidgets('tapping the avatar opens the full-screen viewer', (
      tester,
    ) async {
      ProfileService.setProfileForTesting(_testProfile());
      final controller = ProfileController(avatarService: _FakeAvatarService());
      await tester.pumpWidget(
        host(
          ProfileScreen(
            controller: controller,
            currentUserEmail: () => 'a@x.com',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('avatar_viewer_default')),
        findsOneWidget,
      ); // no photo set
      expect(find.byKey(const Key('avatar_viewer_close')), findsOneWidget);
    });

    testWidgets('closing the viewer returns to the profile screen', (
      tester,
    ) async {
      ProfileService.setProfileForTesting(_testProfile());
      final controller = ProfileController(avatarService: _FakeAvatarService());
      await tester.pumpWidget(
        host(
          ProfileScreen(
            controller: controller,
            currentUserEmail: () => 'a@x.com',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avatar_viewer_close')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('profile_edit_button')),
        findsOneWidget,
      ); // back on the profile screen
    });
  });

  group('Photo actions sheet', () {
    testWidgets(
      'the edit badge opens gallery/camera/(no remove without a photo) options',
      (tester) async {
        ProfileService.setProfileForTesting(_testProfile()); // no avatarUrl
        final controller = ProfileController(
          avatarService: _FakeAvatarService(),
        );
        await tester.pumpWidget(
          host(
            ProfileScreen(
              controller: controller,
              currentUserEmail: () => 'a@x.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('profile_avatar_edit_badge')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('profile_photo_action_gallery')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('profile_photo_action_camera')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('profile_photo_action_remove')),
          findsNothing,
        ); // nothing to remove
      },
    );

    testWidgets('remove option appears once a photo exists', (tester) async {
      ProfileService.setProfileForTesting(
        _testProfile(avatarUrl: 'https://example.com/a.jpg'),
      );
      final controller = ProfileController(avatarService: _FakeAvatarService());
      await tester.pumpWidget(
        host(
          ProfileScreen(
            controller: controller,
            currentUserEmail: () => 'a@x.com',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profile_avatar_edit_badge')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('profile_photo_action_remove')),
        findsOneWidget,
      );
    });

    testWidgets(
      'choosing gallery without a live backend fails gracefully (upload denied, no crash)',
      (tester) async {
        ProfileService.setProfileForTesting(_testProfile());
        final fake = _FakeAvatarService();
        final controller = ProfileController(avatarService: fake);
        await tester.pumpWidget(
          host(
            ProfileScreen(
              controller: controller,
              currentUserEmail: () => 'a@x.com',
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('profile_avatar_edit_badge')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('profile_photo_action_gallery')));
        await tester.pumpAndSettle();

        expect(fake.calls, contains('pickFromGallery'));
        expect(
          fake.calls,
          contains('uploadAvatar'),
        ); // storage layer succeeded (fake)…
        // …but the profiles.avatar_url DB write has no live Supabase here, so
        // the overall action must fail visibly, not crash.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders Golden Verified Tick for owner with 👑 Official Founder tooltip',
      (tester) async {
        final ownerProfile = Profile(
          id: 'owner1',
          fullName: 'Raunak Kumar',
          timezone: 'Asia/Kolkata',
          createdAt: DateTime(2026, 1, 1),
          bio: 'Founder of My Preparation.',
          mobile: '9999999999',
          examTargets: const ['GATE'],
          appRole: AppRole.owner,
        );
        ProfileService.setProfileForTesting(ownerProfile);
        final controller = ProfileController(
          avatarService: _FakeAvatarService(),
        );
        await tester.pumpWidget(
          host(
            ProfileScreen(
              controller: controller,
              currentUserEmail: () => 'founder@myprep.app',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final goldenTickFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Icon &&
              widget.icon == Icons.verified_rounded &&
              widget.color == const Color(0xFFF59E0B),
        );
        expect(goldenTickFinder, findsOneWidget);
        expect(find.byTooltip('👑 Official Founder'), findsOneWidget);
      },
    );

    testWidgets('renders Blue Verified Tick for verified scholar', (
      tester,
    ) async {
      final scholarProfile = Profile(
        id: 's1',
        fullName: 'Scholar Student',
        timezone: 'Asia/Kolkata',
        createdAt: DateTime(2026, 1, 1),
        bio: 'Scholar student.',
        mobile: '9888888888',
        examTargets: const ['JEE'],
        appRole: AppRole.aspirant,
        verifiedBadge: true,
      );
      ProfileService.setProfileForTesting(scholarProfile);
      final controller = ProfileController(avatarService: _FakeAvatarService());
      await tester.pumpWidget(
        host(
          ProfileScreen(
            controller: controller,
            currentUserEmail: () => 'scholar@myprep.app',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final blueTickFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon == Icons.verified_rounded &&
            widget.color == const Color(0xFF2563EB),
      );
      expect(blueTickFinder, findsWidgets);
    });
  });
}
