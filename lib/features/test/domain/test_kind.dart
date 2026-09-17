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

  /// V1 kinds a user can pick when creating a test. Sectional and Adaptive
  /// are reserved (still parsed from stored rows; never offered).
  static const creatable = [
    TestKind.self,
    TestKind.practice,
    TestKind.quick,
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

/// Kind-specific creation behaviour (V1). One source of truth for which
/// configuration sections a kind shows and what it requires; the wizard,
/// readiness and the pre-test section all read from here.
extension TestKindCreation on TestKind {
  /// V1 label + one-line purpose for the picker and the pre-test section.
  String get purpose {
    switch (this) {
      case TestKind.self:
        return 'Individual test you take on your own schedule.';
      case TestKind.practice:
        return 'Practice against selected syllabus topics; repeat attempts allowed by default.';
      case TestKind.quick:
        return 'Short rapid test with a small target question count.';
      case TestKind.challengeWithFriends:
        return 'Scheduled test friends join with a code.';
      case TestKind.group:
        return 'Scheduled test assigned to one of your groups.';
      case TestKind.sectional:
      case TestKind.adaptive:
        return 'Reserved for a future release.';
    }
  }

  /// Scheduled kinds: start time + calculated end, late-join window,
  /// participant limit. Self-family kinds are open-ended (server deadline =
  /// now + duration).
  bool get isScheduled =>
      this == TestKind.challengeWithFriends || this == TestKind.group;

  /// Start time must be set before publishing.
  bool get requiresStartTime => isScheduled;

  /// A syllabus scope (>= 1 node) is mandatory before publishing.
  bool get requiresScope => this == TestKind.practice || this == TestKind.quick;

  /// Late-join window control is shown (defaults ON, 10 min).
  bool get supportsLateJoin => isScheduled;

  /// Max-participants control is shown.
  bool get supportsMaxParticipants => isScheduled;

  /// Join code is required (Challenge with Friends).
  bool get requiresJoinCode => this == TestKind.challengeWithFriends;

  /// Default attempt policy per kind (creator can change it).
  ({bool allowReattempt, int maxAttempts}) get defaultAttemptPolicy {
    switch (this) {
      case TestKind.practice:
        return (allowReattempt: true, maxAttempts: 3);
      default:
        return (allowReattempt: false, maxAttempts: 1);
    }
  }

  /// Upper bound the Quick configuration accepts for the total question target.
  int? get maxQuestionTarget => this == TestKind.quick ? 15 : null;
}
