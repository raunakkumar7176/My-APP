import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/services/test_service.dart';

void main() {
  group('TestService.mapErrorMessage', () {
    test('maps permission denied error', () {
      expect(
        TestService.mapErrorMessage('permission denied for table tests'),
        'You do not have permission to perform this action.',
      );
    });

    test('maps not found error', () {
      expect(
        TestService.mapErrorMessage('record not found'),
        'Test not found.',
      );
    });

    test('maps network error', () {
      expect(
        TestService.mapErrorMessage('network timeout'),
        'Network error. Please check your connection and try again.',
      );
    });

    test('maps unknown error to generic message', () {
      expect(
        TestService.mapErrorMessage('something unexpected happened'),
        'Something went wrong. Please try again.',
      );
    });
  });

  group('TestService.mapPublishError', () {
    test('maps no approved question error to an approval instruction', () {
      // A draft may have questions that are all still pending review; telling
      // the user to "add a question" hid the real cause (seen on device).
      expect(
        TestService.mapPublishError('no approved question found'),
        'Approve all questions before publishing '
        '(Edit Test → Review → Approve).',
      );
      expect(
        TestService.mapPublishError(
            'VALIDATION_ERROR: Test must have at least one approved question to publish'),
        'Approve all questions before publishing '
        '(Edit Test → Review → Approve).',
      );
    });

    test('maps no questions error', () {
      expect(
        TestService.mapPublishError('no questions exist for this test'),
        'Add at least one question before publishing.',
      );
    });

    test('maps permission error', () {
      expect(
        TestService.mapPublishError('permission denied for publish'),
        'You do not have permission to publish this test.',
      );
    });

    test('maps group selection error', () {
      expect(
        TestService.mapPublishError('group selection is required'),
        'Select a group for Group Test mode.',
      );
    });

    test('maps duration error', () {
      expect(
        TestService.mapPublishError('invalid duration provided'),
        'Enter a valid duration for the test.',
      );
    });

    test('maps duplicate ordinal error', () {
      expect(
        TestService.mapPublishError('duplicate question ordinal'),
        'Fix duplicate question numbers before publishing.',
      );
    });

    test('maps syllabus error', () {
      expect(
        TestService.mapPublishError('invalid syllabus node reference'),
        'Fix syllabus references before publishing.',
      );
    });

    test('maps session error', () {
      expect(
        TestService.mapPublishError('session expired unauthorized'),
        'Your session has expired. Please log in again.',
      );
    });

    test('maps network error', () {
      expect(
        TestService.mapPublishError('network timeout'),
        'Network error. Please check your connection and try again.',
      );
    });

    test('maps unknown error to generic message', () {
      expect(
        TestService.mapPublishError('something unexpected'),
        'Failed to publish test. Please try again.',
      );
    });
  });

  group('TestService.mapStartAttemptError', () {
    test('maps not started error', () {
      expect(
        TestService.mapStartAttemptError('test has not started yet'),
        'This test has not started yet.',
      );
    });

    test('maps ended error', () {
      expect(
        TestService.mapStartAttemptError('test has ended'),
        'This test has ended.',
      );
    });

    test('maps expired error', () {
      expect(
        TestService.mapStartAttemptError('test expired'),
        'This test has ended.',
      );
    });

    test('maps cancelled error', () {
      expect(
        TestService.mapStartAttemptError('test cancelled'),
        'This test has been cancelled.',
      );
    });

    test('maps already attempted error', () {
      expect(
        TestService.mapStartAttemptError('already have an active attempt'),
        'You already have an active attempt for this test.',
      );
    });

    test('maps max participant error', () {
      expect(
        TestService.mapStartAttemptError('max participants reached'),
        'This test has reached its maximum number of participants.',
      );
    });

    test('maps permission error', () {
      expect(
        TestService.mapStartAttemptError('permission denied'),
        'You cannot access this test.',
      );
    });

    test('maps session error', () {
      expect(
        TestService.mapStartAttemptError('session unauthorized auth'),
        'Your session has expired. Please log in again.',
      );
    });

    test('maps network error', () {
      expect(
        TestService.mapStartAttemptError('network timeout'),
        'Network error. Please check your connection and try again.',
      );
    });

    test('maps unknown error to generic message', () {
      expect(
        TestService.mapStartAttemptError('something unexpected'),
        'Failed to start test. Please try again.',
      );
    });
  });

  group('TestService.buildCreateTestParams', () {
    test('builds params with required fields only', () {
      final params = TestService.buildCreateTestParams(title: 'My Test');
      expect(params['p_title'], 'My Test');
      expect(params.containsKey('p_description'), false);
      expect(params.containsKey('p_duration_sec'), false);
    });

    test('builds params with all optional fields', () {
      final now = DateTime.now();
      final params = TestService.buildCreateTestParams(
        title: 'My Test',
        description: 'A test',
        durationSec: 3600,
        marksPerQuestion: 4.0,
        negativeMarks: 1.0,
        testMode: 'self',
        creationMethod: 'manual',
        groupId: 'group-1',
        startsAt: now,
        endsAt: now.add(const Duration(hours: 1)),
        maxParticipants: 50,
        allowLateJoin: true,
        config: {'shuffle': true},
        settings: {'show_answers': false},
        accessCode: 'abc123',
        joinCode: 'xyz789',
      );
      expect(params['p_title'], 'My Test');
      expect(params['p_description'], 'A test');
      expect(params['p_duration_sec'], 3600);
      expect(params['p_marks_per_question'], 4.0);
      expect(params['p_negative_marks'], 1.0);
      expect(params['p_test_mode'], 'self');
      expect(params['p_creation_method'], 'manual');
      expect(params['p_group_id'], 'group-1');
      expect(params['p_starts_at'], isNotNull);
      expect(params['p_ends_at'], isNotNull);
      expect(params['p_max_participants'], 50);
      expect(params['p_allow_late_join'], true);
      expect(params['p_config'], {'shuffle': true});
      expect(params['p_settings'], {'show_answers': false});
      expect(params['p_access_code'], 'abc123');
      expect(params['p_join_code'], 'xyz789');
    });
  });

  group('TestService.buildUpdateTestParams', () {
    test('builds params with test ID', () {
      final params = TestService.buildUpdateTestParams(
        testId: 'test-123',
        title: 'Updated',
      );
      expect(params['p_test_id'], 'test-123');
      expect(params['p_title'], 'Updated');
    });

    test('builds params with only provided optional fields', () {
      final params = TestService.buildUpdateTestParams(
        testId: 'test-123',
        durationSec: 1800,
      );
      expect(params['p_test_id'], 'test-123');
      expect(params['p_duration_sec'], 1800);
      expect(params.containsKey('p_title'), false);
      expect(params.containsKey('p_description'), false);
    });
  });

  group('TestService.buildPublishTestParams', () {
    test('builds params with test ID', () {
      final params = TestService.buildPublishTestParams('test-123');
      expect(params['p_test_id'], 'test-123');
    });
  });
}
