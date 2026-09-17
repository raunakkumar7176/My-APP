// In-memory repository fakes for controller tests. No Supabase.

import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/result_batch.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/core/models/test_syllabus.dart';
import 'package:my_praperation/features/test/data/attempt_repository.dart';
import 'package:my_praperation/features/test/data/group_repository.dart';
import 'package:my_praperation/features/test/data/question_repository.dart';
import 'package:my_praperation/features/test/data/result_repository.dart';
import 'package:my_praperation/features/test/data/test_repository.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';

class FakeTestRepository implements TestRepository {
  final Map<String, Test> rows = {};
  final Map<String, Set<String>> syllabus = {};
  final List<String> calls = [];
  int createCount = 0;
  int nextId = 1;
  String currentUser = 'u-1';

  /// Throw on the Nth create (1-based) to simulate failure.
  Object? failCreateWith;

  @override
  Future<Test?> getById(String testId) async {
    calls.add('getById:$testId');
    // Mirrors the live query: `.eq('is_soft_deleted', false)`.
    final t = rows[testId];
    return t == null || t.isSoftDeleted ? null : t;
  }

  @override
  Future<List<Test>> listAccessible({int limit = 100}) async {
    calls.add('listAccessible');
    return rows.values.where((t) => !t.isSoftDeleted).toList();
  }

  @override
  Future<List<Test>> listMyDrafts({int limit = 50}) async {
    calls.add('listMyDrafts');
    return rows.values
        .where((t) =>
            t.status == TestStatus.draft && t.createdBy == currentUser && !t.isSoftDeleted)
        .toList();
  }

  @override
  Future<Test> create(TestWriteInput input) async {
    calls.add('create');
    if (failCreateWith != null) throw failCreateWith!;
    createCount++;
    final id = 't-${nextId++}';
    final t = Test(
      id: id,
      createdBy: currentUser,
      title: input.title,
      description: input.description,
      status: TestStatus.draft,
      testMode: input.testMode,
      groupId: input.groupId,
      durationSec: input.durationSec,
      startsAt: input.startsAt,
      endsAt: input.endsAt,
      allowLateJoin: input.allowLateJoin ?? false,
      joinCode: input.joinCode,
      settings: input.settings,
      config: input.config,
    );
    rows[id] = t;
    return t;
  }

  @override
  Future<void> update(String testId, TestWriteInput input) async {
    calls.add('update:$testId');
    final t = rows[testId]!;
    rows[testId] = Test(
      id: t.id,
      createdBy: t.createdBy,
      title: input.title,
      description: input.description,
      status: t.status,
      testMode: t.testMode,
      groupId: t.groupId,
      durationSec: input.durationSec,
      startsAt: input.startsAt,
      endsAt: input.endsAt,
      allowLateJoin: input.allowLateJoin ?? t.allowLateJoin,
      joinCode: input.joinCode ?? t.joinCode,
      settings: input.settings ?? t.settings,
      config: input.config ?? t.config,
    );
  }

  /// Mirrors `rpc_delete_test`: creator + draft + not already deleted, else
  /// the server error codes the mapper knows. [failDeleteWith] simulates a
  /// backend/network rejection.
  Object? failDeleteWith;

  @override
  Future<void> deleteDraft(String testId) async {
    calls.add('delete:$testId');
    if (failDeleteWith != null) throw failDeleteWith!;
    final t = rows[testId];
    if (t == null) throw const DataError(message: 'Test not found.');
    if (t.createdBy != currentUser) {
      throw const DataError(message: 'You do not have permission to perform this action.');
    }
    if (t.isSoftDeleted) throw const DataError(message: 'This test has already been deleted.');
    if (t.status != TestStatus.draft) {
      throw const DataError(message: 'Only draft tests can be deleted.');
    }
    rows[testId] = Test(
      id: t.id, createdBy: t.createdBy, title: t.title, status: t.status,
      testMode: t.testMode, durationSec: t.durationSec, settings: t.settings,
      isSoftDeleted: true, deletedAt: DateTime(2026, 9, 16),
    );
  }

  @override
  Future<void> publish(String testId) async {
    calls.add('publish:$testId');
    final t = rows[testId]!;
    rows[testId] = Test(
      id: t.id,
      createdBy: t.createdBy,
      title: t.title,
      status: TestStatus.published,
      testMode: t.testMode,
      settings: t.settings,
    );
  }

  @override
  Future<List<TestSyllabus>> syllabusFor(String testId) async => [
        for (final n in syllabus[testId] ?? const <String>{})
          TestSyllabus(id: '', testId: testId, syllabusNodeId: n, createdAt: DateTime(2026)),
      ];

  @override
  Future<void> addSyllabus(String testId, String nodeId) async {
    calls.add('addSyllabus:$nodeId');
    (syllabus[testId] ??= {}).add(nodeId);
  }

  @override
  Future<void> removeSyllabus(String testId, String nodeId) async {
    calls.add('removeSyllabus:$nodeId');
    syllabus[testId]?.remove(nodeId);
  }
}

class FakeQuestionRepository implements QuestionRepository {
  final Map<String, List<Question>> byTest = {};
  final List<String> calls = [];
  int nextId = 1;

  /// Question texts whose create should fail once.
  final Set<String> failOnce = {};

  /// Ids whose approve should fail.
  final Set<String> failApprove = {};

  @override
  Future<List<Question>> safeQuestions(String testId, {String? accessCode}) async {
    calls.add('safe:$testId');
    return List.of(byTest[testId] ?? const []);
  }

  @override
  Future<String> create(String testId, QuestionDraft draft) async {
    calls.add('create:${draft.questionText}');
    if (failOnce.remove(draft.questionText)) {
      throw const DataError(message: 'create failed');
    }
    // Mirrors rpc_create_question (R4_QUESTION_OPTION_GUARD): >= 4 options,
    // correct_option within bounds.
    if (draft.options.length < 4) {
      throw const DataError(message: 'at least 4 options are required.');
    }
    final k = draft.correctOptionIndex;
    if (k == null || k < 0 || k >= draft.options.length) {
      throw const DataError(message: 'correct_option must be a valid option index.');
    }
    final id = 'q-${nextId++}';
    (byTest[testId] ??= []).add(Question(
      id: id,
      testId: testId,
      ordinal: byTest[testId]!.length + 1,
      question: draft.questionText,
      options: [
        for (final o in draft.options) QuestionOption(id: o.id ?? 'o', text: o.text),
      ],
      difficulty: draft.difficulty,
      marks: draft.marks,
      status: 'pending_review',
      questionType: draft.questionType,
    ));
    return id;
  }

  @override
  Future<void> update(String questionId, QuestionDraft draft) async {
    calls.add('update:$questionId');
    // Mirrors rpc_update_question: the FINAL option set (supplied, else
    // stored) must have >= 4; correct_option checked against that set.
    Question? existing;
    for (final list in byTest.values) {
      for (final q in list) {
        if (q.id == questionId) existing = q;
      }
    }
    if (existing == null) throw const DataError(message: 'Question not found.');
    final finalOptions = draft.options.isNotEmpty
        ? draft.options.map((o) => o.text).toList()
        : (existing.options ?? const []).map((o) => o.text).toList();
    if (finalOptions.length < 4) {
      throw const DataError(message: 'at least 4 options are required.');
    }
    final k = draft.correctOptionIndex;
    if (k != null && (k < 0 || k >= finalOptions.length)) {
      throw const DataError(message: 'correct_option must be a valid option index.');
    }
  }

  @override
  Future<void> approve(String questionId) async {
    calls.add('approve:$questionId');
    if (failApprove.contains(questionId)) {
      throw const DataError(message: 'approve failed');
    }
    for (final list in byTest.values) {
      final i = list.indexWhere((q) => q.id == questionId);
      if (i != -1) list[i] = list[i].copyWith(status: 'approved');
    }
  }

  @override
  Future<void> delete(String questionId) async {
    calls.add('delete:$questionId');
    for (final list in byTest.values) {
      list.removeWhere((q) => q.id == questionId);
    }
  }
}

class FakeGroupRepository implements GroupRepository {
  List<Group> groups = const [];
  @override
  Future<List<Group>> myGroups() async => groups;
}

/// Mirrors the live start path (`_fn_start_attempt_core` + the re-attempt
/// policy): resume in_progress first; otherwise count this user's attempts
/// on the test, read `settings.allow_reattempt` / `max_attempts` from
/// [tests], raise REATTEMPT_LIMIT_REACHED / ATTEMPT_ALREADY_COMPLETED, and
/// allocate MAX(attempt_number)+1. [next] / [failStartWith] keep the old
/// canned behaviour for tests that do not care about the policy.
class FakeAttemptRepository implements AttemptRepository {
  final List<String> calls = [];
  Attempt? next;
  Result? submitResult;
  Object? failStartWith;

  /// Server-side state: every attempt row, all users.
  final List<Attempt> rows = [];

  /// Test settings the "server" reads (test id → settings jsonb).
  final Map<String, Map<String, dynamic>?> testSettings = {};
  String currentUser = 'u-1';
  int _seq = 100;

  @override
  Future<StartedAttempt> start(String testId, {bool reattempt = false}) async {
    calls.add('start:$testId${reattempt ? ':reattempt' : ''}');
    if (failStartWith != null) throw failStartWith!;
    if (next != null && rows.isEmpty) return (attempt: next!, testTitle: null);
    return (attempt: _serverStart(testId, reattempt: reattempt), testTitle: null);
  }

  @override
  Future<StartedAttempt> startByCode(String code, {bool reattempt = false}) async {
    calls.add('code:$code${reattempt ? ':reattempt' : ''}');
    if (failStartWith != null) throw failStartWith!;
    if (next != null && rows.isEmpty) return (attempt: next!, testTitle: 'Coded');
    return (attempt: _serverStart('t-coded', reattempt: reattempt), testTitle: 'Coded');
  }

  @override
  Future<List<Attempt>> mine(String testId) async {
    calls.add('mine:$testId');
    return [
      for (final a in rows)
        if (a.testId == testId && a.userId == currentUser) a,
    ]..sort((x, y) => x.attemptNumber.compareTo(y.attemptNumber));
  }

  Attempt _serverStart(String testId, {required bool reattempt}) {
    final own = [for (final a in rows) if (a.testId == testId && a.userId == currentUser) a];
    for (final a in own) {
      if (a.status == AttemptStatus.inProgress) return a; // resume
    }
    final settings = testSettings[testId];
    final allow = settings?['allow_reattempt'] == true;
    final max = allow ? ((settings?['max_attempts'] as int?) ?? 1).clamp(1, 1 << 30) : 1;
    if (own.length >= max) {
      throw const DataError(message: 'You have used all attempts allowed for this test.');
    }
    if (own.isNotEmpty && !reattempt) {
      throw const DataError(
          message: 'You have already completed this test. Use Re-attempt to try again.');
    }
    final number = own.fold<int>(0, (m, a) => a.attemptNumber > m ? a.attemptNumber : m) + 1;
    final a = Attempt(
      id: 'a-${_seq++}',
      testId: testId,
      userId: currentUser,
      status: AttemptStatus.inProgress,
      startedAt: DateTime(2026, 9, 16, 10, number),
      deadlineAt: DateTime(2026, 9, 16, 11, number),
      attemptNumber: number,
    );
    rows.add(a);
    return a;
  }

  /// Simulates the server closing an attempt (submit → scored).
  void complete(String attemptId, {AttemptStatus status = AttemptStatus.scored}) {
    final i = rows.indexWhere((a) => a.id == attemptId);
    if (i == -1) return;
    final a = rows[i];
    rows[i] = Attempt(
      id: a.id, testId: a.testId, userId: a.userId, status: status,
      startedAt: a.startedAt, deadlineAt: a.deadlineAt, attemptNumber: a.attemptNumber,
      submittedAt: a.startedAt.add(const Duration(minutes: 20)),
    );
  }

  @override
  Future<Result> submit(String attemptId, {required bool timedOut}) async {
    calls.add('submit:$attemptId:$timedOut');
    complete(attemptId, status: timedOut ? AttemptStatus.autoSubmitted : AttemptStatus.scored);
    return submitResult ??
        Result(
          id: 'r-1',
          attemptId: attemptId,
          testId: 't-1',
          userId: 'u-1',
          score: 3,
          maxScore: 5,
        );
  }
}

class FakeResultRepository implements ResultRepository {
  final Map<String, Result> byAttemptId = {};
  final List<Result> mine = [];
  ResultBatch? batch;
  final List<String> calls = [];

  @override
  Future<Result?> byAttempt(String attemptId) async {
    calls.add('byAttempt:$attemptId');
    return byAttemptId[attemptId];
  }

  @override
  Future<List<Result>> mineForTest(String testId) async => mine;

  /// Raw jsonb the fake RPC returns (live shape). Parsed exactly like the
  /// real repository so controller tests exercise the same mapping.
  Map<String, dynamic>? rpcResponse;

  @override
  Future<ResultBatch> generateResults(String testId) async {
    calls.add('generate:$testId');
    if (batch != null) return batch!;
    return SupabaseResultRepository.batchFromRpcResponse(rpcResponse);
  }
}
