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
    return rows[testId];
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
        .where((t) => t.status == TestStatus.draft && t.createdBy == currentUser)
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
      settings: input.settings ?? t.settings,
      config: input.config ?? t.config,
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

class FakeAttemptRepository implements AttemptRepository {
  final List<String> calls = [];
  Attempt? next;
  Result? submitResult;
  Object? failStartWith;

  @override
  Future<StartedAttempt> start(String testId) async {
    calls.add('start:$testId');
    if (failStartWith != null) throw failStartWith!;
    return (attempt: next ?? _attempt('a-1', testId), testTitle: null);
  }

  @override
  Future<StartedAttempt> startByCode(String code) async {
    calls.add('code:$code');
    if (failStartWith != null) throw failStartWith!;
    return (attempt: next ?? _attempt('a-2', 't-coded'), testTitle: 'Coded');
  }

  @override
  Future<Result> submit(String attemptId, {required bool timedOut}) async {
    calls.add('submit:$attemptId:$timedOut');
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

  static Attempt _attempt(String id, String testId) => Attempt(
        id: id,
        testId: testId,
        userId: 'u-1',
        status: AttemptStatus.inProgress,
        startedAt: DateTime(2026, 9, 16),
        deadlineAt: DateTime(2026, 9, 16, 1),
      );
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

  @override
  Future<ResultBatch?> latestBatch(String testId) async => batch;

  @override
  Future<ResultBatch?> generateResults(String testId) async {
    calls.add('generate:$testId');
    return batch;
  }
}
