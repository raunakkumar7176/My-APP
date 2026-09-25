// Group Hub redesign — dedicated full-screen Discussion view. It shares
// the Hub's own controller instance (no second subscription / no second
// message fetch), so these are mostly rendering + interaction checks; the
// underlying data logic is already covered by group_chat_test.dart and
// group_realtime_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_praperation/core/models/group_message.dart';
import 'package:my_praperation/features/group/screens/group_discussion_screen.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

GroupHubController _hub(InMemoryGroupRepository repo, {String user = 'u-me'}) =>
    GroupHubController(groupId: 'g-1', repository: repo, currentUserId: user);

InMemoryGroupRepository _repo({String user = 'u-me'}) {
  final repo = InMemoryGroupRepository(currentUser: user)
    ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-owner', members: {'u-me': 'member', 'u-b': 'member'});
  repo.seedMessage(groupId: 'g-1', senderId: 'u-owner', body: 'Welcome all', at: DateTime(2026, 9, 10, 9, 5));
  repo.seedMessage(groupId: 'g-1', senderId: 'u-b', body: 'Hi!', at: DateTime(2026, 9, 10, 9, 6));
  return repo;
}

void main() {
  testWidgets('renders the shared controller\'s already-loaded messages, no second fetch', (tester) async {
    final repo = _repo();
    final c = _hub(repo);
    await c.load();
    final fetchesAfterLoad = repo.calls.where((x) => x.startsWith('messages:')).length;

    await tester.pumpWidget(MaterialApp(home: GroupDiscussionScreen(controller: c)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discussion_message_list')), findsOneWidget);
    expect(find.text('Welcome all'), findsOneWidget);
    expect(find.text('Hi!'), findsOneWidget);
    expect(repo.calls.where((x) => x.startsWith('messages:')).length, fetchesAfterLoad);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('header shows the group name and member count, tap opens settings route', (tester) async {
    final repo = _repo();
    final c = _hub(repo);
    await c.load();

    final router = GoRouter(
      initialLocation: '/groups/g-1',
      routes: [
        GoRoute(
          path: '/groups/:groupId',
          builder: (_, _) => GroupDiscussionScreen(controller: c),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (_, _) => const Scaffold(body: Text('Settings Screen')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discussion_open_info')));
    await tester.pumpAndSettle();
    expect(find.text('Settings Screen'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('typing and sending clears the field and shows the new message', (tester) async {
    final repo = _repo();
    final c = _hub(repo);
    await c.load();

    await tester.pumpWidget(MaterialApp(home: GroupDiscussionScreen(controller: c)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('discussion_message_field')), 'New message');
    await tester.tap(find.byKey(const Key('discussion_send_button')));
    await tester.pumpAndSettle();

    expect(find.text('New message'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('discussion_message_field')));
    expect(field.controller!.text, isEmpty);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('the reconnecting strip appears only while realtime is disconnected', (tester) async {
    final repo = _repo();
    final c = _hub(repo);
    await c.load();

    await tester.pumpWidget(MaterialApp(home: GroupDiscussionScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discussion_reconnecting')), findsNothing);

    repo.simulateConnectionChange('g-1', false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discussion_reconnecting')), findsOneWidget);

    repo.simulateConnectionChange('g-1', true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discussion_reconnecting')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('empty state renders when a group has no messages yet', (tester) async {
    final repo = InMemoryGroupRepository(currentUser: 'u-me')
      ..seed(id: 'g-1', name: 'Empty Group', ownerId: 'u-owner', members: {'u-me': 'member'});
    final c = _hub(repo);
    await c.load();

    await tester.pumpWidget(MaterialApp(home: GroupDiscussionScreen(controller: c)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discussion_empty')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a realtime insert while the screen is open appears without any user action', (tester) async {
    final repo = _repo();
    final c = _hub(repo);
    await c.load();

    await tester.pumpWidget(MaterialApp(home: GroupDiscussionScreen(controller: c)));
    await tester.pumpAndSettle();

    repo.simulateRealtimeInsert(
      'g-1',
      GroupMessage(
        id: 'm-live-1',
        groupId: 'g-1',
        senderId: 'u-b',
        body: 'Live update',
        createdAt: DateTime(2026, 9, 10, 9, 10),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live update'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
