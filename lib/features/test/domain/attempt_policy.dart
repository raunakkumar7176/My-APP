import '../../../core/models/attempt.dart';

/// Test-level re-attempt configuration, stored in `tests.settings`
/// (`allow_reattempt`, `max_attempts`). Mirrors the server rule in
/// `_fn_start_attempt_core`: allow_reattempt=false forces an effective
/// maximum of 1; otherwise max_attempts (V1 UI values: 1/2/3/5/10).
final class AttemptSettings {
  const AttemptSettings({this.allowReattempt = false, this.maxAttempts = 1});

  static const allowKey = 'allow_reattempt';
  static const maxKey = 'max_attempts';
  static const allowedMaxValues = [1, 2, 3, 5, 10];
  static const defaults = AttemptSettings();

  final bool allowReattempt;
  final int maxAttempts;

  /// The limit the server enforces.
  int get effectiveMax => allowReattempt ? (maxAttempts < 1 ? 1 : maxAttempts) : 1;

  static AttemptSettings fromSettings(Map<String, dynamic>? settings) {
    if (settings == null) return defaults;
    final allow = settings[allowKey];
    final max = settings[maxKey];
    return AttemptSettings(
      allowReattempt: allow is bool ? allow : allow?.toString() == 'true',
      maxAttempts: max is num ? max.toInt() : int.tryParse('${max ?? ''}') ?? 1,
    );
  }

  /// Merges into [existing] without dropping keys the client does not own
  /// (e.g. `test_kind`).
  Map<String, dynamic> applyTo(Map<String, dynamic>? existing) => {
        ...?existing,
        allowKey: allowReattempt,
        maxKey: effectiveMax,
      };

  AttemptSettings copyWith({bool? allowReattempt, int? maxAttempts}) => AttemptSettings(
        allowReattempt: allowReattempt ?? this.allowReattempt,
        maxAttempts: maxAttempts ?? this.maxAttempts,
      );

  @override
  bool operator ==(Object other) =>
      other is AttemptSettings &&
      other.allowReattempt == allowReattempt &&
      other.maxAttempts == maxAttempts;

  @override
  int get hashCode => Object.hash(allowReattempt, maxAttempts);
}

/// The one action the detail screen may offer for the current user.
enum AttemptCta {
  /// No attempt yet: plain start (server: first attempt needs no intent).
  startTest,

  /// An in_progress attempt exists: the server resumes it.
  continueTest,

  /// Latest attempt is terminal and another attempt is permitted: only an
  /// explicit re-attempt (p_reattempt = true) may create it.
  reattempt,

  /// Latest attempt is terminal and the limit is reached.
  limitReached,
}

/// Presentation of the user's attempts against the test's [AttemptSettings].
/// UX only — `_fn_start_attempt_core` re-derives the same answer with
/// `count(*)` of the user's attempts and raises REATTEMPT_LIMIT_REACHED /
/// ATTEMPT_ALREADY_COMPLETED.
final class AttemptPolicyState {
  const AttemptPolicyState({
    required this.settings,
    required this.attempts,
  });

  final AttemptSettings settings;

  /// The current user's attempts on this test (any status).
  final List<Attempt> attempts;

  int get used => attempts.length;
  int get max => settings.effectiveMax;

  Attempt? get inProgress {
    for (final a in attempts) {
      if (a.status == AttemptStatus.inProgress) return a;
    }
    return null;
  }

  /// Terminal attempts (submitted / auto_submitted / scored), newest first.
  List<Attempt> get completed => [
        for (final a in attempts)
          if (a.status != AttemptStatus.inProgress) a,
      ]..sort((x, y) => y.attemptNumber.compareTo(x.attemptNumber));

  Attempt? get latestCompleted => completed.isEmpty ? null : completed.first;

  bool get hasAnyAttempt => attempts.isNotEmpty;

  /// True only when the server would accept `p_reattempt = true`.
  bool get canReattempt =>
      inProgress == null && hasAnyAttempt && settings.allowReattempt && used < max;

  AttemptCta get cta {
    if (inProgress != null) return AttemptCta.continueTest;
    if (!hasAnyAttempt) return AttemptCta.startTest;
    return canReattempt ? AttemptCta.reattempt : AttemptCta.limitReached;
  }

  /// "Attempts N/M" — shown once at least one attempt exists.
  String get usageLabel => 'Attempts $used/$max';
}
