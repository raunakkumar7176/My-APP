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

  /// V1 kinds a user can pick when creating a test. `self` and `quick` are
  /// no longer offered as standalone grid tiles: `self` is superseded by
  /// `practice` as the wizard's default general-purpose type, and `quick`
  /// is now reached via the one-tap "Quick Drill" preset button instead of
  /// a full grid tile (it still exists as a real [TestKind] underneath —
  /// no schema change, only the entry point moved). `adaptive` remains
  /// reserved (still parsed from stored rows; never offered).
  static const creatable = [
    TestKind.practice,
    TestKind.sectional,
    TestKind.challengeWithFriends,
    TestKind.group,
  ];

  /// Kinds a currently-edited draft may already hold even though they are
  /// no longer offered for NEW creation (`self`/`quick`, superseded above).
  /// The Basic Details tile list still renders these so an existing draft's
  /// selection is never silently hidden.
  static const _legacyCreatable = [TestKind.self, TestKind.quick];

  /// The tiles to render for the Test Type picker: [creatable], plus the
  /// currently-selected kind if it is a legacy one not otherwise offered.
  static List<TestKind> tilesFor(TestKind current) => [
        ...creatable,
        if (_legacyCreatable.contains(current)) current,
      ];

  /// Every kind a test LISTING may need to filter by — broader than
  /// [creatable]: existing tests can still be `self`/`quick` even though a
  /// new test can no longer be created as either, so the listing's filter
  /// chips must keep covering them. Only `adaptive` (never used by any real
  /// row) is excluded.
  static const filterable = [
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
        return 'Synchronized exam friends join with a 6-digit PIN.';
      case TestKind.group:
        return 'Scheduled test assigned to one of your groups.';
      case TestKind.sectional:
        return 'Subject-specific mock covering one or more chosen topics.';
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
  bool get requiresScope =>
      this == TestKind.practice ||
      this == TestKind.quick ||
      this == TestKind.sectional;

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
