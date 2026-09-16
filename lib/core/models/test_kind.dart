/// The specific kind of a Self-family test.
///
/// Storage: `tests.test_mode` stays `'self'`; the kind lives in
/// `tests.settings->>'test_kind'`. Anything missing/unknown is treated as
/// [self] for backward compatibility. Challenge with Friends (`test_mode =
/// 'live'`) and Group Test (`test_mode = 'group'`) are separate modes and
/// are not represented here.
enum TestKind {
  self,
  practice,
  quick,
  sectional;

  static const settingsKey = 'test_kind';

  /// Value written to `settings.test_kind`.
  String get dbValue => name;

  /// User-facing label.
  String get label {
    switch (this) {
      case TestKind.self:
        return 'Self';
      case TestKind.practice:
        return 'Practice Test';
      case TestKind.quick:
        return 'Quick Test';
      case TestKind.sectional:
        return 'Sectional Test';
    }
  }

  static TestKind fromDbValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'practice':
        return TestKind.practice;
      case 'quick':
        return TestKind.quick;
      case 'sectional':
        return TestKind.sectional;
      case 'self':
      default:
        return TestKind.self;
    }
  }

  /// Reads the kind from a `settings` jsonb map; null/invalid → [self].
  static TestKind fromSettings(Map<String, dynamic>? settings) {
    final raw = settings?[settingsKey];
    return fromDbValue(raw is String ? raw : null);
  }

  /// Returns a copy of [settings] with this kind written in and every other
  /// key preserved — never replace a test's settings with only `test_kind`.
  Map<String, dynamic> applyTo(Map<String, dynamic>? settings) {
    return {...?settings, settingsKey: dbValue};
  }
}

/// User-facing name for a test's type, combining `test_mode` and the
/// Self-family kind. Never returns raw DB values.
String testTypeLabel({required String? testMode, required TestKind kind}) {
  switch (testMode) {
    case 'live':
      return 'Challenge with Friends';
    case 'group':
      return 'Group Test';
    case 'self':
    case null:
      return kind.label;
    default:
      return 'Unknown';
  }
}
