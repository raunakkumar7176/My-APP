import 'test_kind.dart';
import 'test_mode.dart';

/// The single place where product kinds meet backend storage.
///
/// Storage rule (zero schema change):
///   Challenge with Friends → test_mode = 'live'
///   Group Test             → test_mode = 'group'
///   Self family            → test_mode = 'self' + settings.test_kind ∈
///                            {self, practice, quick, sectional, adaptive}
/// Unknown / missing settings resolve to [TestKind.self] for compatibility.
abstract final class BackendMapping {
  static const settingsKindKey = 'test_kind';

  /// Backend representation of a kind.
  static ({TestMode mode, String? settingsKind}) toBackend(TestKind kind) {
    switch (kind) {
      case TestKind.challengeWithFriends:
        return (mode: TestMode.live, settingsKind: null);
      case TestKind.group:
        return (mode: TestMode.group, settingsKind: null);
      case TestKind.self:
      case TestKind.practice:
      case TestKind.quick:
      case TestKind.sectional:
      case TestKind.adaptive:
        return (mode: TestMode.self, settingsKind: kind.name);
    }
  }

  /// Product kind from a stored row. Non-self modes ignore `settings`.
  static TestKind fromBackend(String? testMode, Map<String, dynamic>? settings) {
    switch (TestMode.fromDb(testMode)) {
      case TestMode.live:
        return TestKind.challengeWithFriends;
      case TestMode.group:
        return TestKind.group;
      case TestMode.self:
      case null:
        return _selfFamilyFromSettings(settings);
    }
  }

  static TestKind _selfFamilyFromSettings(Map<String, dynamic>? settings) {
    final raw = settings?[settingsKindKey];
    if (raw is! String) return TestKind.self;
    switch (raw.trim().toLowerCase()) {
      case 'practice':
        return TestKind.practice;
      case 'quick':
        return TestKind.quick;
      case 'sectional':
        return TestKind.sectional;
      case 'adaptive':
        return TestKind.adaptive;
      default:
        return TestKind.self;
    }
  }

  /// `settings` to persist for [kind], preserving every unrelated key of
  /// [existing]. Non-self kinds get `test_kind` removed (never a stale value).
  /// Returns null when nothing needs to be sent (non-self kind, no settings).
  static Map<String, dynamic>? settingsFor(
    TestKind kind,
    Map<String, dynamic>? existing,
  ) {
    final backend = toBackend(kind);
    if (backend.settingsKind != null) {
      return {...?existing, settingsKindKey: backend.settingsKind};
    }
    if (existing == null) return null;
    return {...existing}..remove(settingsKindKey);
  }
}
