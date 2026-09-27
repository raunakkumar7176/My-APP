/// Creation-time configuration that lives in `tests.settings` jsonb next to
/// `test_kind` / attempt keys (the established per-test config store; no
/// schema change). Every helper merges into the existing map and never drops
/// keys it does not own.
library;

/// Late-join window (Challenge with Friends / Group Test). The boolean
/// `tests.allow_late_join` column keeps meaning "late join allowed at all";
/// the window length lives in `settings.late_join_minutes`.
///
/// Server rule (core function, v2): with late join allowed, a NEW attempt is
/// accepted while `now() <= starts_at + minutes`; after that
/// LATE_JOIN_WINDOW_CLOSED. `ends_at` stays a hard block; an in_progress
/// attempt is always resumable.
final class LateJoinSettings {
  const LateJoinSettings({this.enabled = true, this.minutes = defaultMinutes});

  static const key = 'late_join_minutes';
  static const defaultMinutes = 10;
  static const allowedMinutes = [5, 10, 15, 30];
  static const defaults = LateJoinSettings();

  final bool enabled;
  final int minutes;

  static LateJoinSettings fromTest({
    required bool allowLateJoin,
    Map<String, dynamic>? settings,
  }) {
    final raw = settings?[key];
    final m = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    return LateJoinSettings(
      enabled: allowLateJoin,
      minutes: (m == null || m < 0) ? defaultMinutes : m,
    );
  }

  Map<String, dynamic> applyTo(Map<String, dynamic>? existing) => {
    ...?existing,
    key: minutes,
  };

  /// Presentation mirror of the server boundary (instants; zone-agnostic).
  /// Returns true when a new participant may still join at [now].
  bool joinOpenAt({required DateTime? startsAt, required DateTime now}) {
    if (!enabled) return startsAt == null || !now.isAfter(startsAt);
    if (startsAt == null) return true;
    return !now.isAfter(startsAt.add(Duration(minutes: minutes)));
  }

  LateJoinSettings copyWith({bool? enabled, int? minutes}) => LateJoinSettings(
    enabled: enabled ?? this.enabled,
    minutes: minutes ?? this.minutes,
  );

  @override
  bool operator ==(Object other) =>
      other is LateJoinSettings &&
      other.enabled == enabled &&
      other.minutes == minutes;

  @override
  int get hashCode => Object.hash(enabled, minutes);
}

/// Mixed-difficulty distribution TARGET for the creator (`settings.question_config`).
/// It is a target, not a generator: the review/publish step compares it
/// with the actual question difficulties and reports the gap truthfully.
final class QuestionConfig {
  const QuestionConfig({
    this.total = 0,
    this.easy = 0,
    this.medium = 0,
    this.hard = 0,
  });

  static const key = 'question_config';
  static const none = QuestionConfig();

  final int total;
  final int easy;
  final int medium;
  final int hard;

  bool get isSet => total > 0;
  int get sum => easy + medium + hard;

  /// Easy + Medium + Hard must equal Total (when a target is set).
  bool get isValid =>
      !isSet ||
      (total > 0 && sum == total && easy >= 0 && medium >= 0 && hard >= 0);

  static QuestionConfig fromSettings(Map<String, dynamic>? settings) {
    final raw = settings?[key];
    if (raw is! Map) return none;
    int n(String k) {
      final v = raw[k];
      return v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    }

    return QuestionConfig(
      total: n('total'),
      easy: n('easy'),
      medium: n('medium'),
      hard: n('hard'),
    );
  }

  Map<String, dynamic> applyTo(Map<String, dynamic>? existing) {
    final out = {...?existing};
    if (isSet) {
      out[key] = {
        'total': total,
        'easy': easy,
        'medium': medium,
        'hard': hard,
        'type': 'mcq',
      };
    } else {
      out.remove(key);
    }
    return out;
  }

  /// Actual difficulty counts vs this target. [actual] keys: easy/medium/hard.
  DistributionCheck check(Map<String, int> actual) => DistributionCheck(
    target: this,
    easy: actual['easy'] ?? 0,
    medium: actual['medium'] ?? 0,
    hard: actual['hard'] ?? 0,
  );

  QuestionConfig copyWith({int? total, int? easy, int? medium, int? hard}) =>
      QuestionConfig(
        total: total ?? this.total,
        easy: easy ?? this.easy,
        medium: medium ?? this.medium,
        hard: hard ?? this.hard,
      );

  @override
  bool operator ==(Object other) =>
      other is QuestionConfig &&
      other.total == total &&
      other.easy == easy &&
      other.medium == medium &&
      other.hard == hard;

  @override
  int get hashCode => Object.hash(total, easy, medium, hard);
}

/// Truthful comparison of actual questions against a [QuestionConfig].
final class DistributionCheck {
  const DistributionCheck({
    required this.target,
    required this.easy,
    required this.medium,
    required this.hard,
  });

  final QuestionConfig target;
  final int easy;
  final int medium;
  final int hard;

  int get total => easy + medium + hard;
  bool get satisfied =>
      easy == target.easy && medium == target.medium && hard == target.hard;

  String get summary =>
      'Easy $easy/${target.easy} · Medium $medium/${target.medium} · Hard $hard/${target.hard} '
      '($total/${target.total})';
}

/// Whether the timer forces a submission at 00:00 (`settings.auto_submit`).
/// Defaults to true (matches every kind's behaviour before this setting
/// existed, so an absent key is never a behaviour change for an existing
/// test). When false, `TestTakingScreen` still locks further answering at
/// the deadline but leaves the actual submit tap to the student instead of
/// calling it automatically — the server-side deadline enforcement
/// (`deadline_at`, late-submission handling in `rpc_submit_and_score_test`)
/// is unaffected either way.
final class AutoSubmitSettings {
  const AutoSubmitSettings({this.enabled = true});

  static const key = 'auto_submit';
  static const defaults = AutoSubmitSettings();

  final bool enabled;

  static AutoSubmitSettings fromSettings(Map<String, dynamic>? settings) {
    final raw = settings?[key];
    return AutoSubmitSettings(enabled: raw is bool ? raw : true);
  }

  Map<String, dynamic> applyTo(Map<String, dynamic>? existing) => {
    ...?existing,
    key: enabled,
  };

  AutoSubmitSettings copyWith({bool? enabled}) =>
      AutoSubmitSettings(enabled: enabled ?? this.enabled);

  @override
  bool operator ==(Object other) =>
      other is AutoSubmitSettings && other.enabled == enabled;

  @override
  int get hashCode => enabled.hashCode;
}

/// Duration-driven schedule: the creator picks a start time and a duration;
/// the end is derived (`ends_at = starts_at + duration_sec`), never typed.
abstract final class ScheduleMath {
  static DateTime? endFor({
    required DateTime? startsAt,
    required int? durationSec,
  }) {
    if (startsAt == null || durationSec == null || durationSec <= 0) {
      return null;
    }
    return startsAt.add(Duration(seconds: durationSec));
  }
}
