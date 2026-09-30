// In-memory repository fakes for controller tests. No Supabase.

import 'package:my_praperation/core/errors/app_error.dart';
import 'package:my_praperation/core/models/attempt.dart';
import 'package:my_praperation/core/models/group.dart';
import 'package:my_praperation/core/models/question.dart';
import 'package:my_praperation/core/models/question_bank_item.dart';
import 'package:my_praperation/core/models/result.dart';
import 'package:my_praperation/core/models/result_batch.dart';
import 'package:my_praperation/core/models/submit_scorecard.dart';
import 'package:my_praperation/core/models/test.dart';
import 'package:my_praperation/core/models/test_syllabus.dart';
import 'package:my_praperation/features/test/data/attempt_repository.dart';
import 'package:my_praperation/features/test/data/question_bank_repository.dart';
import 'package:my_praperation/features/test/data/question_repository.dart';
import 'package:my_praperation/features/test/data/result_repository.dart';
import 'package:my_praperation/features/group/domain/group_permission.dart';
import 'package:my_praperation/features/group/domain/group_test_results.dart';
import 'package:my_praperation/features/test/data/test_repository.dart';
import 'package:my_praperation/features/test/models/question_draft.dart';

import '../group/fakes.dart';

class FakeTestRepository implements TestRepository {
  final Map<String, Test> rows = {};
  final Map<String, Set<String>> syllabus = {};
  final List<String> calls = [];
  int createCount = 0;
  int nextId = 1;
  String currentUser = 'u-1';

  /// Throw on the Nth create (1-based) to simulate failure.
  Object? failCreateWith;

  /// G10: when attached, the LIVE group policies are mirrored —
  /// `group create test` (INSERT WITH CHECK: created_by = uid, test_mode =
  /// 'group', CREATE_TEST in that group), `member read tests` (SELECT:
  /// member, not soft-deleted) + `creator sees soft-deleted`, and
  /// `fn_soft_delete_test` (creator OR owner OR EDIT_TEST; not live /
  /// scheduled). Without it the old canned behaviour stays.
  InMemoryGroupRepository? groups;

  bool _hasPermission(String groupId, GroupPermission p) =>
      groups?.hasPermission(groupId, p) ?? true;

  bool _isMember(String groupId) =>
      groups?.groups[groupId]?.roles.containsKey(currentUser) ?? true;

  bool _isGroupOwner(String groupId) =>
      groups?.groups[groupId]?.roles[currentUser] == 'owner';

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
        .where(
          (t) =>
              t.status == TestStatus.draft &&
              t.createdBy == currentUser &&
              !t.isSoftDeleted,
        )
        .toList();
  }

  @override
  Future<Test> create(TestWriteInput input) async {
    calls.add('create');
    if (failCreateWith != null) throw failCreateWith!;
    if (groups != null && input.groupId != null) {
      // Live `group create test` policy: the row is refused unless the
      // caller holds CREATE_TEST in exactly that group (owner bypass inside
      // fn_has_permission). A forged group_id fails here.
      if (input.testMode != 'group' ||
          !_hasPermission(input.groupId!, GroupPermission.createTest)) {
        throw const DataError(
          message: 'You do not have permission to perform this action.',
        );
      }
    }
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
      // rpc_update_test has no shuffle parameter — the column is owned by
      // setShuffleQuestions below and must survive an unrelated update.
      shuffleQuestions: t.shuffleQuestions,
    );
  }

  /// Mirrors `rpc_set_test_shuffle_questions` (draft-only column writer).
  /// [failShuffleWith] simulates the RPC being unavailable (e.g. the
  /// migration not applied yet), which the creation controller must treat
  /// as non-fatal.
  Object? failShuffleWith;
  final List<String> shuffleCalls = [];

  @override
  Future<void> setShuffleQuestions(String testId, bool shuffle) async {
    shuffleCalls.add('$testId:$shuffle');
    if (failShuffleWith != null) throw failShuffleWith!;
    final t = rows[testId];
    if (t == null) throw const DataError(message: 'Test not found.');
    if (t.status != TestStatus.draft) {
      throw const DataError(
        message: 'shuffle_questions can only be changed while the test is a draft',
      );
    }
    rows[testId] = _withShuffle(t, shuffle);
  }

  /// Full-field copy of [t] with only `shuffleQuestions` replaced: the fake
  /// row must survive a column-only write with EVERY other field intact
  /// (dropping `endsAt` here once silently broke a schedule assertion).
  static Test _withShuffle(Test t, bool shuffle) => Test(
    id: t.id,
    createdBy: t.createdBy,
    title: t.title,
    description: t.description,
    instructions: t.instructions,
    subjectId: t.subjectId,
    classLevel: t.classLevel,
    status: t.status,
    durationSec: t.durationSec,
    marksPerQuestion: t.marksPerQuestion,
    negativeMarks: t.negativeMarks,
    startsAt: t.startsAt,
    endsAt: t.endsAt,
    groupId: t.groupId,
    accessCode: t.accessCode,
    joinCode: t.joinCode,
    testMode: t.testMode,
    maxParticipants: t.maxParticipants,
    allowLateJoin: t.allowLateJoin,
    isSoftDeleted: t.isSoftDeleted,
    deletedAt: t.deletedAt,
    archivedAt: t.archivedAt,
    tags: t.tags,
    language: t.language,
    difficulty: t.difficulty,
    totalMarks: t.totalMarks,
    passingMarks: t.passingMarks,
    totalQuestions: t.totalQuestions,
    shuffleQuestions: shuffle,
    showAnswersAfter: t.showAnswersAfter,
    isPublic: t.isPublic,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
    config: t.config,
    settings: t.settings,
  );

  /// Mirrors `rpc_delete_test`: creator + draft + not already deleted, else
  /// the server error codes the mapper knows. [failDeleteWith] simulates a
  /// backend/network rejection.
  Object? failDeleteWith;
  String? lastDeleteReason;

  @override
  Future<void> deleteDraft(String testId, {String? reason}) async {
    lastDeleteReason = reason;
    calls.add('delete:$testId');
    if (failDeleteWith != null) throw failDeleteWith!;
    final t = rows[testId];
    if (t == null) throw const DataError(message: 'Test not found.');
    if (t.createdBy != currentUser) {
      throw const DataError(
        message: 'You do not have permission to perform this action.',
      );
    }
    if (t.isSoftDeleted) {
      throw const DataError(message: 'This test has already been deleted.');
    }
    if (t.status != TestStatus.draft) {
      throw const DataError(message: 'Only draft tests can be deleted.');
    }
    rows[testId] = Test(
      id: t.id,
      createdBy: t.createdBy,
      title: t.title,
      status: t.status,
      testMode: t.testMode,
      durationSec: t.durationSec,
      settings: t.settings,
      isSoftDeleted: true,
      deletedAt: DateTime(2026, 9, 16),
      shuffleQuestions: t.shuffleQuestions,
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
      description: t.description,
      status: TestStatus.published,
      testMode: t.testMode,
      groupId: t.groupId, // G10: a published group test stays in its group
      durationSec: t.durationSec,
      marksPerQuestion: t.marksPerQuestion,
      negativeMarks: t.negativeMarks,
      startsAt: t.startsAt,
      endsAt: t.endsAt,
      settings: t.settings,
      config: t.config,
      shuffleQuestions: t.shuffleQuestions,
    );
  }

  // ── G9 compile dependency (interface method added by the G9 branch in
  // progress; thin mirror of `member read tests` so the suite compiles) ──
  @override
  Future<List<Test>> listByGroup(String groupId, {int limit = 100}) async {
    calls.add('listByGroup:$groupId');
    if (!_isMember(groupId)) return const [];
    return rows.values
        .where((t) => t.groupId == groupId && !t.isSoftDeleted)
        .take(limit)
        .toList();
  }

  // ── G10 ──

  /// Live SELECT policies: members see the group's non-deleted tests; the
  /// creator additionally sees their own soft-deleted (archived) ones.
  @override
  Future<List<Test>> listForGroup(String groupId, {int limit = 100}) async {
    calls.add('listForGroup:$groupId');
    final member = _isMember(groupId);
    final out = rows.values.where((t) {
      if (t.groupId != groupId) return false;
      if (t.createdBy == currentUser) return true;
      return member && !t.isSoftDeleted;
    }).toList();
    // Newest first, like the live query (by id sequence here).
    out.sort((a, b) => b.id.compareTo(a.id));
    return out.take(limit).toList();
  }

  Object? failArchiveWith;

  /// Mirrors `fn_soft_delete_test`.
  @override
  Future<void> archive(String testId, {String? reason}) async {
    calls.add('archive:$testId');
    if (failArchiveWith != null) throw failArchiveWith!;
    final t = rows[testId];
    if (t == null) throw const DataError(message: 'Test not found.');
    if (t.isSoftDeleted) return; // idempotent server behaviour
    if (t.status == TestStatus.live || t.status == TestStatus.scheduled) {
      throw const DataError(
        message: 'Ongoing or scheduled tests cannot be archived.',
      );
    }
    if (t.createdBy != currentUser) {
      final g = t.groupId;
      if (g == null ||
          !(_isGroupOwner(g) || _hasPermission(g, GroupPermission.editTest))) {
        throw const DataError(
          message: 'You do not have permission to perform this action.',
        );
      }
    }
    rows[testId] = Test(
      id: t.id,
      createdBy: t.createdBy,
      title: t.title,
      description: t.description,
      status: TestStatus.archived,
      testMode: t.testMode,
      groupId: t.groupId,
      durationSec: t.durationSec,
      startsAt: t.startsAt,
      endsAt: t.endsAt,
      settings: t.settings,
      config: t.config,
      isSoftDeleted: true,
      deletedAt: DateTime(2026, 9, 19),
      archivedAt: DateTime(2026, 9, 19),
    );
  }

  @override
  Future<List<TestSyllabus>> syllabusFor(String testId) async => [
    for (final n in syllabus[testId] ?? const <String>{})
      TestSyllabus(
        id: '',
        testId: testId,
        syllabusNodeId: n,
        createdAt: DateTime(2026),
      ),
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
  Future<List<Question>> safeQuestions(
    String testId, {
    String? accessCode,
  }) async {
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
      throw const DataError(
        message: 'correct_option must be a valid option index.',
      );
    }
    final id = 'q-${nextId++}';
    (byTest[testId] ??= []).add(
      Question(
        id: id,
        testId: testId,
        ordinal: byTest[testId]!.length + 1,
        question: draft.questionText,
        options: [
          for (final o in draft.options)
            QuestionOption(id: o.id ?? 'o', text: o.text),
        ],
        difficulty: draft.difficulty,
        marks: draft.marks,
        status: 'pending_review',
        questionType: draft.questionType,
      ),
    );
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
      throw const DataError(
        message: 'correct_option must be a valid option index.',
      );
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

/// Fake Question Bank Repository for testing.
class FakeQuestionBankRepository implements QuestionBankRepository {
  final Map<String, QuestionBankItem> items = {};
  final List<String> calls = [];
  int nextId = 1;
  int _cloneCount = 0;

  @override
  Future<QuestionBankPage> list(QuestionBankFilter filter) async {
    calls.add('list');
    var filtered = items.values.toList();

    // Apply filters
    if (filter.search != null && filter.search!.isNotEmpty) {
      final search = filter.search!.toLowerCase();
      filtered = filtered
          .where((item) => item.question.toLowerCase().contains(search))
          .toList();
    }
    if (filter.status != null) {
      filtered = filtered
          .where((item) => item.status == filter.status)
          .toList();
    }
    if (filter.difficulty != null) {
      filtered = filtered
          .where((item) => item.difficulty == filter.difficulty)
          .toList();
    }
    if (filter.language != null) {
      filtered = filtered
          .where((item) => item.language == filter.language)
          .toList();
    }
    if (filter.questionType != null) {
      filtered = filtered
          .where((item) => item.questionType == filter.questionType)
          .toList();
    }

    final offset = filter.offset;
    final limit = filter.pageSize;
    final paged = filtered.skip(offset).take(limit).toList();

    return QuestionBankPage(
      items: paged,
      total: filtered.length,
      offset: offset,
      pageSize: limit,
    );
  }

  @override
  Future<QuestionBankItem?> getById(String id) async {
    calls.add('getById:$id');
    return items[id];
  }

  @override
  Future<int> getAvailableCount({
    String? subjectName,
    String? chapter,
    String? difficulty,
    String? language,
    bool pyqOnly = false,
  }) async {
    calls.add('getAvailableCount');
    return items.values.where((item) => item.status == 'approved').length;
  }

  @override
  Future<String> create({
    required String question,
    required List<QuestionBankOption> options,
    required int correctOption,
    String explanation = '',
    String? subjectId,
    String subjectName = '',
    String chapter = '',
    String? topicNodeId,
    String difficulty = 'medium',
    String language = 'en',
    String questionType = 'mcq',
    String source = 'manual',
  }) async {
    calls.add('create:$question');
    final id = 'qb-${nextId++}';
    items[id] = QuestionBankItem(
      id: id,
      question: question,
      options: options,
      correctOption: correctOption,
      explanation: explanation,
      subjectId: subjectId,
      subjectName: subjectName,
      chapter: chapter,
      topicNodeId: topicNodeId,
      difficulty: difficulty,
      language: language,
      questionType: questionType,
      source: source,
      createdAt: DateTime.now(),
    );
    return id;
  }

  @override
  Future<void> update({
    required String id,
    String? question,
    List<QuestionBankOption>? options,
    int? correctOption,
    String? explanation,
    String? subjectId,
    String? subjectName,
    String? chapter,
    String? topicNodeId,
    String? difficulty,
    String? language,
    String? questionType,
    String? status,
  }) async {
    calls.add('update:$id');
    final existing = items[id];
    if (existing == null) throw const DataError(message: 'Question not found');

    items[id] = QuestionBankItem(
      id: existing.id,
      question: question ?? existing.question,
      options: options ?? existing.options,
      correctOption: correctOption ?? existing.correctOption,
      explanation: explanation ?? existing.explanation,
      subjectId: subjectId ?? existing.subjectId,
      subjectName: subjectName ?? existing.subjectName,
      chapter: chapter ?? existing.chapter,
      topicNodeId: topicNodeId ?? existing.topicNodeId,
      difficulty: difficulty ?? existing.difficulty,
      language: language ?? existing.language,
      questionType: questionType ?? existing.questionType,
      source: existing.source,
      createdBy: existing.createdBy,
      timesUsed: existing.timesUsed,
      status: status ?? existing.status,
      createdAt: existing.createdAt,
    );
  }

  @override
  Future<void> archive(String id) async {
    calls.add('archive:$id');
    final existing = items[id];
    if (existing == null) throw const DataError(message: 'Question not found');

    items[id] = QuestionBankItem(
      id: existing.id,
      question: existing.question,
      options: existing.options,
      correctOption: existing.correctOption,
      explanation: existing.explanation,
      subjectId: existing.subjectId,
      subjectName: existing.subjectName,
      chapter: existing.chapter,
      topicNodeId: existing.topicNodeId,
      difficulty: existing.difficulty,
      language: existing.language,
      questionType: existing.questionType,
      source: existing.source,
      createdBy: existing.createdBy,
      timesUsed: existing.timesUsed,
      status: 'archived',
      createdAt: existing.createdAt,
      archivedAt: DateTime.now(),
    );
  }

  @override
  Future<void> restore(String id) async {
    calls.add('restore:$id');
    final existing = items[id];
    if (existing == null) throw const DataError(message: 'Question not found');

    items[id] = QuestionBankItem(
      id: existing.id,
      question: existing.question,
      options: existing.options,
      correctOption: existing.correctOption,
      explanation: existing.explanation,
      subjectId: existing.subjectId,
      subjectName: existing.subjectName,
      chapter: existing.chapter,
      topicNodeId: existing.topicNodeId,
      difficulty: existing.difficulty,
      language: existing.language,
      questionType: existing.questionType,
      source: existing.source,
      createdBy: existing.createdBy,
      timesUsed: existing.timesUsed,
      status: 'pending_review',
      createdAt: existing.createdAt,
      archivedAt: null,
    );
  }

  @override
  Future<List<QuestionBankItem>> checkDuplicates(String questionText) async {
    calls.add('checkDuplicates');
    final normalizedKey = questionText.toLowerCase().trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    return items.values
        .where(
          (item) =>
              item.question.toLowerCase().trim().replaceAll(
                RegExp(r'\s+'),
                ' ',
              ) ==
              normalizedKey,
        )
        .toList();
  }

  @override
  Future<int> cloneToTest({
    required String testId,
    required List<String> bankIds,
    int marksPerQuestion = 1,
  }) async {
    calls.add('cloneToTest:$testId');
    var count = 0;
    for (final bankId in bankIds) {
      final item = items[bankId];
      if (item != null && item.status == 'approved') {
        count++;
      }
    }
    _cloneCount += count;
    return count;
  }

  @override
  Future<QuestionBankSaveResult> saveDrafts({
    required List<QuestionDraft> drafts,
    String? subjectId,
    String? chapterId,
    String source = 'upload',
    String status = 'pending_review',
  }) async {
    calls.add('saveDrafts');
    final savedIds = <String>[];
    for (final d in drafts) {
      final id = (nextId++).toString();
      items[id] = QuestionBankItem(
        id: id,
        question: d.questionText,
        options: d.options
            .map((o) => QuestionBankOption(text: o.text))
            .toList(),
        correctOption: d.correctOptionIndex ?? 0,
        explanation: d.explanation ?? '',
        subjectId: d.subjectId ?? subjectId,
        subjectName: '',
        chapter: '',
        topicNodeId: d.topicNodeId,
        difficulty: 'medium',
        language: 'en',
        questionType: 'mcq',
        source: source,
        createdBy: 'user-1',
        timesUsed: 0,
        status: status,
        createdAt: DateTime.now(),
      );
      savedIds.add(id);
    }
    return QuestionBankSaveResult(
      total: drafts.length,
      savedCount: savedIds.length,
      savedIds: savedIds,
      skippedDuplicateCount: 0,
      skippedDuplicates: const [],
    );
  }

  /// Helper to seed test data.
  void seed(QuestionBankItem item) {
    items[item.id] = item;
  }
}

/// The R4 test feature only reads [myGroups]; the full Group Hub behaviour
/// lives in `test/group/fakes.dart`.
class FakeGroupRepository extends InMemoryGroupRepository {
  /// Seeds the fake from canned rows (R4 only needs id, name and role).
  void seedGroups(List<Group> rows) {
    groups.clear();
    for (final g in rows) {
      final f = seed(id: g.id, name: g.name, ownerId: g.ownerId);
      f.roles[currentUser] = g.userRole;
      for (var i = f.roles.length; i < g.memberCount; i++) {
        f.roles['filler-$i'] = 'member';
      }
    }
  }
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
  SubmitScorecard? submitResult;
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
    return (
      attempt: _serverStart(testId, reattempt: reattempt),
      testTitle: null,
    );
  }

  @override
  Future<StartedAttempt> startByCode(
    String code, {
    bool reattempt = false,
  }) async {
    calls.add('code:$code${reattempt ? ':reattempt' : ''}');
    if (failStartWith != null) throw failStartWith!;
    if (next != null && rows.isEmpty) {
      return (attempt: next!, testTitle: 'Coded');
    }
    return (
      attempt: _serverStart('t-coded', reattempt: reattempt),
      testTitle: 'Coded',
    );
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
    final own = [
      for (final a in rows)
        if (a.testId == testId && a.userId == currentUser) a,
    ];
    for (final a in own) {
      if (a.status == AttemptStatus.inProgress) return a; // resume
    }
    final settings = testSettings[testId];
    final allow = settings?['allow_reattempt'] == true;
    final max = allow
        ? ((settings?['max_attempts'] as int?) ?? 1).clamp(1, 1 << 30)
        : 1;
    if (own.length >= max) {
      throw const DataError(
        message: 'You have used all attempts allowed for this test.',
      );
    }
    if (own.isNotEmpty && !reattempt) {
      throw const DataError(
        message: 'You have already completed this test. Use Re-attempt to try again.',
      );
    }
    final number =
        own.fold<int>(0, (m, a) => a.attemptNumber > m ? a.attemptNumber : m) +
        1;
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
  void complete(
    String attemptId, {
    AttemptStatus status = AttemptStatus.scored,
  }) {
    final i = rows.indexWhere((a) => a.id == attemptId);
    if (i == -1) return;
    final a = rows[i];
    rows[i] = Attempt(
      id: a.id,
      testId: a.testId,
      userId: a.userId,
      status: status,
      startedAt: a.startedAt,
      deadlineAt: a.deadlineAt,
      attemptNumber: a.attemptNumber,
      submittedAt: a.startedAt.add(const Duration(minutes: 20)),
      integrityEventCount: a.integrityEventCount,
      autoSubmitThreshold: a.autoSubmitThreshold,
    );
  }

  @override
  Future<SubmitScorecard> submit(String attemptId, {required bool timedOut}) async {
    calls.add('submit:$attemptId:$timedOut');
    complete(
      attemptId,
      status: timedOut ? AttemptStatus.autoSubmitted : AttemptStatus.scored,
    );
    return submitResult ??
        SubmitScorecard(
          success: true,
          attemptId: attemptId,
          pointsAwarded: 15,
          testId: 't-1',
          score: 3,
          maxScore: 5,
          resultPublished: true,
        );
  }

  // ── Integrity events (mirrors rpc_record_integrity_event's server
  // rules: ownership, test-relationship, terminal-state no-op, same-type
  // dedup within 3s, threshold auto-submit) — a security-analog double,
  // not a canned stub, matching this file's convention for other fakes. ──

  DateTime Function() now = DateTime.now;
  Object? failIntegrityWith;
  final Map<String, ({String type, DateTime at})> _lastEvent = {};

  @override
  Future<IntegrityEventOutcome> recordIntegrityEvent({
    required String attemptId,
    required String testId,
    required String eventType,
    Map<String, dynamic>? details,
  }) async {
    calls.add('integrity:$attemptId:$eventType');
    if (failIntegrityWith != null) throw failIntegrityWith!;

    final i = rows.indexWhere(
      (a) => a.id == attemptId && a.userId == currentUser,
    );
    if (i == -1) {
      throw const DataError(message: 'ATTEMPT_NOT_FOUND');
    }
    var a = rows[i];
    if (a.testId != testId) {
      throw const DataError(message: 'TEST_MISMATCH');
    }
    if (a.status != AttemptStatus.inProgress) {
      return (
        eventRecorded: false,
        integrityEventCount: a.integrityEventCount ?? 0,
        autoSubmitThreshold: a.autoSubmitThreshold,
        autoSubmitted: false,
      );
    }

    final last = _lastEvent[attemptId];
    final nowTime = now();
    if (last != null &&
        last.type == eventType &&
        nowTime.difference(last.at) < const Duration(seconds: 3)) {
      return (
        eventRecorded: false,
        integrityEventCount: a.integrityEventCount ?? 0,
        autoSubmitThreshold: a.autoSubmitThreshold,
        autoSubmitted: false,
      );
    }
    _lastEvent[attemptId] = (type: eventType, at: nowTime);

    final newCount = (a.integrityEventCount ?? 0) + 1;
    rows[i] = Attempt(
      id: a.id,
      testId: a.testId,
      userId: a.userId,
      status: a.status,
      startedAt: a.startedAt,
      deadlineAt: a.deadlineAt,
      attemptNumber: a.attemptNumber,
      submittedAt: a.submittedAt,
      integrityEventCount: newCount,
      autoSubmitThreshold: a.autoSubmitThreshold,
    );
    a = rows[i];

    var autoSubmitted = false;
    final threshold = a.autoSubmitThreshold;
    if (threshold != null && threshold > 0 && newCount >= threshold) {
      complete(attemptId, status: AttemptStatus.autoSubmitted);
      autoSubmitted = true;
    }

    return (
      eventRecorded: true,
      integrityEventCount: newCount,
      autoSubmitThreshold: threshold,
      autoSubmitted: autoSubmitted,
    );
  }

  // ── Disclaimer acceptance: own-attempt-only, set-once (mirrors
  // rpc_record_disclaimer_acceptance's WHERE ... disclaimer_accepted_at IS
  // NULL idempotency). ──
  final Map<String, ({String version, String language})> disclaimerAcceptances =
      {};

  @override
  Future<void> recordDisclaimerAcceptance({
    required String attemptId,
    required String version,
    required String language,
  }) async {
    calls.add('disclaimer:$attemptId:$version:$language');
    final owned = rows.any((a) => a.id == attemptId && a.userId == currentUser);
    if (!owned) {
      throw const DataError(message: 'ATTEMPT_NOT_FOUND');
    }
    disclaimerAcceptances.putIfAbsent(
      attemptId,
      () => (version: version, language: language),
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
    final r = byAttemptId[attemptId];
    if (r == null) return null;
    if (!_resultVisible(r.testId, r.userId)) return null;
    return r;
  }

  @override
  Future<List<Result>> mineForTest(String testId) async => mine;

  /// `rpc_get_my_answer_key` stand-in: attempt id -> (question id -> correct
  /// option index). Empty until a test seeds it, matching the live RPC's
  /// "no rows" case (the review screen then shows no verdicts).
  final Map<String, Map<String, int>> answerKeyByAttempt = {};

  @override
  Future<Map<String, int>> myAnswerKey(String attemptId) async {
    calls.add('myAnswerKey:$attemptId');
    return answerKeyByAttempt[attemptId] ?? const {};
  }

  /// Raw jsonb the fake RPC returns (live shape). Parsed exactly like the
  /// real repository so controller tests exercise the same mapping.
  Map<String, dynamic>? rpcResponse;

  // ── G11: group test results. When [groups] and [tests] are attached the
  // LIVE rules are mirrored:
  //   results SELECT      → own row OR VIEW_GROUP_ANALYTICS in the test's group
  //   result_batches SEL  → GENERATE_RESULTS in the test's group
  //   ai_reports SELECT   → own row OR GENERATE_RESULTS
  //   rpc_generate_results → creator OR GENERATE_RESULTS, else
  //                          GENERATE_RESULTS_FORBIDDEN; UNIQUE batch per test
  //   rpc_request_coach_reports (proposed) → same gate + finished batch;
  //                          idempotent job per (test, batch)
  // Without them the old canned behaviour stays.
  InMemoryGroupRepository? groups;
  FakeTestRepository? tests;
  String currentUser = 'u-1';
  final Map<String, List<Result>> resultsByTest = {};
  final Map<String, List<AiCoachReport>> reportsByTest = {};
  final Map<String, ResultBatch> batchByTest = {};
  final Map<String, CoachReportJob> jobByTest = {};
  Object? failGenerateWith;
  Object? failRequestWith;

  String? _groupOf(String testId) => tests?.rows[testId]?.groupId;
  bool _has(String testId, GroupPermission p) {
    final g = _groupOf(testId);
    if (g == null || groups == null) return false;
    return groups!.hasPermission(g, p);
  }

  bool _isCreator(String testId) =>
      tests?.rows[testId]?.createdBy == currentUser;

  @override
  Future<ResultBatch> generateResults(String testId) async {
    calls.add('generate:$testId');
    if (failGenerateWith != null) throw failGenerateWith!;
    if (groups == null || tests == null) {
      if (batch != null) return batch!;
      return SupabaseResultRepository.batchFromRpcResponse(rpcResponse);
    }
    if (!_isCreator(testId) && !_has(testId, GroupPermission.generateResults)) {
      throw const DataError(message: 'GENERATE_RESULTS_FORBIDDEN');
    }
    final existing = batchByTest[testId];
    if (existing != null) return existing; // live: UNIQUE(test_id), reused
    final rows = resultsByTest[testId] ?? const [];
    final b = ResultBatch(
      id: 'b-$testId',
      testId: testId,
      requestedBy: currentUser,
      status: BatchStatus.completed,
      reportsDone: rows.length,
      reportsTotal: rows.length,
      completedAt: DateTime(2026, 9, 19, 12),
    );
    batchByTest[testId] = b;
    return b;
  }

  /// Test-only convenience: seeds an already-published, completed batch for
  /// [testId] directly (skipping the generate step) so visibility tests can
  /// assert post-publish behavior without re-testing the generate flow.
  void publish(String testId) {
    final existing = batchByTest[testId];
    batchByTest[testId] = ResultBatch(
      id: existing?.id ?? 'b-$testId',
      testId: testId,
      status: BatchStatus.completed,
      reportsDone: existing?.reportsDone,
      reportsTotal: existing?.reportsTotal,
      publishedAt: DateTime(2026, 9, 22, 12),
      publishedBy: currentUser,
    );
  }

  Object? failPublishWith;

  /// Mirrors the proposed `rpc_publish_results`: same authorization as
  /// generate, requires a completed/partially-completed batch, idempotent.
  @override
  Future<ResultBatch> publishResults(String testId) async {
    calls.add('publish:$testId');
    if (failPublishWith != null) throw failPublishWith!;
    if (groups == null || tests == null) {
      final b = batch ?? batchByTest[testId];
      if (b == null) {
        throw const DataError(message: 'RESULTS_NOT_GENERATED');
      }
      final published = ResultBatch(
        id: b.id,
        testId: b.testId,
        status: b.status,
        publishedAt: b.publishedAt ?? DateTime(2026, 9, 22, 12),
        reused: b.publishedAt != null,
      );
      batch = published;
      return published;
    }
    if (!_isCreator(testId) && !_has(testId, GroupPermission.generateResults)) {
      throw const DataError(message: 'GENERATE_RESULTS_FORBIDDEN');
    }
    final existing = batchByTest[testId];
    if (existing == null ||
        !(existing.isCompleted || existing.isPartiallyCompleted)) {
      throw const DataError(message: 'RESULTS_NOT_GENERATED');
    }
    if (existing.isPublished) {
      return ResultBatch(
        id: existing.id,
        testId: existing.testId,
        status: existing.status,
        publishedAt: existing.publishedAt,
        reused: true,
      );
    }
    final published = ResultBatch(
      id: existing.id,
      testId: existing.testId,
      requestedBy: existing.requestedBy,
      status: existing.status,
      reportsDone: existing.reportsDone,
      reportsTotal: existing.reportsTotal,
      completedAt: existing.completedAt,
      publishedAt: DateTime(2026, 9, 22, 12),
      publishedBy: currentUser,
    );
    batchByTest[testId] = published;
    return published;
  }

  /// Own-row visibility for a group test additionally requires the test's
  /// batch to be published — mirrors the live `own results` RLS gate added
  /// alongside `rpc_publish_results`. VIEW_GROUP_ANALYTICS holders are
  /// unaffected (same asymmetry as the live "analytics holders" policy).
  /// Self/practice tests (no `groups`/`tests` attached, or `groupId` null)
  /// are never gated.
  bool _resultVisible(String testId, String ownerId) {
    if (groups == null || tests == null) return true;
    if (_groupOf(testId) == null) return true;
    if (_has(testId, GroupPermission.viewGroupAnalytics)) return true;
    if (ownerId != currentUser) return false;
    return batchByTest[testId]?.isPublished ?? false;
  }

  @override
  Future<List<Result>> resultsForTest(String testId) async {
    calls.add('results:$testId');
    final rows = resultsByTest[testId] ?? const [];
    if (groups == null) return rows;
    if (_has(testId, GroupPermission.viewGroupAnalytics)) {
      return [...rows]..sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
    }
    if (!_resultVisible(testId, currentUser)) return const [];
    return rows.where((r) => r.userId == currentUser).toList();
  }

  /// Mirrors the remediated live `rpc_get_leaderboard`: rows for the test
  /// creator, a member of the test's group, or a participant (own result);
  /// everyone else gets 0 rows. Ranking is the server's (`score DESC`,
  /// competition ranks); `full_name` comes from the roster names.
  @override
  Future<List<Map<String, dynamic>>> leaderboard(String testId) async {
    calls.add('leaderboard:$testId');
    final rows = resultsByTest[testId] ?? const [];
    if (groups != null) {
      final g = _groupOf(testId);
      final member =
          g != null &&
          (groups!.groups[g]?.roles.containsKey(currentUser) ?? false);
      final participant = rows.any((r) => r.userId == currentUser);
      if (!_isCreator(testId) && !member && !participant) return const [];
      // Same publish gate as `own results`, with the same manager preview
      // asymmetry: the creator and VIEW_GROUP_ANALYTICS holders may see the
      // leaderboard before publish; everyone else cannot.
      if (g != null &&
          !_isCreator(testId) &&
          !_has(testId, GroupPermission.viewGroupAnalytics) &&
          !(batchByTest[testId]?.isPublished ?? false)) {
        return const [];
      }
    }
    final sorted = [...rows]
      ..sort(
        (a, b) => (b.score ?? double.negativeInfinity).compareTo(
          a.score ?? double.negativeInfinity,
        ),
      );
    var rank = 0;
    double? prev;
    final allEntries = [
      for (var i = 0; i < sorted.length; i++)
        {
          'rank': (() {
            final s = sorted[i].score ?? double.negativeInfinity;
            if (prev == null || s != prev) {
              rank = i + 1;
              prev = s;
            }
            return rank;
          })(),
          'user_id': sorted[i].userId,
          'full_name': groups?.profileNames[sorted[i].userId],
          'avatar_url': null,
          'student_code': null,
          'score': sorted[i].score,
          'max_score': sorted[i].maxScore,
          'percentage': sorted[i].percentage,
          'accuracy': sorted[i].accuracy,
          'submitted_at': sorted[i].computedAt?.toIso8601String(),
        },
    ];
    if (groups != null &&
        !_isCreator(testId) &&
        !_has(testId, GroupPermission.viewGroupAnalytics)) {
      return allEntries.where((e) => e['user_id'] == currentUser).toList();
    }
    return allEntries;
  }

  @override
  Future<AiCoachReport?> myAiReport(String testId) async {
    calls.add('myReport:$testId');
    return (reportsByTest[testId] ?? const [])
        .where((r) => r.userId == currentUser)
        .firstOrNull;
  }

  @override
  Future<List<AiCoachReport>> allAiReports(String testId) async {
    calls.add('allReports:$testId');
    final rows = reportsByTest[testId] ?? const [];
    if (groups == null) return rows;
    if (_has(testId, GroupPermission.generateResults)) return rows;
    return rows.where((r) => r.userId == currentUser).toList();
  }

  @override
  Future<ResultBatch?> batchForTest(String testId) async {
    calls.add('batch:$testId');
    if (groups == null) return batch;
    if (!_has(testId, GroupPermission.generateResults)) return null;
    return batchByTest[testId];
  }

  @override
  Future<CoachReportJob> requestCoachReports(String testId) async {
    calls.add('requestCoach:$testId');
    if (failRequestWith != null) throw failRequestWith!;
    if (!_isCreator(testId) && !_has(testId, GroupPermission.generateResults)) {
      throw const DataError(message: 'GENERATE_RESULTS_FORBIDDEN');
    }
    final b = batchByTest[testId];
    if (b == null || !(b.isCompleted || b.isPartiallyCompleted)) {
      throw const DataError(message: 'RESULTS_NOT_GENERATED');
    }
    final existing = jobByTest[testId];
    if (existing != null) {
      return CoachReportJob(
        jobId: existing.jobId,
        status: existing.status,
        reportsDone: existing.reportsDone,
        reportsTotal: existing.reportsTotal,
        created: false,
      );
    }
    final job = CoachReportJob(
      jobId: 'job-$testId',
      status: 'pending',
      reportsDone: (reportsByTest[testId] ?? const []).length,
      reportsTotal: (resultsByTest[testId] ?? const []).length,
      created: true,
    );
    jobByTest[testId] = job;
    return job;
  }
}
