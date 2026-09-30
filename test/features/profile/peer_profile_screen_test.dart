// Peer ("Student") Profile screen — widget tests for what ANOTHER student
// sees when their profile is opened from the Followers / Following list, a
// group roster or a shared link.
//
// No fake Supabase client exists anywhere in this project's test infra (see
// profile_screen_test's header), so the target profile is handed to the
// screen exactly the way the router hands it over:
// ProfileController(targetUserId: ..., initialProfile: ...). What is pinned
// down here is the screen's CONTRACT:
//   * every number/name/code on screen comes from that profile row —
//     nothing hardcoded, nothing invented;
//   * private fields (phone, date of birth) and the viewer's own email are
//     never rendered on someone else's card;
//   * the Follow button appears for a peer and never for yourself.
//
// The live follow COUNTS a real navigation would refresh come from
// ProfileService.fetchFollowCounts (COUNT(*) over user_follows) inside
// ProfileController.load; with initialProfile already supplied the
// controller skips that round trip, so the values below are the ones the
// card renders verbatim.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/models/profile.dart';
import 'package:my_praperation/core/services/profile_service.dart';
import 'package:my_praperation/features/profile/profile_screen.dart';
import 'package:my_praperation/features/profile/state/profile_controller.dart';

Profile _peerProfile() => Profile(
  id: 'peer-uuid-0000',
  fullName: 'Aarav Mehta',
  avatarUrl: null,
  timezone: 'Asia/Kolkata',
  createdAt: DateTime(2025, 4, 12),
  studentCode: 'MP-83921',
  bio: 'Aspiring civil services officer.',
  mobile: '9876543210',
  examTargets: const ['UPSC CSE', 'SSC CGL'],
  totalPoints: 4820,
  weeklyPoints: 310,
  dateOfBirth: DateTime(2004, 6, 9),
  followersCount: 128,
  followingCount: 64,
);

Widget _host(Widget child) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [GoRoute(path: '/start', builder: (_, _) => child)],
  );
  return MediaQuery(
    data: const MediaQueryData(size: Size(390, 844)),
    child: MaterialApp.router(routerConfig: router),
  );
}

Widget _peerScreen({required Profile peer}) => ProfileScreen(
  userId: peer.id,
  controller: ProfileController(targetUserId: peer.id, initialProfile: peer),
  currentUserEmail: () => 'viewer@example.com',
);

void main() {
  tearDown(() => ProfileService.setProfileForTesting(null));

  group('Peer profile (another student)', () {
    testWidgets('renders the student card from real profile data', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_peerScreen(peer: _peerProfile())));
      await tester.pumpAndSettle();

      // Full name: header + info card, and the initials avatar (no photo).
      expect(find.text('Aarav Mehta'), findsNWidgets(2));
      expect(find.byKey(const Key('profile_avatar_initials')), findsOneWidget);

      // Student code chip (header) — exactly once, never duplicated.
      expect(find.text('MP-83921'), findsOneWidget);

      // Real dynamic counts and points, straight off the row.
      expect(find.text('128'), findsOneWidget); // followers
      expect(find.text('64'), findsOneWidget); // following
      expect(find.text('4820'), findsOneWidget); // study points
      expect(find.text('Followers'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Study Points'), findsOneWidget);

      // Target exams + bio + join date from the card.
      expect(find.text('UPSC CSE'), findsOneWidget);
      expect(find.text('SSC CGL'), findsOneWidget);
      expect(find.text('Aspiring civil services officer.'), findsOneWidget);
      expect(find.text('Apr 12, 2025'), findsOneWidget);

      // A peer gets an active follow action.
      expect(find.text('+ Follow'), findsOneWidget);
    });

    testWidgets('never leaks phone, date of birth or the viewer email', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_peerScreen(peer: _peerProfile())));
      await tester.pumpAndSettle();

      expect(find.text('9876543210'), findsNothing); // peer's phone
      expect(find.text('Jun 9, 2004'), findsNothing); // peer's DOB
      expect(find.text('viewer@example.com'), findsNothing); // viewer's email
      expect(find.text('Email'), findsNothing);
      expect(find.text('Phone'), findsNothing);
      expect(find.text('Date of Birth'), findsNothing);
    });
  });

  group('Own profile', () {
    testWidgets('keeps its private fields and hides the follow button', (
      tester,
    ) async {
      ProfileService.setProfileForTesting(_peerProfile());

      await tester.pumpWidget(
        _host(
          ProfileScreen(
            controller: ProfileController(
              targetUserId: null,
              initialProfile: _peerProfile(),
            ),
            currentUserEmail: () => 'viewer@example.com',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Still my own editable, private card...
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Jun 9, 2004'), findsOneWidget);
      expect(find.text('viewer@example.com'), findsOneWidget);
      expect(find.text('Not set'), findsNothing); // bio is filled in

      // ...and no way to follow myself.
      expect(find.text('+ Follow'), findsNothing);
      expect(find.text('Following ✓'), findsNothing);
    });
  });
}
