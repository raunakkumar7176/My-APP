// Group Hub — foreground push toast dedupe. A GROUP_MESSAGE push for a
// group the user is already viewing would otherwise show a toast on top
// of a chat bubble realtime just rendered. GroupHubController tells
// PushNotificationService which group is on screen; the actual "skip the
// toast" branch lives in PushNotificationService._handleForegroundMessage
// (untestable here — it needs a live FCM RemoteMessage/plugin, which this
// project has no mocking infra for) — these tests cover the client-side
// wiring this task actually added: setting/clearing `activeGroupId`.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/services/push_notification_service.dart';
import 'package:my_praperation/features/group/state/group_hub_controller.dart';

import 'fakes.dart';

void main() {
  setUp(() => PushNotificationService.instance.activeGroupId = null);
  tearDown(() => PushNotificationService.instance.activeGroupId = null);

  test('opening a group hub marks it as the active group for push dedupe', () async {
    final repo = InMemoryGroupRepository(currentUser: 'u-me')
      ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me');
    final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-me');

    await c.load();

    expect(PushNotificationService.instance.activeGroupId, 'g-1');
    c.dispose();
  });

  test('disposing the hub clears the active group', () async {
    final repo = InMemoryGroupRepository(currentUser: 'u-me')
      ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me');
    final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-me');
    await c.load();
    expect(PushNotificationService.instance.activeGroupId, 'g-1');

    c.dispose();

    expect(PushNotificationService.instance.activeGroupId, isNull);
  });

  test('disposing a hub never clears a DIFFERENT group that became active meanwhile', () async {
    final repo = InMemoryGroupRepository(currentUser: 'u-me')
      ..seed(id: 'g-1', name: 'Physics', ownerId: 'u-me')
      ..seed(id: 'g-2', name: 'Chemistry', ownerId: 'u-me');
    final c1 = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-me');
    await c1.load();

    final c2 = GroupHubController(groupId: 'g-2', repository: repo, currentUserId: 'u-me');
    await c2.load();
    expect(PushNotificationService.instance.activeGroupId, 'g-2');

    c1.dispose(); // stale/already-navigated-away controller
    expect(PushNotificationService.instance.activeGroupId, 'g-2');

    c2.dispose();
    expect(PushNotificationService.instance.activeGroupId, isNull);
  });

  test('a group the caller cannot access never becomes the active group', () async {
    final repo = InMemoryGroupRepository(currentUser: 'u-me')
      ..seed(id: 'g-1', name: 'Not mine', ownerId: 'u-owner');
    final c = GroupHubController(groupId: 'g-1', repository: repo, currentUserId: 'u-me');

    await c.load();

    expect(c.accessDenied, isTrue);
    expect(PushNotificationService.instance.activeGroupId, isNull);
    c.dispose();
  });
}
