/// Model for the `notification_settings` table. Maps to the existing
/// server-side schema with per-category toggles, push, and quiet hours.
final class NotificationSettings {
  const NotificationSettings({
    required this.userId,
    this.notificationsEnabled = true,
    this.testReminders = true,
    this.liveTestInvitations = true,
    this.testResults = true,
    this.groupAnnouncements = true,
    this.groupMessages = true,
    this.routineReminders = true,
    this.aiReports = true,
    this.systemUpdates = true,
    this.testInvitations = true,
    this.badgeEnabled = true,
    this.pushEnabled = false,
    this.quietHoursEnabled = false,
    this.quietFrom = '22:00',
    this.quietTo = '07:00',
  });

  final String userId;
  final bool notificationsEnabled;
  final bool testReminders;
  final bool liveTestInvitations;
  final bool testResults;
  final bool groupAnnouncements;
  final bool groupMessages;
  final bool routineReminders;
  final bool aiReports;
  final bool systemUpdates;
  final bool testInvitations;
  final bool badgeEnabled;
  final bool pushEnabled;
  final bool quietHoursEnabled;
  final String quietFrom;
  final String quietTo;

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      userId: json['user_id'] as String,
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      testReminders: json['test_reminders'] as bool? ?? true,
      liveTestInvitations: json['live_test_invitations'] as bool? ?? true,
      testResults: json['test_results'] as bool? ?? true,
      groupAnnouncements: json['group_announcements'] as bool? ?? true,
      groupMessages: json['group_messages'] as bool? ?? true,
      routineReminders: json['routine_reminders'] as bool? ?? true,
      aiReports: json['ai_reports'] as bool? ?? true,
      systemUpdates: json['system_updates'] as bool? ?? true,
      testInvitations: json['test_invitations'] as bool? ?? true,
      badgeEnabled: json['badge_enabled'] as bool? ?? true,
      pushEnabled: json['push_enabled'] as bool? ?? false,
      quietHoursEnabled: json['quiet_hours_enabled'] as bool? ?? false,
      quietFrom: json['quiet_from'] as String? ?? '22:00',
      quietTo: json['quiet_to'] as String? ?? '07:00',
    );
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'notifications_enabled': notificationsEnabled,
      'test_reminders': testReminders,
      'live_test_invitations': liveTestInvitations,
      'test_results': testResults,
      'group_announcements': groupAnnouncements,
      'group_messages': groupMessages,
      'routine_reminders': routineReminders,
      'ai_reports': aiReports,
      'system_updates': systemUpdates,
      'test_invitations': testInvitations,
      'badge_enabled': badgeEnabled,
      'push_enabled': pushEnabled,
      'quiet_hours_enabled': quietHoursEnabled,
      'quiet_from': quietFrom,
      'quiet_to': quietTo,
    };
  }

  NotificationSettings copyWith({
    bool? notificationsEnabled,
    bool? testReminders,
    bool? liveTestInvitations,
    bool? testResults,
    bool? groupAnnouncements,
    bool? groupMessages,
    bool? routineReminders,
    bool? aiReports,
    bool? systemUpdates,
    bool? testInvitations,
    bool? badgeEnabled,
    bool? pushEnabled,
    bool? quietHoursEnabled,
    String? quietFrom,
    String? quietTo,
  }) {
    return NotificationSettings(
      userId: userId,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      testReminders: testReminders ?? this.testReminders,
      liveTestInvitations: liveTestInvitations ?? this.liveTestInvitations,
      testResults: testResults ?? this.testResults,
      groupAnnouncements: groupAnnouncements ?? this.groupAnnouncements,
      groupMessages: groupMessages ?? this.groupMessages,
      routineReminders: routineReminders ?? this.routineReminders,
      aiReports: aiReports ?? this.aiReports,
      systemUpdates: systemUpdates ?? this.systemUpdates,
      testInvitations: testInvitations ?? this.testInvitations,
      badgeEnabled: badgeEnabled ?? this.badgeEnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietFrom: quietFrom ?? this.quietFrom,
      quietTo: quietTo ?? this.quietTo,
    );
  }
}
