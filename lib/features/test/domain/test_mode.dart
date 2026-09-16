/// Backend `tests.test_mode` values. This is a *storage* concept; the product
/// concept is [TestKind]. Only [BackendMapping] should translate between them.
enum TestMode {
  self('self'),
  live('live'),
  group('group');

  const TestMode(this.dbValue);

  /// Exact string stored in `tests.test_mode`.
  final String dbValue;

  static TestMode? fromDb(String? value) {
    for (final m in TestMode.values) {
      if (m.dbValue == value) return m;
    }
    return null;
  }
}
