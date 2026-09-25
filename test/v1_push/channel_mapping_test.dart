// Push — Android notification channel routing. Pure, no Firebase/Supabase.
// Every live `notif_category` value (see core/models/app_notification.dart)
// must resolve to exactly one of the 6 channels, explicitly — not a prefix
// guess (an earlier prefix-based draft of the server-side twin of this
// mis-routed TEST_COMPLETED; this test pins the correct, explicit mapping
// so that class of bug can't come back silently).

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/app_notification.dart';
import 'package:my_praperation/core/services/push_notification_service.dart';

void main() {
  group('channelForCategory — every live category maps to exactly one channel', () {
    final expected = <String, PushChannel>{
      'GROUP_MESSAGE': PushChannel.group,
      'GROUP_ANNOUNCEMENT': PushChannel.group,
      'GROUP_JOIN': PushChannel.group,
      'GROUP_TEST_ASSIGNED': PushChannel.group,
      'GROUP_TEST_REMINDER': PushChannel.group,
      'GROUP_JOIN_REQUEST': PushChannel.group,
      'JOIN_ACCEPTED': PushChannel.group,
      'JOIN_REJECTED': PushChannel.group,
      'ROLE_CHANGED': PushChannel.group,
      'MEMBER_REMOVED': PushChannel.group,
      'TEST_REMINDER': PushChannel.testExam,
      'TEST_LIVE': PushChannel.testExam,
      'TEST_INVITATION': PushChannel.testExam,
      'TEST_SCHEDULED': PushChannel.testExam,
      'TEST_STARTING_SOON': PushChannel.testExam,
      'TEST_STARTED': PushChannel.testExam,
      'TEST_ENDED': PushChannel.testExam,
      'TEST_COMPLETED': PushChannel.testResult,
      'RESULTS_AVAILABLE': PushChannel.testResult,
      'LEADERBOARD_UPDATED': PushChannel.testResult,
      'REPORT_READY': PushChannel.testResult,
      'ROUTINE_REMINDER': PushChannel.routineReminder,
      'ROUTINE_DUE': PushChannel.routineReminder,
      'ROUTINE_MISSED': PushChannel.routineReminder,
      'ROUTINE_COMPLETED': PushChannel.routineReminder,
      'STREAK_MILESTONE': PushChannel.routineReminder,
      'SYSTEM_NOTIFICATION': PushChannel.importantSystem,
      'CONTENT_REVIEW_RESULT': PushChannel.general,
    };

    for (final entry in expected.entries) {
      test('${entry.key} -> ${entry.value.id}', () {
        expect(channelForCategory(entry.key), entry.value);
      });
    }

    test('every NotificationCategory enum value has an explicit mapping entry above', () {
      for (final cat in NotificationCategory.values) {
        if (cat == NotificationCategory.unknown) continue;
        expect(
          expected.containsKey(cat.label),
          isTrue,
          reason: '${cat.label} is a live category with no channel mapping test coverage',
        );
      }
    });

    test('an unrecognized category falls back to general, never crashes', () {
      expect(channelForCategory('SOMETHING_NEW'), PushChannel.general);
    });

    test('mapping is case-insensitive', () {
      expect(channelForCategory('test_live'), PushChannel.testExam);
    });

    test('TEST_COMPLETED specifically resolves to test_result, not test_exam (regression pin)', () {
      expect(channelForCategory('TEST_COMPLETED'), PushChannel.testResult);
    });
  });

  group('PushChannel', () {
    test('all 6 channels have distinct, stable ids', () {
      final ids = PushChannel.values.map((c) => c.id).toSet();
      expect(ids.length, 6);
      expect(ids, {
        'test_exam',
        'test_result',
        'group',
        'routine_reminder',
        'general',
        'important_system',
      });
    });

    test('important_system uses the platform Max importance (Phase 9: critical alerts)', () {
      expect(PushChannel.importantSystem.importance, Importance.max);
    });
  });
}
