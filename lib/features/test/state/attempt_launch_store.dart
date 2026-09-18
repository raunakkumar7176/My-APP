import '../../../core/models/question.dart';
import '../../../core/models/result.dart';
import '../../../core/models/test.dart';
import '../data/attempt_repository.dart';

/// In-memory handoff between screens so routes can carry ids only.
///
/// Whoever starts an attempt (detail screen, join-by-code, repeat) puts the
/// server response here; the taking screen takes it. If the entry is missing
/// (cold start, deep link), the taking controller falls back to the server's
/// own resume semantics (`rpc_start_attempt` returns the in-progress attempt).
/// Likewise a fresh submission result is parked here for the result screen,
/// which otherwise reads the row via RLS.
abstract final class AttemptLaunchStore {
  static final Map<String, StartedAttempt> _starts = {};
  static final Map<String, List<Question>> _questions = {};
  static final Map<String, Test> _tests = {};
  static final Map<String, Result> _results = {};

  static void putLaunch({
    required StartedAttempt started,
    required List<Question> questions,
    required Test test,
  }) {
    final id = started.attempt.id;
    _starts[id] = started;
    _questions[id] = questions;
    _tests[id] = test;
  }

  static ({StartedAttempt started, List<Question> questions, Test test})?
  takeLaunch(String attemptId) {
    final s = _starts.remove(attemptId);
    final q = _questions.remove(attemptId);
    final t = _tests.remove(attemptId);
    if (s == null || q == null || t == null) return null;
    return (started: s, questions: q, test: t);
  }

  static void putResult(Result result) => _results[result.attemptId] = result;

  static Result? takeResult(String attemptId) => _results.remove(attemptId);

  static void clear() {
    _starts.clear();
    _questions.clear();
    _tests.clear();
    _results.clear();
  }
}
