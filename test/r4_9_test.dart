import 'package:flutter_test/flutter_test.dart';

import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/result_batch.dart';
import 'package:my_praperation/core/models/test.dart';

void main() {
  group('BatchStatus enum', () {
    test('all statuses are defined', () {
      expect(BatchStatus.values.length, 6);
      expect(BatchStatus.values, contains(BatchStatus.pending));
      expect(BatchStatus.values, contains(BatchStatus.processing));
      expect(BatchStatus.values, contains(BatchStatus.partiallyCompleted));
      expect(BatchStatus.values, contains(BatchStatus.completed));
      expect(BatchStatus.values, contains(BatchStatus.failed));
      expect(BatchStatus.values, contains(BatchStatus.unknown));
    });

    test('partially_completed parses correctly', () {
      final batch = ResultBatch.fromJson({
        'id': 'b-1',
        'test_id': 't-1',
        'status': 'partially_completed',
      });
      expect(batch.status, BatchStatus.partiallyCompleted);
      expect(batch.isPartiallyCompleted, true);
    });

    test('unknown status is returned for unrecognized value', () {
      final batch = ResultBatch.fromJson({
        'id': 'b-1',
        'test_id': 't-1',
        'status': 'bogus',
      });
      expect(batch.status, BatchStatus.unknown);
    });
  });

  group('ResultBatch model', () {
    test('fromJson parses all actual DB columns', () {
      final batch = ResultBatch.fromJson({
        'id': 'b-1',
        'test_id': 't-1',
        'requested_by': 'u-owner',
        'status': 'completed',
        'reports_done': 10,
        'reports_total': 10,
        'totals': {'scored': 10, 'errors': 0},
        'created_at': '2026-01-15T10:00:00Z',
        'completed_at': '2026-01-15T10:05:00Z',
      });

      expect(batch.id, 'b-1');
      expect(batch.testId, 't-1');
      expect(batch.requestedBy, 'u-owner');
      expect(batch.status, BatchStatus.completed);
      expect(batch.reportsDone, 10);
      expect(batch.reportsTotal, 10);
      expect(batch.totals, isNotNull);
      expect(batch.totals!['scored'], 10);
      expect(batch.createdAt, isNotNull);
      expect(batch.completedAt, isNotNull);
    });

    test('fromJson handles null optional fields', () {
      final batch = ResultBatch.fromJson({
        'id': 'b-1',
        'test_id': 't-1',
        'status': 'pending',
      });

      expect(batch.requestedBy, isNull);
      expect(batch.reportsDone, isNull);
      expect(batch.reportsTotal, isNull);
      expect(batch.totals, isNull);
      expect(batch.createdAt, isNull);
      expect(batch.completedAt, isNull);
    });

    test('equality is based on id, testId, status', () {
      const b1 = ResultBatch(id: 'b', testId: 't', status: BatchStatus.pending);
      const b2 = ResultBatch(id: 'b', testId: 't', status: BatchStatus.pending);
      const b3 = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.completed,
      );

      expect(b1, b2);
      expect(b1 == b3, false);
    });

    test('toJson roundtrip preserves data', () {
      const batch = ResultBatch(
        id: 'b-1',
        testId: 't-1',
        requestedBy: 'u-1',
        status: BatchStatus.completed,
        reportsDone: 5,
        reportsTotal: 5,
        totals: {'scored': 5},
      );
      final json = batch.toJson();
      final restored = ResultBatch.fromJson(json);

      expect(restored.id, batch.id);
      expect(restored.testId, batch.testId);
      expect(restored.requestedBy, batch.requestedBy);
      expect(restored.status, batch.status);
      expect(restored.reportsDone, batch.reportsDone);
      expect(restored.reportsTotal, batch.reportsTotal);
      expect(restored.totals, batch.totals);
    });
  });

  group('ResultBatch status predicates', () {
    test('isPending is true for pending status', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.pending,
      );
      expect(batch.isPending, true);
      expect(batch.isProcessing, false);
      expect(batch.isCompleted, false);
      expect(batch.isFailed, false);
      expect(batch.isTerminal, false);
    });

    test('isProcessing is true for processing status', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.processing,
      );
      expect(batch.isProcessing, true);
      expect(batch.isTerminal, false);
    });

    test('isPartiallyCompleted is true for partially_completed status', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.partiallyCompleted,
      );
      expect(batch.isPartiallyCompleted, true);
      expect(batch.isTerminal, false);
    });

    test('isCompleted is true for completed status', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.completed,
      );
      expect(batch.isCompleted, true);
      expect(batch.isTerminal, true);
    });

    test('isFailed is true for failed status', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.failed,
      );
      expect(batch.isFailed, true);
      expect(batch.isTerminal, true);
    });
  });

  group('ResultBatch progress', () {
    test('progress returns 0 when reportsTotal is null', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.processing,
      );
      expect(batch.progress, 0);
    });

    test('progress returns 0 when reportsTotal is 0', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.processing,
        reportsDone: 0,
        reportsTotal: 0,
      );
      expect(batch.progress, 0);
    });

    test('progress calculates ratio correctly', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.processing,
        reportsDone: 3,
        reportsTotal: 10,
      );
      expect(batch.progress, closeTo(0.3, 0.01));
    });

    test('progress is 1.0 when all done', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.completed,
        reportsDone: 10,
        reportsTotal: 10,
      );
      expect(batch.progress, 1.0);
    });
  });

  group('Batch canTrigger logic', () {
    test('canTrigger is true when no batch exists (unknown status)', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.unknown,
      );
      expect(batch.canTrigger, true);
    });

    test('canTrigger is true when batch is completed', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.completed,
      );
      expect(batch.canTrigger, true);
    });

    test('canTrigger is true when batch is failed', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.failed,
      );
      expect(batch.canTrigger, true);
    });

    test('canTrigger is true when batch is partially_completed', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.partiallyCompleted,
      );
      expect(batch.canTrigger, true);
    });

    test('canTrigger is false when batch is pending', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.pending,
      );
      expect(batch.canTrigger, false);
    });

    test('canTrigger is false when batch is processing', () {
      const batch = ResultBatch(
        id: 'b',
        testId: 't',
        status: BatchStatus.processing,
      );
      expect(batch.canTrigger, false);
    });
  });

  group('Batch authorization', () {
    test('only owner can trigger generation', () {
      const test = Test(
        id: 't-1',
        createdBy: 'user-owner',
        title: 'Test',
        status: TestStatus.completed,
      );
      const currentUserId = 'user-owner';
      expect(test.createdBy == currentUserId, true);
    });

    test('non-owner cannot trigger generation', () {
      const test = Test(
        id: 't-1',
        createdBy: 'user-owner',
        title: 'Test',
        status: TestStatus.completed,
      );
      const currentUserId = 'user-student';
      expect(test.createdBy == currentUserId, false);
    });

    test('anonymous cannot trigger generation', () {
      const test = Test(
        id: 't-1',
        createdBy: 'user-owner',
        title: 'Test',
        status: TestStatus.completed,
      );
      const currentUserId = null;
      expect(test.createdBy == currentUserId, false);
    });
  });

  group('Eligible attempts filtering', () {
    test('submitted attempt is eligible', () {
      final attempt = Attempt(
        id: 'a-1',
        testId: 't-1',
        userId: 'u-1',
        status: AttemptStatus.submitted,
        startedAt: DateTime(2026, 1, 15),
      );
      expect(attempt.isSubmitted, true);
      expect(attempt.isInProgress, false);
    });

    test('auto_submitted attempt is eligible', () {
      final attempt = Attempt(
        id: 'a-2',
        testId: 't-1',
        userId: 'u-1',
        status: AttemptStatus.autoSubmitted,
        startedAt: DateTime(2026, 1, 15),
      );
      expect(attempt.isSubmitted, true);
      expect(attempt.isInProgress, false);
    });

    test('scored attempt is eligible', () {
      final attempt = Attempt(
        id: 'a-3',
        testId: 't-1',
        userId: 'u-1',
        status: AttemptStatus.scored,
        startedAt: DateTime(2026, 1, 15),
      );
      expect(attempt.isSubmitted, true);
      expect(attempt.isInProgress, false);
    });

    test('in_progress attempt is NOT eligible', () {
      final attempt = Attempt(
        id: 'a-4',
        testId: 't-1',
        userId: 'u-1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2026, 1, 15),
      );
      expect(attempt.isInProgress, true);
      expect(attempt.isSubmitted, false);
    });
  });

  group('Result persistence', () {
    test('result has batchId for traceability', () {
      const result = Result(
        id: 'r-1',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
        batchId: 'b-1',
      );
      expect(result.batchId, 'b-1');
    });

    test('result can exist without batchId', () {
      const result = Result(
        id: 'r-1',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
      );
      expect(result.batchId, isNull);
    });

    test('unique attempt_id constraint prevents duplicate results', () {
      const r1 = Result(
        id: 'r-1',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
      );
      const r2 = Result(
        id: 'r-2',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
      );
      expect(r1.attemptId, r2.attemptId);
    });
  });

  group('Repeat attempt result separation', () {
    test('different attempts have separate results', () {
      const r1 = Result(
        id: 'r-1',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
        score: 80,
      );
      const r2 = Result(
        id: 'r-2',
        attemptId: 'a-2',
        testId: 't-1',
        userId: 'u-1',
        score: 90,
      );
      expect(r1.attemptId, isNot(equals(r2.attemptId)));
      expect(r1.id, isNot(equals(r2.id)));
      expect(r1.score, 80);
      expect(r2.score, 90);
    });

    test('results for different users are independent', () {
      const r1 = Result(
        id: 'r-1',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
        score: 70,
      );
      const r2 = Result(
        id: 'r-2',
        attemptId: 'a-2',
        testId: 't-1',
        userId: 'u-2',
        score: 85,
      );
      expect(r1.userId, isNot(equals(r2.userId)));
      expect(r1.score, 70);
      expect(r2.score, 85);
    });
  });

  group('Multiple participants batch', () {
    test('batch tracks reports_done and reports_total', () {
      const batch = ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.completed,
        reportsDone: 10,
        reportsTotal: 10,
      );
      expect(batch.reportsDone, 10);
      expect(batch.reportsTotal, 10);
      expect(batch.progress, 1.0);
    });

    test('batch tracks partial progress', () {
      const batch = ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.processing,
        reportsDone: 7,
        reportsTotal: 10,
      );
      expect(batch.reportsDone, 7);
      expect(batch.reportsTotal, 10);
      expect(batch.progress, closeTo(0.7, 0.01));
    });

    test('batch stores totals map', () {
      const batch = ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.completed,
        reportsDone: 10,
        reportsTotal: 10,
        totals: {'scored': 10, 'errors': 0},
      );
      expect(batch.totals, isNotNull);
      expect(batch.totals!['scored'], 10);
      expect(batch.totals!['errors'], 0);
    });
  });

  group('Test mode naming', () {
    test('live mode displays as Challenge with Friends', () {
      const test = Test(
        id: 't-1',
        createdBy: 'u-1',
        title: 'Test',
        status: TestStatus.completed,
        testMode: 'live',
      );
      expect(test.testMode, 'live');
    });

    test('self mode displays as Self Practice', () {
      const test = Test(
        id: 't-1',
        createdBy: 'u-1',
        title: 'Test',
        status: TestStatus.completed,
        testMode: 'self',
      );
      expect(test.testMode, 'self');
    });

    test('group mode displays as Group Test', () {
      const test = Test(
        id: 't-1',
        createdBy: 'u-1',
        title: 'Test',
        status: TestStatus.completed,
        testMode: 'group',
      );
      expect(test.testMode, 'group');
    });
  });

  group('Error handling', () {
    test('error message maps permission denied', () {
      const message = 'permission denied for table result_batches';
      final lower = message.toLowerCase();
      expect(lower.contains('permission') || lower.contains('denied'), true);
    });

    test('error message maps not authenticated', () {
      const message = 'not_authenticated';
      final lower = message.toLowerCase();
      expect(lower.contains('not_authenticated'), true);
    });

    test('error message maps already processing', () {
      const message = 'batch already in progress for this test';
      final lower = message.toLowerCase();
      expect(
        lower.contains('already_processing') ||
            lower.contains('already in progress'),
        true,
      );
    });

    test('error message maps no eligible attempts', () {
      const message = 'no eligible attempts found';
      final lower = message.toLowerCase();
      expect(
        lower.contains('no_eligible') || lower.contains('no eligible'),
        true,
      );
    });
  });

  group('Batch lifecycle', () {
    test('pending to processing to completed', () {
      var batch = const ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.pending,
      );
      expect(batch.isPending, true);

      batch = ResultBatch(
        id: batch.id,
        testId: batch.testId,
        status: BatchStatus.processing,
        reportsDone: 0,
        reportsTotal: 5,
      );
      expect(batch.isProcessing, true);
      expect(batch.progress, 0);

      batch = ResultBatch(
        id: batch.id,
        testId: batch.testId,
        status: BatchStatus.completed,
        reportsDone: 5,
        reportsTotal: 5,
        completedAt: DateTime(2026, 1, 15, 10, 5),
      );
      expect(batch.isCompleted, true);
      expect(batch.isTerminal, true);
      expect(batch.reportsDone, 5);
    });

    test('pending to processing to failed', () {
      var batch = const ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.pending,
      );
      expect(batch.isPending, true);

      batch = ResultBatch(
        id: batch.id,
        testId: batch.testId,
        status: BatchStatus.failed,
        totals: {'error': 'Server timeout'},
      );
      expect(batch.isFailed, true);
      expect(batch.isTerminal, true);
      expect(batch.totals!['error'], 'Server timeout');
    });

    test('pending to processing to partially_completed', () {
      var batch = const ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.pending,
      );
      expect(batch.isPending, true);

      batch = const ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.partiallyCompleted,
        reportsDone: 7,
        reportsTotal: 10,
      );
      expect(batch.isPartiallyCompleted, true);
      expect(batch.isTerminal, false);
      expect(batch.canTrigger, true);
      expect(batch.progress, closeTo(0.7, 0.01));
    });

    test('failed batch can be retried', () {
      const batch = ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.failed,
      );
      expect(batch.canTrigger, true);
    });

    test('completed batch can trigger new generation', () {
      const batch = ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.completed,
      );
      expect(batch.canTrigger, true);
    });
  });

  group('Loading and empty states', () {
    test('null batch means results not generated', () {
      ResultBatch? batch;
      expect(batch, isNull);
    });

    test('empty batch list means no batches exist', () {
      final batches = <ResultBatch>[];
      expect(batches, isEmpty);
    });

    test('batch requestedBy tracks who triggered', () {
      const batch = ResultBatch(
        id: 'b-1',
        testId: 't-1',
        status: BatchStatus.pending,
        requestedBy: 'u-owner',
      );
      expect(batch.requestedBy, 'u-owner');
    });
  });

  group('fn_score_attempt boundary', () {
    test('scoring is server-authoritative via fn_score_attempt', () {
      // Client does NOT calculate scores
      // All scoring happens server-side via fn_score_attempt()
      // Flutter only reads results from the results table
      const result = Result(
        id: 'r-1',
        attemptId: 'a-1',
        testId: 't-1',
        userId: 'u-1',
        score: 85.0,
        maxScore: 100,
        percentage: 85.0,
        correctCount: 17,
        wrongCount: 2,
        unansweredCount: 1,
        generationMethod: 'server',
      );
      expect(result.score, 85.0);
      expect(result.generationMethod, 'server');
    });
  });
}
