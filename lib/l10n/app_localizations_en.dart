// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionExam => 'EXAM & PREPARATION';

  @override
  String get settingsTargetExam => 'Target Exam';

  @override
  String get settingsDailyGoal => 'Daily Study Goal';

  @override
  String get settingsLanguage => 'Language & Medium';

  @override
  String get settingsSectionDisplay => 'DISPLAY & EXPERIENCE';

  @override
  String get settingsThemeMode => 'Theme Mode';

  @override
  String get settingsHaptic => 'Haptic Feedback (Vibration)';

  @override
  String get settingsHapticSubtitle =>
      'Vibrate on MCQ selection and test submission';

  @override
  String get settingsSoundEffects => 'Sound Effects';

  @override
  String get settingsSoundEffectsSubtitle =>
      'Audio cues for correct answers and streak bonuses';

  @override
  String get settingsSectionNudges => 'STUDY NUDGES & ALERTS';

  @override
  String get settingsRevisionReminder => 'Daily Revision Reminder';

  @override
  String settingsRevisionReminderSubtitle(String time) {
    return 'Daily at $time';
  }

  @override
  String get settingsPushPreferences => 'Push Notification Preferences';

  @override
  String get settingsPushPreferencesSubtitle =>
      'Group messages, announcements, test & routine reminders';

  @override
  String get settingsSectionPrivacy => 'PRIVACY & ACCESS';

  @override
  String get settingsGroupInvites => 'Allow Group Invites';

  @override
  String get settingsShowAgeBadge => 'Show Age Badge on Portfolio';

  @override
  String get settingsShowAgeBadgeSubtitle => 'Display calculated age publicly';

  @override
  String get settingsChangePassword => 'Change Password / Security';

  @override
  String get settingsChangePasswordSubtitle =>
      'Manage your password and active sessions';

  @override
  String get settingsSectionAbout => 'ABOUT & COMMUNITY';

  @override
  String get settingsAboutApp => 'About App & Founder Desk';

  @override
  String get settingsAboutAppSubtitle => 'Vision, founder message & pedagogy';

  @override
  String get settingsHelpDesk => 'Help Desk & Diagnostics';

  @override
  String get settingsHelpDeskSubtitle =>
      'Report bugs, sync issues, or ask questions';

  @override
  String get settingsClearCache => 'Clear Image Cache';

  @override
  String get settingsClearCacheSubtitle =>
      'Frees up space used by cached images';

  @override
  String get settingsClear => 'Clear';

  @override
  String get settingsTerms => 'Terms & Privacy Policy';

  @override
  String get settingsTermsSubtitle =>
      'Read our data and student security policies';

  @override
  String get settingsLogOut => 'Log Out';

  @override
  String get settingsRequestDeletion => 'Request Account Deletion';

  @override
  String get dashboardTodaySchedule => 'Today\'s Schedule';

  @override
  String get dashboardTodayRoutine => 'Today\'s Routine';

  @override
  String get dashboardViewRoutine => 'View Routine';

  @override
  String get dashboardViewAll => 'View All';

  @override
  String get dashboardPerformanceSnapshot => 'Performance Snapshot';

  @override
  String get dashboardAnalytics => 'Analytics';

  @override
  String get dashboardTestsAttempted => 'Tests Attempted';

  @override
  String get dashboardAverageScore => 'Average Score';

  @override
  String get dashboardAccuracyRate => 'Accuracy Rate';

  @override
  String get dashboardRecentTests => 'Recent Tests';

  @override
  String get dashboardAllPapers => 'All Papers';

  @override
  String get navHome => 'Home';

  @override
  String get navStudy => 'Study';

  @override
  String get navTests => 'Tests';

  @override
  String get navPerformance => 'Performance';

  @override
  String get navProfile => 'Profile';
}
