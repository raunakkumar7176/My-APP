import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/models/result_batch.dart';

void main() {
  group('ResultBatch model', () {
    test('parses batch status correctly', () {
      final batch = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'pending',
      });
      expect(batch.status, BatchStatus.pending);
      expect(batch.isPending, true);
    });

    test('parses all status values', () {
      final statuses = {
        'pending': BatchStatus.pending,
        'processing': BatchStatus.processing,
        'partially_completed': BatchStatus.partiallyCompleted,
        'completed': BatchStatus.completed,
        'failed': BatchStatus.failed,
      };

      for (final entry in statuses.entries) {
        final batch = ResultBatch.fromJson({
          'id': 'batch-1',
          'test_id': 'test-1',
          'status': entry.key,
        });
        expect(batch.status, entry.value, reason: 'Failed for status: ${entry.key}');
      }
    });

    test('defaults to unknown for invalid status', () {
      final batch = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'invalid_status',
      });
      expect(batch.status, BatchStatus.unknown);
    });

    test('progress calculates correctly', () {
      final batch = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'processing',
        'reports_done': 5,
        'reports_total': 10,
      });
      expect(batch.progress, 0.5);
    });

    test('progress returns 0 for zero total', () {
      final batch = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'pending',
        'reports_done': 0,
        'reports_total': 0,
      });
      expect(batch.progress, 0);
    });

    test('isTerminal is true for completed and failed', () {
      final completed = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'completed',
      });
      expect(completed.isTerminal, true);

      final failed = ResultBatch.fromJson({
        'id': 'batch-2',
        'test_id': 'test-1',
        'status': 'failed',
      });
      expect(failed.isTerminal, true);
    });

    test('isTerminal is false for non-terminal statuses', () {
      final pending = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'pending',
      });
      expect(pending.isTerminal, false);

      final processing = ResultBatch.fromJson({
        'id': 'batch-2',
        'test_id': 'test-1',
        'status': 'processing',
      });
      expect(processing.isTerminal, false);
    });

    test('canTrigger is true when not pending or processing', () {
      final completed = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'completed',
      });
      expect(completed.canTrigger, true);

      final failed = ResultBatch.fromJson({
        'id': 'batch-2',
        'test_id': 'test-1',
        'status': 'failed',
      });
      expect(failed.canTrigger, true);
    });

    test('canTrigger is false when pending or processing', () {
      final pending = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'pending',
      });
      expect(pending.canTrigger, false);

      final processing = ResultBatch.fromJson({
        'id': 'batch-2',
        'test_id': 'test-1',
        'status': 'processing',
      });
      expect(processing.canTrigger, false);
    });

    test('equality is based on id, testId, status', () {
      final batch1 = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'pending',
      });
      final batch2 = ResultBatch.fromJson({
        'id': 'batch-1',
        'test_id': 'test-1',
        'status': 'pending',
      });
      expect(batch1, batch2);

      final batch3 = ResultBatch.fromJson({
        'id': 'batch-2',
        'test_id': 'test-1',
        'status': 'pending',
      });
      expect(batch1 == batch3, false);
    });
  });
}
