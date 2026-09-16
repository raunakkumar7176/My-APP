/// Product-level test types. Labels here are the ONLY user-facing names.
/// Storage representation lives in [BackendMapping]; never compare a kind
/// against a raw `test_mode` string outside that file.
enum TestKind {
  self,
  challengeWithFriends,
  group,
  practice,
  quick,
  sectional,

  /// Reserved for a future phase; no creation path exposes it.
  adaptive;

  String get label {
    switch (this) {
      case TestKind.self:
        return 'Self';
      case TestKind.challengeWithFriends:
        return 'Challenge with Friends';
      case TestKind.group:
        return 'Group Test';
      case TestKind.practice:
        return 'Practice Test';
      case TestKind.quick:
        return 'Quick Test';
      case TestKind.sectional:
        return 'Sectional Test';
      case TestKind.adaptive:
        return 'Adaptive Test';
    }
  }

  /// Kinds a user can pick when creating a test today.
  static const creatable = [
    TestKind.self,
    TestKind.practice,
    TestKind.quick,
    TestKind.sectional,
    TestKind.challengeWithFriends,
    TestKind.group,
  ];

  /// Requires a group to be selected at creation.
  bool get requiresGroup => this == TestKind.group;

  /// Can be joined with an access/join code (server verifies the code).
  bool get supportsCodeEntry => this == TestKind.challengeWithFriends;

  /// Practice/Quick use the lightweight submit flow (no reflection step).
  bool get isLightweightFlow =>
      this == TestKind.practice || this == TestKind.quick;
}
