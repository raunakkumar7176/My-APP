import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionExam.
  ///
  /// In en, this message translates to:
  /// **'EXAM & PREPARATION'**
  String get settingsSectionExam;

  /// No description provided for @settingsTargetExam.
  ///
  /// In en, this message translates to:
  /// **'Target Exam'**
  String get settingsTargetExam;

  /// No description provided for @settingsDailyGoal.
  ///
  /// In en, this message translates to:
  /// **'Daily Study Goal'**
  String get settingsDailyGoal;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language & Medium'**
  String get settingsLanguage;

  /// No description provided for @settingsSectionDisplay.
  ///
  /// In en, this message translates to:
  /// **'DISPLAY & EXPERIENCE'**
  String get settingsSectionDisplay;

  /// No description provided for @settingsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get settingsThemeMode;

  /// No description provided for @settingsHaptic.
  ///
  /// In en, this message translates to:
  /// **'Haptic Feedback (Vibration)'**
  String get settingsHaptic;

  /// No description provided for @settingsHapticSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibrate on MCQ selection and test submission'**
  String get settingsHapticSubtitle;

  /// No description provided for @settingsSoundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound Effects'**
  String get settingsSoundEffects;

  /// No description provided for @settingsSoundEffectsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Audio cues for correct answers and streak bonuses'**
  String get settingsSoundEffectsSubtitle;

  /// No description provided for @settingsSectionNudges.
  ///
  /// In en, this message translates to:
  /// **'STUDY NUDGES & ALERTS'**
  String get settingsSectionNudges;

  /// No description provided for @settingsRevisionReminder.
  ///
  /// In en, this message translates to:
  /// **'Daily Revision Reminder'**
  String get settingsRevisionReminder;

  /// No description provided for @settingsRevisionReminderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily at {time}'**
  String settingsRevisionReminderSubtitle(String time);

  /// No description provided for @settingsPushPreferences.
  ///
  /// In en, this message translates to:
  /// **'Push Notification Preferences'**
  String get settingsPushPreferences;

  /// No description provided for @settingsPushPreferencesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Group messages, announcements, test & routine reminders'**
  String get settingsPushPreferencesSubtitle;

  /// No description provided for @settingsSectionPrivacy.
  ///
  /// In en, this message translates to:
  /// **'PRIVACY & ACCESS'**
  String get settingsSectionPrivacy;

  /// No description provided for @settingsGroupInvites.
  ///
  /// In en, this message translates to:
  /// **'Allow Group Invites'**
  String get settingsGroupInvites;

  /// No description provided for @settingsShowAgeBadge.
  ///
  /// In en, this message translates to:
  /// **'Show Age Badge on Portfolio'**
  String get settingsShowAgeBadge;

  /// No description provided for @settingsShowAgeBadgeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Display calculated age publicly'**
  String get settingsShowAgeBadgeSubtitle;

  /// No description provided for @settingsChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password / Security'**
  String get settingsChangePassword;

  /// No description provided for @settingsChangePasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your password and active sessions'**
  String get settingsChangePasswordSubtitle;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'ABOUT & COMMUNITY'**
  String get settingsSectionAbout;

  /// No description provided for @settingsAboutApp.
  ///
  /// In en, this message translates to:
  /// **'About App & Founder Desk'**
  String get settingsAboutApp;

  /// No description provided for @settingsAboutAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vision, founder message & pedagogy'**
  String get settingsAboutAppSubtitle;

  /// No description provided for @settingsHelpDesk.
  ///
  /// In en, this message translates to:
  /// **'Help Desk & Diagnostics'**
  String get settingsHelpDesk;

  /// No description provided for @settingsHelpDeskSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Report bugs, sync issues, or ask questions'**
  String get settingsHelpDeskSubtitle;

  /// No description provided for @settingsClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Image Cache'**
  String get settingsClearCache;

  /// No description provided for @settingsClearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Frees up space used by cached images'**
  String get settingsClearCacheSubtitle;

  /// No description provided for @settingsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsClear;

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms & Privacy Policy'**
  String get settingsTerms;

  /// No description provided for @settingsTermsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read our data and student security policies'**
  String get settingsTermsSubtitle;

  /// No description provided for @settingsLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get settingsLogOut;

  /// No description provided for @settingsRequestDeletion.
  ///
  /// In en, this message translates to:
  /// **'Request Account Deletion'**
  String get settingsRequestDeletion;

  /// No description provided for @dashboardTodaySchedule.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Schedule'**
  String get dashboardTodaySchedule;

  /// No description provided for @dashboardTodayRoutine.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Routine'**
  String get dashboardTodayRoutine;

  /// No description provided for @dashboardViewRoutine.
  ///
  /// In en, this message translates to:
  /// **'View Routine'**
  String get dashboardViewRoutine;

  /// No description provided for @dashboardViewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get dashboardViewAll;

  /// No description provided for @dashboardPerformanceSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Performance Snapshot'**
  String get dashboardPerformanceSnapshot;

  /// No description provided for @dashboardAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get dashboardAnalytics;

  /// No description provided for @dashboardTestsAttempted.
  ///
  /// In en, this message translates to:
  /// **'Tests Attempted'**
  String get dashboardTestsAttempted;

  /// No description provided for @dashboardAverageScore.
  ///
  /// In en, this message translates to:
  /// **'Average Score'**
  String get dashboardAverageScore;

  /// No description provided for @dashboardAccuracyRate.
  ///
  /// In en, this message translates to:
  /// **'Accuracy Rate'**
  String get dashboardAccuracyRate;

  /// No description provided for @dashboardRecentTests.
  ///
  /// In en, this message translates to:
  /// **'Recent Tests'**
  String get dashboardRecentTests;

  /// No description provided for @dashboardAllPapers.
  ///
  /// In en, this message translates to:
  /// **'All Papers'**
  String get dashboardAllPapers;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navStudy.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get navStudy;

  /// No description provided for @navTests.
  ///
  /// In en, this message translates to:
  /// **'Tests'**
  String get navTests;

  /// No description provided for @navPerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get navPerformance;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
