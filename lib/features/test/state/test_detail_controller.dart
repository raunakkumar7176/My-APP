import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/attempt.dart';
import '../../../core/models/question.dart';
import '../../../core/models/result_batch.dart';
import '../../../core/models/test.dart';
import '../../../core/services/auth_service.dart';
import '../data/attempt_repository.dart';
import '../data/question_repository.dart';
import '../data/result_repository.dart';
import '../data/test_repository.dart';
import '../domain/attempt_policy.dart';
import '../domain/backend_mapping.dart';
import '../domain/test_kind.dart';
import '../domain/test_lifecycle.dart';
import '../domain/test_mode.dart';
import 'disposable_notifier.dart';

/// Everything a started attempt needs to open the taking screen.
typedef LaunchedAttempt = ({StartedAttempt started, List<Question> questions, Test test});

/// Loads one test by id (never from a route object) and exposes the
/// lifecycle-derived action flags. All actions go through repositories; the
/// server re-validates each one.
class TestDetailController extends DisposableNotifier {
  TestDetailController({
    required this.testId,
    TestRepository? tests,
    QuestionRepository? questions,
    AttemptRepository? attempts,
    ResultRepository? results,
    String? Function()? currentUserId,
    DateTime Function()? clock,
  })  : _tests = tests ?? const SupabaseTestRepository(),
        _questions = questions ?? const SupabaseQuestionRepository(),
        _attempts = attempts ?? const SupabaseAttemptRepository(),
        _results = results ?? const SupabaseResultRepository(),
        _currentUserId = currentUserId ?? (() => AuthService.currentUser?.id),
        _clock = clock ?? DateTime.now;

  final String testId;
  final TestRepository _tests;
  final QuestionRepository _questions;
  final AttemptRepository _attempts;
  final ResultRepository _results;
  final String? Function() _currentUserId;
  final DateTime Function() _clock;

  Test? _test;
  ResultBatch? _batch;
  bool _loading = false;
  bool _busy = false;
  String? _error;

  Test? get test => _test;
  ResultBatch? get latestBatch => _batch;
  bool get isLoading => _loading;
  bool get isBusy => _busy;
  String? get error => _error;

  TestKind get kind =>
      BackendMapping.fromBackend(_test?.testMode, _test?.settings);

  bool get isOwner {
    final uid = _currentUserId();
    return uid != null && _test?.createdBy == uid;
  }

  bool get canEdit =>
      _test != null &&
      TestLifecycle.canEdit(isOwner: isOwner, status: _test!.status);

  bool get canPublish =>
      _test != null &&
      TestLifecycle.canPublish(isOwner: isOwner, status: _test!.status);

  bool get canDelete =>
      _test != null &&
      TestLifecycle.canDelete(
        isOwner: isOwner,
        status: _test!.status,
        isSoftDeleted: _test!.isSoftDeleted,
      );

  /// Owner + test over + no batch known to be pending/processing. A batch
  /// that completed, partially completed or failed may be re-requested; the
  /// server answers idempotently (`reused`).
  bool get canGenerateResults =>
      _test != null &&
      TestLifecycle.canGenerateResults(isOwner: isOwner, status: _test!.status) &&
      (_batch == null || _batch!.canTrigger);

  /// Presentation-only window phase (device clock). The server decides for
  /// real when `start()` is called.
  SchedulePhase? get phase {
    final t = _test;
    if (t == null) return null;
    return TestLifecycle.phase(startsAt: t.startsAt, endsAt: t.endsAt, now: _clock());
  }

  /// Null when startable; else a user-facing reason.
  String? startBlockReason({String Function(DateTime)? formatDateTime}) {
    final t = _test;
    if (t == null) return 'Loading…';
    return TestLifecycle.startBlockReason(
      status: t.status,
      startsAt: t.startsAt,
      endsAt: t.endsAt,
      now: _clock(),
      formatDateTime: formatDateTime,
    );
  }

  /// Join codes are a sharing feature (Challenge with Friends / group); a
  /// Self test's stored code is not shown even if the row carries one.
  bool get showsJoinCode =>
      _test?.joinCode != null && TestMode.fromDb(_test?.testMode) != TestMode.self;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _test = await _tests.getById(testId);
      if (_test == null) _error = 'Test not found.';
      await _loadMyAttempts();
      // Batch state is known only from rpc_generate_results in this session
      // (the result_batches SELECT policy is group-permission based, so a
      // standalone owner cannot read the row); no table read here.
    } on AppError catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Publishes and reloads. Throws [AppError] with a user-facing message.
  Future<void> publish() => _action(() async {
        await _tests.publish(testId);
        await load();
      });

  /// Soft-deletes a draft (server-enforced rule). The gate is re-checked here
  /// so a stale screen cannot fire the RPC for a non-draft; on success the
  /// local test is cleared so nothing on this screen can act on it again.
  /// Throws [AppError] with a user-facing message; the test stays loaded on
  /// failure so the screen keeps showing it.
  Future<void> deleteDraft() => _action(() async {
        if (!canDelete) {
          throw const ValidationError(message: 'Only your draft tests can be deleted.');
        }
        await _tests.deleteDraft(testId);
        _test = null;
        _deleted = true;
      });

  bool _deleted = false;

  /// True once this test was deleted in this session.
  bool get isDeleted => _deleted;

  // ── attempt policy (presentation; the server re-derives it) ──
  List<Attempt> _myAttempts = const [];
  bool _attemptsLoadFailed = false;

  /// True when the own-attempts read failed; the CTA then falls back to a
  /// plain start and the server's answer (resume / error) is authoritative.
  bool get attemptsLoadFailed => _attemptsLoadFailed;

  AttemptPolicyState? get attemptState => _test == null
      ? null
      : AttemptPolicyState(
          settings: AttemptSettings.fromSettings(_test!.settings),
          attempts: _myAttempts,
        );

  Future<void> _loadMyAttempts() async {
    if (_test == null) return;
    try {
      _myAttempts = await _attempts.mine(testId);
      _attemptsLoadFailed = false;
    } catch (e) {
      AppLogger.warning('Own attempts unavailable for $testId: $e');
      _myAttempts = const [];
      _attemptsLoadFailed = true;
    }
  }

  /// Starts attempt 1 or resumes the in_progress attempt. Never allocates
  /// attempt N+1: after a completed attempt the server answers
  /// ATTEMPT_ALREADY_COMPLETED, and the UI does not offer this action then.
  Future<LaunchedAttempt> start() => _action(() => _launch(reattempt: false));

  /// Explicit re-attempt: the only path that requests attempt N+1. Gated
  /// here for UX; enforced by the server (REATTEMPT_LIMIT_REACHED).
  Future<LaunchedAttempt> reattempt() => _action(() async {
        final s = attemptState;
        if (s != null && !_attemptsLoadFailed && !s.canReattempt) {
          throw const ValidationError(message: 'Re-attempt is not available for this test.');
        }
        return _launch(reattempt: true);
      });

  Future<LaunchedAttempt> _launch({required bool reattempt}) async {
    final started = await _attempts.start(testId, reattempt: reattempt);
    final qs = await _questions.safeQuestions(started.attempt.testId);
    return (started: started, questions: qs, test: _test!);
  }

  /// Requests generation; the returned batch (from the RPC JSON) is the
  /// authoritative state and is kept for display / button gating.
  Future<ResultBatch> generateResults() => _action(() async {
        final batch = await _results.generateResults(testId);
        _batch = batch;
        return batch;
      });

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
