// R4.3 — repository contract tests (pure parsing / param building; the
// Supabase client is never touched here).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/answer.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/features/test/data/answer_repository.dart';
import 'package:my_praperation/features/test/data/attempt_repository.dart';
import 'package:my_praperation/features/test/data/question_repository.dart';
import 'package:my_praperation/features/test/data/test_repository.dart';
import 'package:my_praperation/features/test/domain/backend_mapping.dart';
import 'package:my_praperation/features/test/domain/test_kind.dart';

void main() {
  group('TestWriteInput params', () {
    test(
      'create: Practice sends test_mode=self + settings.test_kind; omits nulls',
      () {
        final b = BackendMapping.toBackend(TestKind.practice);
        final p = TestWriteInput(
          title: 'T',
          testMode: b.mode.dbValue,
          settings: BackendMapping.settingsFor(TestKind.practice, null),
          durationSec: 10800,
        ).toCreateParams();
        expect(p['p_test_mode'], 'self');
        expect(p['p_settings'], {'test_kind': 'practice'});
        expect(p['p_creation_method'], 'manual');
        expect(p.containsKey('p_starts_at'), isFalse);
        expect(p.containsKey('p_group_id'), isFalse);
      },
    );

    test('create: Challenge with Friends sends live and no settings; Group sends group', () {
      final live = TestWriteInput(
        title: 'T',
        testMode: BackendMapping.toBackend(TestKind.challengeWithFriends)
            .mode
            .dbValue,
        settings: BackendMapping.settingsFor(
          TestKind.challengeWithFriends,
          null,
        ),
        accessCode: 'ABC',
      ).toCreateParams();
      expect(live['p_test_mode'], 'live');
      expect(live.containsKey('p_settings'), isFalse);
      expect(live['p_access_code'], 'ABC');

      final group = TestWriteInput(
        title: 'T',
        testMode: BackendMapping.toBackend(TestKind.group).mode.dbValue,
        groupId: 'g-1',
      ).toCreateParams();
      expect(group['p_test_mode'], 'group');
      expect(group['p_group_id'], 'g-1');
    });

    test('update: never carries mode/group; keeps settings', () {
      final p = const TestWriteInput(
        title: 'T',
        testMode: 'self',
        groupId: 'g',
        settings: {'test_kind': 'quick', 'keep': 1},
      ).toUpdateParams('t-1');
      expect(p['p_test_id'], 't-1');
      expect(p.containsKey('p_test_mode'), isFalse);
      expect(p.containsKey('p_group_id'), isFalse);
      expect(p['p_settings'], {'test_kind': 'quick', 'keep': 1});
    });
  });

  group('questionTypeToRpc', () {
    test('maps every type to the RPC vocabulary', () {
      expect(questionTypeToRpc(QuestionType.mcqSingle), 'mcq');
      expect(questionTypeToRpc(QuestionType.mcqMultiple), 'mcq');
      expect(questionTypeToRpc(QuestionType.trueFalse), 'tf');
      expect(questionTypeToRpc(QuestionType.integer), 'num');
      expect(questionTypeToRpc(QuestionType.shortAnswer), 'short');
      expect(questionTypeToRpc(null), 'mcq');
    });
  });

  group('SupabaseAttemptRepository.parseStarted', () {
    test('jsonb shape (R4_3): attempt_id/status/deadline/test_title', () {
      final r = SupabaseAttemptRepository.parseStarted({
        'attempt_id': 'a-1',
        'test_id': 't-1',
        'status': 'resumed',
        'started_at': '2026-09-16T10:00:00Z',
        'deadline_at': '2026-09-16T11:00:00Z',
        'attempt_number': 2,
        'test_title': 'Maths',
        'entry_method': 'code',
      });
      expect(r.attempt.id, 'a-1');
      expect(r.attempt.testId, 't-1');
      expect(r.attempt.status, AttemptStatus.inProgress);
      expect(r.attempt.attemptNumber, 2);
      expect(r.attempt.deadlineAt, isNotNull);
      expect(r.testTitle, 'Maths');
    });

    test('row shape (R4_7_6): id/user_id/status', () {
      final r = SupabaseAttemptRepository.parseStarted([
        {
          'id': 'a-2',
          'test_id': 't-1',
          'user_id': 'u-1',
          'status': 'in_progress',
          'started_at': '2026-09-16T10:00:00Z',
          'deadline_at': null,
          'attempt_number': 1,
        },
      ]);
      expect(r.attempt.id, 'a-2');
      expect(r.attempt.userId, 'u-1');
      expect(r.attempt.deadlineAt, isNull);
      expect(r.testTitle, isNull);
    });

    test('rejects unusable shapes instead of fabricating an attempt', () {
      expect(
        () => SupabaseAttemptRepository.parseStarted('a-3'),
        throwsA(isA<DataError>()),
      );
      expect(
        () => SupabaseAttemptRepository.parseStarted({'attempt_id': 'a-3'}),
        throwsA(isA<DataError>()),
      );
      expect(
        () => SupabaseAttemptRepository.parseStarted(null),
        throwsA(isA<DataError>()),
      );
    });
  });

  group(
    'SupabaseAnswerRepository.answerFromRow (single normalization point)',
    () {
      test('repo-DDL naming', () {
        final a = SupabaseAnswerRepository.answerFromRow({
          'attempt_id': 'a',
          'question_id': 'q',
          'selected_option_id': 'opt-b',
          'text_answer': null,
          'is_marked_for_review': true,
          'is_answered': true,
        });
        expect(a.selectedOptionId, 'opt-b');
        expect(a.isMarkedForReview, isTrue);
        expect(a.isAnswered, isTrue);
      });

      test('owner-listed naming (selected_option / marked_for_review)', () {
        final a = SupabaseAnswerRepository.answerFromRow({
          'attempt_id': 'a',
          'question_id': 'q',
          'selected_option': 'opt-c',
          'marked_for_review': false,
          'updated_at': '2026-09-16T10:00:00Z',
        });
        expect(a.selectedOptionId, 'opt-c');
        expect(a.isMarkedForReview, isFalse);
        expect(
          a.isAnswered,
          isTrue,
          reason: 'derived from presence of a value',
        );
      });

      test('empty row is unanswered', () {
        final a = SupabaseAnswerRepository.answerFromRow({
          'attempt_id': 'a',
          'question_id': 'q',
        });
        expect(a.isAnswered, isFalse);
        expect(a.selectedOptionId, isNull);
      });

      test('write payload is unchanged from the historical contract', () {
        const a = Answer(
          attemptId: 'a',
          questionId: 'q',
          selectedOptionId: 'x',
          isAnswered: true,
        );
        expect(a.toJson().keys.toSet(), {
          'attempt_id',
          'question_id',
          'selected_option_id',
          'text_answer',
          'is_marked_for_review',
          'is_answered',
        });
      });
    },
  );
}
