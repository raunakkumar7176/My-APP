import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/profile/widgets/profile_avatar.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('no photo (default avatar): shows initials, not a broken-image icon', (tester) async {
    await tester.pumpWidget(host(const ProfileAvatar(initials: 'AS')));
    expect(find.byKey(const Key('profile_avatar_initials')), findsOneWidget);
    expect(find.byKey(const Key('profile_avatar_photo')), findsNothing);
    expect(find.text('AS'), findsOneWidget);
  });

  testWidgets('with a photo url: renders the photo key, not the initials key', (tester) async {
    await tester.pumpWidget(host(
      const ProfileAvatar(initials: 'AS', avatarUrl: 'https://example.com/a.jpg'),
    ));
    expect(find.byKey(const Key('profile_avatar_photo')), findsOneWidget);
    expect(find.byKey(const Key('profile_avatar_initials')), findsNothing);
  });

  testWidgets('an empty-string avatarUrl is treated as no photo', (tester) async {
    await tester.pumpWidget(host(const ProfileAvatar(initials: 'AS', avatarUrl: '')));
    expect(find.byKey(const Key('profile_avatar_initials')), findsOneWidget);
  });

  testWidgets('tapping the avatar invokes onTap (tap-to-view)', (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(
      ProfileAvatar(initials: 'AS', onTap: () => tapped = true),
    ));
    await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
    expect(tapped, isTrue);
  });

  testWidgets('the edit badge is hidden when onEditTap is null (view-only contexts)', (tester) async {
    await tester.pumpWidget(host(const ProfileAvatar(initials: 'AS')));
    expect(find.byKey(const Key('profile_avatar_edit_badge')), findsNothing);
  });

  testWidgets('the edit badge invokes onEditTap, independent of onTap', (tester) async {
    var viewed = false;
    var edited = false;
    await tester.pumpWidget(host(
      ProfileAvatar(
        initials: 'AS',
        onTap: () => viewed = true,
        onEditTap: () => edited = true,
      ),
    ));
    await tester.tap(find.byKey(const Key('profile_avatar_edit_badge')));
    expect(edited, isTrue);
    expect(viewed, isFalse);
  });

  testWidgets('busy=true shows a progress overlay and disables the edit badge', (tester) async {
    var edited = false;
    await tester.pumpWidget(host(
      ProfileAvatar(initials: 'AS', busy: true, onEditTap: () => edited = true),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile_avatar_edit_badge')));
    expect(edited, isFalse);
  });
}
