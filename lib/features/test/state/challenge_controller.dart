import 'dart:async';

import '../../../core/errors/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/models/challenge_session.dart';
import '../../../core/services/auth_service.dart';
import '../data/challenge_repository.dart';
import 'disposable_notifier.dart';

/// Orchestrates one Peer Challenge session end-to-end: create/join, the
/// waiting-room roster (live via Realtime), host commence, and the merit
/// list. All state comes from `challenge_sessions`/`challenge_participants`
/// (migration 0061) via [ChallengeRepository] — nothing here computes a
/// score, a rank, or a synchronized instant itself; those are the server's
/// (`rpc_commence_challenge_session` sets `commence_at`,
/// `rpc_get_challenge_merit_list` ranks).
class ChallengeController extends DisposableNotifier {
  ChallengeController({ChallengeRepository? repository})
      : _repo = repository ?? const SupabaseChallengeRepository();

  final ChallengeRepository _repo;

  ChallengeSession? _session;
  List<ChallengeParticipant> _roster = const [];
  List<ChallengeMeritRow> _meritList = const [];
  bool _loading = false;
  String? _error;

  ChallengeRosterSubscription? _rosterSub;
  ChallengeRosterSubscription? _sessionSub;

  ChallengeSession? get session => _session;
  List<ChallengeParticipant> get roster => _roster;
  List<ChallengeMeritRow> get meritList => _meritList;
  bool get isLoading => _loading;
  String? get error => _error;

  String? get _currentUserId => AuthService.currentUser?.id;
  bool get isHost => _session?.isHost(_currentUserId) ?? false;

  /// Host: mint a new session for [testId] and start listening.
  Future<void> createSession({
    required String? testId,
    required String title,
    required String subject,
    required int durationMinutes,
  }) => _run(() async {
    _session = await _repo.createSession(
      testId: testId,
      title: title,
      subject: subject,
      durationMinutes: durationMinutes,
    );
    _roster = await _repo.getRoster(_session!.id);
    _listen(_session!.id);
  });

  /// Candidate: join by PIN and start listening.
  Future<void> joinByPin(String pinCode) => _run(() async {
    final joined = await _repo.joinByPin(pinCode);
    // The join RPC's response is missing host_user_id; refresh from the row
    // so isHost/host display are correct.
    _session = await _repo.getSession(joined.id) ?? joined;
    _roster = await _repo.getRoster(_session!.id);
    _listen(_session!.id);
  });

  /// Re-attach to an already-known session (e.g. returning to the waiting
  /// room after backgrounding the app).
  Future<void> loadSession(String sessionId) => _run(() async {
    _session = await _repo.getSession(sessionId);
    if (_session == null) {
      throw const DataError(message: 'This session no longer exists.');
    }
    _roster = await _repo.getRoster(sessionId);
    _listen(sessionId);
  });

  void _listen(String sessionId) {
    _rosterSub?.cancel();
    _sessionSub?.cancel();
    _rosterSub = _repo.subscribeToRoster(
      sessionId: sessionId,
      onChange: (p) {
        final next = List<ChallengeParticipant>.from(_roster);
        final i = next.indexWhere((e) => e.id == p.id);
        if (i >= 0) {
          next[i] = p;
        } else {
          next.add(p);
        }
        _roster = next;
        notifyListeners();
      },
    );
    _sessionSub = _repo.subscribeToSession(
      sessionId: sessionId,
      onChange: (s) {
        _session = s;
        notifyListeners();
      },
    );
  }

  /// Host: broadcast the synchronized start (+5s lead, server clock).
  Future<void> commence() => _run(() async {
    final s = _session;
    if (s == null) return;
    _session = await _repo.commence(s.id);
  });

  /// Binds the caller's own participant row to the real attempt they just
  /// started for this session, so the exam and the merit list stay linked.
  Future<void> bindAttempt(String attemptId) async {
    final s = _session;
    if (s == null) return;
    try {
      await _repo.bindAttempt(sessionId: s.id, attemptId: attemptId);
    } catch (e) {
      AppLogger.warning('ChallengeController.bindAttempt failed: $e');
    }
  }

  /// Writes the caller's own result back once their attempt is scored.
  Future<void> reportResult({
    required double score,
    required double accuracy,
    required int timeTakenSeconds,
  }) async {
    final s = _session;
    if (s == null) return;
    try {
      await _repo.reportResult(
        sessionId: s.id,
        score: score,
        accuracy: accuracy,
        timeTakenSeconds: timeTakenSeconds,
      );
    } catch (e) {
      AppLogger.warning('ChallengeController.reportResult failed: $e');
    }
  }

  Future<void> loadMeritList() => _run(() async {
    final s = _session;
    if (s == null) return;
    _meritList = await _repo.getMeritList(s.id);
  });

  Future<void> _run(Future<void> Function() body) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await body();
    } on AppError catch (e) {
      _error = e.message;
    } catch (e, st) {
      AppLogger.error('ChallengeController unexpected: $e', stackTrace: st);
      _error = 'Something went wrong. Please try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _rosterSub?.cancel();
    _sessionSub?.cancel();
    super.dispose();
  }
}
