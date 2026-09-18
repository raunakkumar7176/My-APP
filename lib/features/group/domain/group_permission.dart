/// The `public.app_permission` enum as defined by the migration set that
/// built the live database (0001_init; unchanged since). The G3 live audit
/// query confirms the list; nothing here is invented, and an unknown value
/// coming back from the server is kept as [unknown] rather than dropped.
enum GroupPermission {
  groupSettings('GROUP_SETTINGS'),
  manageMembers('MANAGE_MEMBERS'),
  manageRoles('MANAGE_ROLES'),
  createTest('CREATE_TEST'),
  editTest('EDIT_TEST'),
  generateQuestions('GENERATE_QUESTIONS'),
  reviewQuestions('REVIEW_QUESTIONS'),
  publishTest('PUBLISH_TEST'),
  scheduleTest('SCHEDULE_TEST'),
  generateResults('GENERATE_RESULTS'),
  viewGroupAnalytics('VIEW_GROUP_ANALYTICS'),
  sendAnnouncement('SEND_ANNOUNCEMENT'),
  unknown('');

  const GroupPermission(this.db);

  /// Exact database label.
  final String db;

  static GroupPermission fromDb(String? value) {
    final v = value?.trim().toUpperCase();
    for (final p in values) {
      if (p != unknown && p.db == v) return p;
    }
    return unknown;
  }

  /// The values the client may ever ask the server about.
  static const live = [
    groupSettings,
    manageMembers,
    manageRoles,
    createTest,
    editTest,
    generateQuestions,
    reviewQuestions,
    publishTest,
    scheduleTest,
    generateResults,
    viewGroupAnalytics,
    sendAnnouncement,
  ];
}

/// The caller's effective permissions in one group, as the server reports
/// them (`fn_has_permission`, which returns true for the owner without a
/// `role_permissions` row). This is a UX mirror: it decides what to show,
/// never what is allowed — the live RLS / functions decide that.
final class GroupPermissions {
  const GroupPermissions(this._granted);

  static const none = GroupPermissions({});

  final Set<GroupPermission> _granted;

  bool has(GroupPermission p) => _granted.contains(p);

  bool get canManageMembers => has(GroupPermission.manageMembers);
  bool get canManageRoles => has(GroupPermission.manageRoles);
  bool get canEditSettings => has(GroupPermission.groupSettings);

  Set<GroupPermission> get granted => Set.unmodifiable(_granted);

  @override
  String toString() =>
      'GroupPermissions(${_granted.map((p) => p.db).join(', ')})';
}
