// rpc_generate_results(p_test_id) — LIVE return contract (2026-09-16):
//   {batch_id, test_id, status, reports_done, reports_total, errors, reused}
// The RPC JSON is the authoritative batch state; the client never falls back
// to SELECTing public.result_batches (its policy hides standalone owners' rows).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/result_batch.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/features/test/data/result_repository.dart';
import 'package:my_praperation/features/test/state/test_detail_controller.dart';

import 'fakes.dart';

Map<String, dynamic> _rpc({
  String status = 'completed',
  int done = 3,
  int total = 3,
  int errors = 0,
  bool reused = false,
}) =>
    {
      'batch_id': 'b-1',
      'test_id': 't-1',
      'status': status,
      'reports_done': done,
      'reports_total': total,
      'errors': errors,
      'reused': reused,
    };

void main() {
  group('ResultBatch.fromRpcJson / batchFromRpcResponse', () {
    test('parses the real completed shape (batch_id → id)', () {
      final b = SupabaseResultRepository.batchFromRpcResponse(_rpc());
      expect(b.id, 'b-1');
      expect(b.testId, 't-1');
      expect(b.status, BatchStatus.completed);
      expect(b.reportsDone, 3);
      expect(b.reportsTotal, 3);
      expect(b.errors, 0);
      expect(b.hasErrors, isFalse);
      expect(b.reused, isFalse);
      expect(b.isTerminal, isTrue);
      expect(b.canTrigger, isTrue);
      // Row-only fields are not invented.
      expect(b.requestedBy, isNull);
      expect(b.totals, isNull);
      expect(b.createdAt, isNull);
      expect(b.completedAt, isNull);
    });

    test('reused: true is preserved', () {
      final b = SupabaseResultRepository.batchFromRpcResponse(_rpc(reused: true));
      expect(b.reused, isTrue);
      expect(b.status, BatchStatus.completed);
    });

    test('partially_completed with errors is a valid (non-failed) outcome', () {
      final b = SupabaseResultRepository.batchFromRpcResponse(
          _rpc(status: 'partially_completed', done: 2, total: 3, errors: 1));
      expect(b.status, BatchStatus.partiallyCompleted);
      expect(b.isPartiallyCompleted, isTrue);
      expect(b.isFailed, isFalse);
      expect(b.errors, 1);
      expect(b.hasErrors, isTrue);
      expect(b.canTrigger, isTrue, reason: 'may be re-requested; server decides');
    });

    test('failed / processing map correctly and processing blocks re-trigger', () {
      expect(SupabaseResultRepository.batchFromRpcResponse(_rpc(status: 'failed')).isFailed, isTrue);
      final p = SupabaseResultRepository.batchFromRpcResponse(_rpc(status: 'processing', done: 1));
      expect(p.isProcessing, isTrue);
      expect(p.canTrigger, isFalse);
    });

    test('a one-element list wrapper is tolerated', () {
      final b = SupabaseResultRepository.batchFromRpcResponse([_rpc()]);
      expect(b.id, 'b-1');
    });

    test('REGRESSION: no batch_id → error, never a table fallback', () {
      // Old row shape (id instead of batch_id) must not be silently accepted.
      expect(
        () => SupabaseResultRepository.batchFromRpcResponse({'id': 'row-1', 'status': 'completed'}),
        throwsA(isA<DataError>()),
      );
      expect(() => SupabaseResultRepository.batchFromRpcResponse(null), throwsA(isA<DataError>()));
      expect(() => SupabaseResultRepository.batchFromRpcResponse('ok'), throwsA(isA<DataError>()));
    });
  });

  group('TestDetailController + generateResults', () {
    TestDetailController make(FakeResultRepository results) => TestDetailController(
          testId: 't-1',
          tests: FakeTestRepository()
            ..rows['t-1'] = const Test(
              id: 't-1', createdBy: 'u-1', title: 'T', status: TestStatus.completed,
              testMode: 'self',
            ),
          questions: FakeQuestionRepository(),
          attempts: FakeAttemptRepository(),
          results: results,
          currentUserId: () => 'u-1',
          clock: () => DateTime(2026, 9, 16),
        );

    test('standalone Self owner: no result_batches read on open; RPC JSON drives state',
        () async {
      final results = FakeResultRepository()..rpcResponse = _rpc();
      final c = make(results);
      await c.load();

      expect(results.calls, isEmpty, reason: 'no SELECT/read on load');
      expect(c.latestBatch, isNull);
      expect(c.canGenerateResults, isTrue);

      final b = await c.generateResults();
      expect(results.calls, ['generate:t-1']);
      expect(b.id, 'b-1');
      expect(c.latestBatch?.reportsDone, 3);
      expect(c.canGenerateResults, isTrue, reason: 'completed batch may be re-requested (idempotent)');
    });

    test('an in-progress (reused) batch blocks repeated generation', () async {
      final results = FakeResultRepository()
        ..rpcResponse = _rpc(status: 'processing', done: 1, total: 3, reused: true);
      final c = make(results);
      await c.load();
      final b = await c.generateResults();
      expect(b.reused, isTrue);
      expect(b.isProcessing, isTrue);
      expect(c.canGenerateResults, isFalse);
    });

    test('unexpected RPC response surfaces as an error, not a null batch', () async {
      final results = FakeResultRepository()..rpcResponse = {'message': 'ok'};
      final c = make(results);
      await c.load();
      await expectLater(c.generateResults(), throwsA(isA<DataError>()));
      expect(c.latestBatch, isNull);
      expect(c.isBusy, isFalse);
    });
  });
}
