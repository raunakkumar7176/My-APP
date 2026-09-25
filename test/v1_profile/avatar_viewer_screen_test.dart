import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/features/profile/screens/avatar_viewer_screen.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('no avatar: shows the default-avatar state, not a crash or broken image', (tester) async {
    await tester.pumpWidget(host(const AvatarViewerScreen(initials: 'AS')));
    expect(find.byKey(const Key('avatar_viewer_default')), findsOneWidget);
    expect(find.text('No profile photo yet'), findsOneWidget);
    expect(find.text('AS'), findsOneWidget);
  });

  testWidgets('an empty-string avatarUrl is treated the same as no photo', (tester) async {
    await tester.pumpWidget(host(const AvatarViewerScreen(initials: 'AS', avatarUrl: '')));
    expect(find.byKey(const Key('avatar_viewer_default')), findsOneWidget);
  });

  testWidgets('with a photo url: builds the zoomable InteractiveViewer, not the default state', (tester) async {
    await tester.pumpWidget(host(
      const AvatarViewerScreen(initials: 'AS', avatarUrl: 'https://example.com/a.jpg'),
    ));
    expect(find.byKey(const Key('avatar_viewer_default')), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('the close button pops the viewer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AvatarViewerScreen(initials: 'AS')),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('avatar_viewer_default')), findsOneWidget);

    await tester.tap(find.byKey(const Key('avatar_viewer_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('avatar_viewer_default')), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the background is black (dark viewer as required)', (tester) async {
    await tester.pumpWidget(host(const AvatarViewerScreen(initials: 'AS')));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.black);
  });
}
