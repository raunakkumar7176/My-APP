import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/group.dart';
import '../../../core/models/question.dart';
import '../../../core/models/test.dart';
import '../../../core/services/auth_service.dart';
import '../data/group_repository.dart';
import '../data/question_repository.dart';
import '../data/test_repository.dart';
import '../domain/attempt_policy.dart';
import '../domain/backend_mapping.dart';
import '../domain/creation_settings.dart';
import '../domain/publish_readiness.dart';
import '../domain/test_kind.dart';
import '../models/question_draft.dart';
import 'disposable_notifier.dart';

/// Owns the whole create/edit/publish orchestration. Screens render its
/// state and call its methods; every server rule is re-checked by the RPCs.
///
/// Persistence guarantees (unit-tested):
///  - a test is created at most once per controller (later saves update);
///  - each local question draft is created at most once (removed from
///    [localQuestions] as soon as its RPC succeeds, so partial failures are
///    retry-safe);
///  - each syllabus node is added/removed at most once;
///  - after a save the server question list is reloaded through the safe
///    RPC (never `public.questions`).
class TestCreationController extends DisposableNotifier {
  TestCreationController({
    this.editingTestId,
    TestRepository? tests,
    QuestionRepository? questions,
    GroupRepository? groups,
    String? Function()? currentUserId,
  }) : _tests = tests ?? const SupabaseTestRepository(),
       _questions = questions ?? const SupabaseQuestionRepository(),
       _groups = groups ?? const SupabaseGroupRepository(),
       _currentUserId = currentUserId ?? (() => AuthService.currentUser?.id);

  /// Set when opened via /tests/:id/edit.
  final String? editingTestId;
  final TestRepository _tests;
  final QuestionRepository _questions;
  final GroupRepository _groups;
  final String? Function() _currentUserId;

  // ── Kind defaults (server always applies duration_sec as the deadline;
  //    no untimed mode exists, so Practice gets a generous limit) ──
  static const practiceDefaultDurationSec = 3 * 60 * 60;
  static const quickDefaultDurationSec = 10 * 60;
  static const quickTargetQuestionCount = 10;
  static const targetQuestionCountKey = 'target_question_count';

  // ── form state ──
  String title = '';
  String description = '';
  TestKind kind = TestKind.self;
  String? groupId;
  int? durationSec;
  double? marksPerQuestion;
  double? negativeMarks;
  DateTime? startsAt;
  DateTime? endsAt;
  int? maxParticipants;
  bool allowLateJoin = false;
  String? accessCode;
  String? joinCode;

  /// Re-attempt policy (persisted in `tests.settings`; server-enforced).
  AttemptSettings attemptSettings = AttemptSettings.defaults;

  /// Late-join window (scheduled kinds); `allowLateJoin` is the column flag.
  LateJoinSettings lateJoin = LateJoinSettings.defaults;

  /// Mixed-difficulty distribution target (`settings.question_config`).
  QuestionConfig questionConfig = QuestionConfig.none;

  /// Derived, never typed: `starts_at + duration_sec` (null without a start).
  DateTime? get calculatedEndsAt =>
      ScheduleMath.endFor(startsAt: startsAt, durationSec: durationSec);

  /// Actual difficulty counts of every question (server + local drafts).
  Map<String, int> get actualDifficultyCounts {
    final counts = {'easy': 0, 'medium': 0, 'hard': 0};
    for (final q in serverQuestions) {
      counts.update(q.difficulty.name, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final d in localQuestions) {
      counts.update(d.difficulty.name, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  DistributionCheck? get distributionCheck =>
      questionConfig.isSet ? questionConfig.check(actualDifficultyCounts) : null;

  final List<QuestionDraft> localQuestions = [];
  final List<Question> serverQuestions = [];
  final List<String> syllabusNodeIds = [];
  final List<String> _serverSyllabusNodeIds = [];
  List<Group> groups = const [];

  Test? _persisted;
  bool _loading = false;
  bool _busy = false;
  String? _loadError;

  /// The server row once created/loaded; the ONLY edit-mode signal.
  Test? get persistedTest => _persisted;
  bool get isPersisted => _persisted != null;
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  String? get loadError => _loadError;
  List<String> get serverSyllabusNodeIds =>
      List.unmodifiable(_serverSyllabusNodeIds);

  String? get questionsGuidance {
    switch (kind) {
      case TestKind.quick:
        return 'Quick Test: aim for 5–$quickTargetQuestionCount questions '
            '(about ${quickDefaultDurationSec ~/ 60} minutes).';
      case TestKind.sectional:
        return 'Sectional Test: add questions for each subject/topic you '
            'select in the Syllabus step.';
      default:
        return null;
    }
  }

  // ── readiness (single implementation, shared with the review step) ──

  PublishReadinessInput get readinessInput => PublishReadinessInput(
    title: title,
    kind: kind,
    groupId: groupId,
    durationSec: durationSec,
    marksPerQuestion: marksPerQuestion,
    startsAt: startsAt,
    endsAt: calculatedEndsAt ?? endsAt,
    serverQuestionStatuses: [for (final q in serverQuestions) q.status],
    serverQuestionOptionCounts: [
      for (final q in serverQuestions) q.options?.length ?? 0,
    ],
    localDraftValidity: [for (final d in localQuestions) d.isValid],
    syllabusNodeCount: syllabusNodeIds.length,
    questionConfig: questionConfig,
    actualDifficultyCounts: actualDifficultyCounts,
    attemptSettings: attemptSettings,
    lateJoin: lateJoin,
    allowLateJoin: allowLateJoin,
    // Empty string (not null) so readiness evaluates the join-code rule.
    joinCode: joinCode ?? '',
  );

  List<ReadinessItem> get readiness =>
      PublishReadiness.evaluate(readinessInput);
  bool get isReadyToPublish => PublishReadiness.isReady(readinessInput);

  bool get canProceedFromBasics => title.trim().isNotEmpty;
  bool get canProceedFromConfiguration =>
      (!kind.requiresGroup || (groupId != null && groupId!.isNotEmpty)) &&
      questionConfig.isValid &&
      (kind.maxQuestionTarget == null || questionConfig.total <= kind.maxQuestionTarget!);
  bool get hasAnyQuestion =>
      localQuestions.isNotEmpty || serverQuestions.isNotEmpty;

  // ── loading ──

  Future<void> loadForEdit() async {
    final id = editingTestId;
    if (id == null) return;
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final test = await _tests.getById(id);
      if (test == null) {
        _loadError = 'Test not found';
      } else if (test.status != TestStatus.draft) {
        _loadError = 'Only draft tests can be edited';
      } else if (test.createdBy != _currentUserId()) {
        _loadError = 'You can only edit your own tests';
      } else {
        _applyTest(test);
        await _reloadServerQuestions(id);
        try {
          final syllabus = await _tests.syllabusFor(id);
          _serverSyllabusNodeIds
            ..clear()
            ..addAll(syllabus.map((s) => s.syllabusNodeId));
          syllabusNodeIds
            ..clear()
            ..addAll(_serverSyllabusNodeIds);
        } catch (e) {
          AppLogger.warning('Syllabus load failed: $e');
        }
      }
    } on AppError catch (e) {
      _loadError = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadGroups() async {
    try {
      groups = await _groups.myGroups();
    } catch (e) {
      AppLogger.warning('Groups unavailable: $e');
      groups = const [];
    }
    notifyListeners();
  }

  void _applyTest(Test t) {
    _persisted = t;
    title = t.title;
    description = t.description ?? '';
    kind = BackendMapping.fromBackend(t.testMode, t.settings);
    groupId = t.groupId;
    durationSec = t.durationSec;
    marksPerQuestion = t.marksPerQuestion;
    negativeMarks = t.negativeMarks;
    startsAt = t.startsAt;
    endsAt = t.endsAt;
    maxParticipants = t.maxParticipants;
    allowLateJoin = t.allowLateJoin;
    accessCode = t.accessCode;
    joinCode = t.joinCode;
    attemptSettings = AttemptSettings.fromSettings(t.settings);
    lateJoin = LateJoinSettings.fromTest(allowLateJoin: t.allowLateJoin, settings: t.settings);
    questionConfig = QuestionConfig.fromSettings(t.settings);
  }

  // ── form mutations ──

  void setTitle(String v) => _set(() => title = v);
  void setDescription(String v) => _set(() => description = v);

  void setKind(TestKind newKind) => _set(() {
    final changed = newKind != kind;
    kind = newKind;
    if (!newKind.requiresGroup) groupId = null;
    if (!changed) return;
    switch (newKind) {
      case TestKind.practice:
        startsAt = null;
        endsAt = null;
        durationSec = practiceDefaultDurationSec;
        break;
      case TestKind.quick:
        durationSec = quickDefaultDurationSec;
        break;
      default:
        break;
    }
    // Kind defaults for a NEW test only; an edited row keeps its values.
    if (_persisted == null) {
      final p = newKind.defaultAttemptPolicy;
      attemptSettings = AttemptSettings(
        allowReattempt: p.allowReattempt,
        maxAttempts: p.maxAttempts,
      );
      allowLateJoin = newKind.supportsLateJoin;
      lateJoin = LateJoinSettings.defaults;
      if (!newKind.isScheduled) {
        startsAt = null;
        endsAt = null;
        maxParticipants = null;
      }
    }
  });

  void setLateJoin(LateJoinSettings v) => _set(() {
    lateJoin = v;
    allowLateJoin = v.enabled;
  });

  void setQuestionConfig(QuestionConfig v) => _set(() => questionConfig = v);


  void setConfiguration({
    required int? durationSec,
    required double? marksPerQuestion,
    required double? negativeMarks,
    required String? groupId,
    required DateTime? startsAt,
    required DateTime? endsAt,
    required int? maxParticipants,
    required bool allowLateJoin,
    required String? accessCode,
    required String? joinCode,
    AttemptSettings? attemptSettings,
    LateJoinSettings? lateJoin,
    QuestionConfig? questionConfig,
  }) => _set(() {
    if (attemptSettings != null) this.attemptSettings = attemptSettings;
    if (lateJoin != null) {
      this.lateJoin = lateJoin;
      this.allowLateJoin = lateJoin.enabled;
    }
    if (questionConfig != null) this.questionConfig = questionConfig;
    this.durationSec = durationSec;
    this.marksPerQuestion = marksPerQuestion;
    this.negativeMarks = negativeMarks;
    this.groupId = groupId;
    this.startsAt = startsAt;
    this.endsAt = endsAt;
    this.maxParticipants = maxParticipants;
    this.allowLateJoin = allowLateJoin;
    this.accessCode = accessCode;
    this.joinCode = joinCode;
  });

  void setLocalQuestions(List<QuestionDraft> drafts) => _set(() {
    localQuestions
      ..clear()
      ..addAll(drafts);
  });

  void setSyllabusNodeIds(List<String> ids) => _set(() {
    syllabusNodeIds
      ..clear()
      ..addAll(ids);
  });

  // ── server question operations ──

  Future<void> approveQuestion(String questionId) => _action(() async {
    await _questions.approve(questionId);
    _replaceServerQuestion(questionId, (q) => q.copyWith(status: 'approved'));
  });

  /// Approves every pending question; returns the number that failed.
  Future<int> approveAllPending() => _action(() async {
    var failed = 0;
    for (final q in List<Question>.from(serverQuestions)) {
      if (q.status == PublishReadiness.approvedStatus) continue;
      try {
        await _questions.approve(q.id);
        _replaceServerQuestion(q.id, (x) => x.copyWith(status: 'approved'));
      } on AppError catch (e) {
        AppLogger.error('Approve ${q.id} failed: ${e.message}');
        failed++;
      }
    }
    return failed;
  });

  Future<void> deleteServerQuestion(String questionId) => _action(() async {
    await _questions.delete(questionId);
    serverQuestions.removeWhere((q) => q.id == questionId);
  });

  Future<void> updateServerQuestion(Question original, QuestionDraft draft) =>
      _action(() async {
        await _questions.update(original.id, draft);
        _replaceServerQuestion(
          original.id,
          (q) => Question(
            id: q.id,
            testId: q.testId,
            ordinal: q.ordinal,
            question: draft.questionText,
            options: [
              for (final o in draft.options)
                QuestionOption(id: o.id ?? '', text: o.text),
            ],
            explanation: draft.explanation,
            subjectId: draft.subjectId,
            topicNodeId: draft.topicNodeId,
            difficulty: draft.difficulty,
            marks: draft.marks,
            negativeMarks: draft.negativeMarks,
            status: q.status,
            language: draft.language,
            questionType: draft.questionType,
          ),
        );
      });

  void _replaceServerQuestion(String id, Question Function(Question) f) {
    final i = serverQuestions.indexWhere((q) => q.id == id);
    if (i != -1) serverQuestions[i] = f(serverQuestions[i]);
  }

  // ── persistence ──

  /// Saves everything as a draft. Returns the test id.
  Future<String> saveDraft() => _action(() async {
    _validateBasics();
    final id = await _persistTestRow();
    await _persistQuestions(id, approve: false);
    await _persistSyllabus(id);
    await _reloadServerQuestions(id);
    return id;
  });

  /// Saves, approves new questions, and publishes. Throws with the first
  /// blocking readiness reason before touching the server.
  Future<String> publish() => _action(() async {
    final reasons = PublishReadiness.blockingReasons(readinessInput);
    if (reasons.isNotEmpty) {
      throw ValidationError(message: reasons.join('\n'));
    }
    final id = await _persistTestRow();
    await _persistQuestions(id, approve: true);
    await _persistSyllabus(id);
    await _reloadServerQuestions(id);
    await _tests.publish(id);
    return id;
  });

  void _validateBasics() {
    if (title.trim().isEmpty) {
      throw const ValidationError(message: 'Title is required');
    }
    if (kind.requiresGroup && (groupId == null || groupId!.isEmpty)) {
      throw const ValidationError(
        message: 'Group selection is required for Group Test',
      );
    }
  }

  TestWriteInput _writeInput() {
    final backend = BackendMapping.toBackend(kind);
    var settings = BackendMapping.settingsFor(kind, _persisted?.settings);
    if (kind == TestKind.quick && settings != null) {
      settings = {...settings}
        ..putIfAbsent(targetQuestionCountKey, () => quickTargetQuestionCount);
    }
    // Attempt policy keys live next to test_kind; every other key is kept.
    settings = attemptSettings.applyTo(settings);
    if (kind.supportsLateJoin) settings = lateJoin.applyTo(settings);
    settings = questionConfig.applyTo(settings);
    String? clean(String? s) =>
        (s == null || s.trim().isEmpty) ? null : s.trim();
    return TestWriteInput(
      title: title.trim(),
      description: clean(description),
      durationSec: durationSec,
      marksPerQuestion: marksPerQuestion,
      negativeMarks: negativeMarks,
      testMode: backend.mode.dbValue,
      groupId: kind.requiresGroup ? groupId : null,
      startsAt: startsAt,
      // Derived on every save: ends_at = starts_at + duration_sec (UTC by the
      // repository). No user-typed end time exists in V1.
      endsAt: calculatedEndsAt,
      maxParticipants: maxParticipants,
      allowLateJoin: allowLateJoin,
      settings: settings,
      config: _persisted?.config,
      accessCode: clean(accessCode),
      joinCode: clean(joinCode),
    );
  }

  /// Creates the row exactly once; afterwards always updates.
  Future<String> _persistTestRow() async {
    final input = _writeInput();
    final existing = _persisted;
    if (existing != null) {
      await _tests.update(existing.id, input);
      return existing.id;
    }
    final created = await _tests.create(input);
    _persisted = created; // from here on, retries update instead of create
    notifyListeners();
    return created.id;
  }

  Future<void> _persistQuestions(String testId, {required bool approve}) async {
    for (final draft in List<QuestionDraft>.from(localQuestions)) {
      final String questionId;
      try {
        questionId = await _questions.create(testId, draft);
        localQuestions.remove(draft); // never re-created on retry
        notifyListeners();
      } catch (e) {
        AppLogger.error('Create question failed: $e');
        rethrow;
      }
      if (approve) {
        try {
          await _questions.approve(questionId);
        } on AppError catch (e) {
          AppLogger.error('Approve new question failed: ${e.message}');
          throw DataError(
            message:
                'A question was saved but could not be approved. '
                'Approve it from the Review step, then publish.',
          );
        }
      }
    }
  }

  Future<void> _persistSyllabus(String testId) async {
    for (final nodeId in List<String>.from(syllabusNodeIds)) {
      if (_serverSyllabusNodeIds.contains(nodeId)) continue;
      await _tests.addSyllabus(testId, nodeId);
      _serverSyllabusNodeIds.add(nodeId);
    }
    for (final nodeId in List<String>.from(_serverSyllabusNodeIds)) {
      if (syllabusNodeIds.contains(nodeId)) continue;
      await _tests.removeSyllabus(testId, nodeId);
      _serverSyllabusNodeIds.remove(nodeId);
    }
  }

  Future<void> _reloadServerQuestions(String testId) async {
    try {
      final fresh = await _questions.safeQuestions(testId);
      serverQuestions
        ..clear()
        ..addAll(fresh);
    } catch (e) {
      // Writes already succeeded and drafts were dropped: nothing will be
      // recreated on retry; the list refreshes on next open.
      AppLogger.warning('Safe question reload failed for $testId: $e');
    }
    notifyListeners();
  }

  // ── helpers ──

  void _set(void Function() body) {
    body();
    notifyListeners();
  }

  Future<T> _action<T>(Future<T> Function() body) async {
    if (_busy) throw const ValidationError(message: 'Please wait…');
    _busy = true;
    notifyListeners();
    try {
      return await body();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
