// Push tap -> deep link. Pure tests for
// NotificationDeepLinkHandler.resolvePath — the context-free half used by
// PushNotificationService for a system push tap (cold start / background),
// where no BuildContext exists yet. No Firebase, no widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/app_notification.dart';
import 'package:my_praperation/features/notifications/state/notification_deep_link_handler.dart';

AppNotification _notif({
  String category = 'GENERAL',
  Map<String, dynamic> data = const {},
}) {
  return AppNotification(
    id: 'n1',
    userId: 'u1',
    category: category,
    title: 't',
    body: 'b',
    data: data,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('resolvePath — server-provided deep_link takes priority', () {
    test('a valid deep_link is used as-is', () {
      final n = _notif(data: {'deep_link': '/tests/abc'});
      expect(NotificationDeepLinkHandler.resolvePath(n), '/tests/abc');
    });

    test('a deep_link with a query string is rejected, falls through', () {
      final n = _notif(
        category: 'RESULTS_AVAILABLE',
        data: {'deep_link': '/tests/abc?x=1', 'test_id': 'abc'},
      );
      expect(NotificationDeepLinkHandler.resolvePath(n), '/tests/abc');
    });

    test('a deep_link to an unknown prefix is rejected, falls through', () {
      final n = _notif(data: {'deep_link': '/evil/path'});
      expect(NotificationDeepLinkHandler.resolvePath(n), '/notifications');
    });

    test('an external URL as deep_link is rejected, falls through', () {
      final n = _notif(data: {'deep_link': 'https://example.com'});
      expect(NotificationDeepLinkHandler.resolvePath(n), '/notifications');
    });
  });

  group('resolvePath — fallback from test/routine/group ids', () {
    test('RESULTS_AVAILABLE with a test_id -> the test screen', () {
      final n = _notif(category: 'RESULTS_AVAILABLE', data: {'test_id': 't1'});
      expect(NotificationDeepLinkHandler.resolvePath(n), '/tests/t1');
    });

    test('a test_id with a group_id (not results) -> the group tests list', () {
      final n = _notif(category: 'TEST_LIVE', data: {'test_id': 't1', 'group_id': 'g1'});
      expect(NotificationDeepLinkHandler.resolvePath(n), '/groups/g1/tests');
    });

    test('a routine_id -> the routine screen', () {
      final n = _notif(category: 'ROUTINE_REMINDER', data: {'routine_id': 'r1'});
      expect(NotificationDeepLinkHandler.resolvePath(n), '/routine/r1');
    });

    test('a group_id with type group_message -> the group screen', () {
      final n = _notif(data: {'group_id': 'g1', 'type': 'group_message'});
      expect(NotificationDeepLinkHandler.resolvePath(n), '/groups/g1');
    });
  });

  group('resolvePath — category-only fallback (no ids at all)', () {
    test('TEST_REMINDER -> /tests', () {
      expect(NotificationDeepLinkHandler.resolvePath(_notif(category: 'TEST_REMINDER')), '/tests');
    });

    test('ROUTINE_DUE -> /routine', () {
      expect(NotificationDeepLinkHandler.resolvePath(_notif(category: 'ROUTINE_DUE')), '/routine');
    });

    test('LEADERBOARD_UPDATED with no test id -> /tests', () {
      expect(NotificationDeepLinkHandler.resolvePath(_notif(category: 'LEADERBOARD_UPDATED')), '/tests');
    });

    test('an unrecognized category with nothing else -> the notification center', () {
      expect(NotificationDeepLinkHandler.resolvePath(_notif(category: 'SOMETHING_NEW')), '/notifications');
    });
  });
}
