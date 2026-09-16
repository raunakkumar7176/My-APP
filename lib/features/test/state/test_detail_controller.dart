import '../../../core/errors/app_error.dart';
import '../../../core/models/question.dart';
import '../../../core/models/result_batch.dart';
import '../../../core/models/test.dart';
import '../../../core/services/auth_service.dart';
import '../data/attempt_repository.dart';
import '../data/question_repository.dart';
import '../data/result_repository.dart';
import '../data/test_repository.dart';
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

  /// Starts (or resumes) an attempt and loads the safe questions.
  Future<LaunchedAttempt> start() => _action(() async {
        final started = await _attempts.start(testId);
        final qs = await _questions.safeQuestions(started.attempt.testId);
        return (started: started, questions: qs, test: _test!);
      });

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
