// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get settingsSectionExam => 'परीक्षा और तैयारी';

  @override
  String get settingsTargetExam => 'लक्ष्य परीक्षा';

  @override
  String get settingsDailyGoal => 'दैनिक अध्ययन लक्ष्य';

  @override
  String get settingsLanguage => 'भाषा और माध्यम';

  @override
  String get settingsSectionDisplay => 'डिस्प्ले और अनुभव';

  @override
  String get settingsThemeMode => 'थीम मोड';

  @override
  String get settingsHaptic => 'हैप्टिक फीडबैक (वाइब्रेशन)';

  @override
  String get settingsHapticSubtitle =>
      'MCQ चुनने और टेस्ट जमा करने पर वाइब्रेट करें';

  @override
  String get settingsSoundEffects => 'साउंड इफेक्ट्स';

  @override
  String get settingsSoundEffectsSubtitle =>
      'सही उत्तर और स्ट्रीक बोनस पर ऑडियो संकेत';

  @override
  String get settingsSectionNudges => 'अध्ययन अनुस्मारक और अलर्ट';

  @override
  String get settingsRevisionReminder => 'दैनिक रिवीजन रिमाइंडर';

  @override
  String settingsRevisionReminderSubtitle(String time) {
    return 'रोज़ $time बजे';
  }

  @override
  String get settingsPushPreferences => 'पुश नोटिफिकेशन प्राथमिकताएं';

  @override
  String get settingsPushPreferencesSubtitle =>
      'ग्रुप संदेश, घोषणाएं, टेस्ट और रूटीन रिमाइंडर';

  @override
  String get settingsSectionPrivacy => 'गोपनीयता और पहुंच';

  @override
  String get settingsGroupInvites => 'ग्रुप आमंत्रण की अनुमति';

  @override
  String get settingsShowAgeBadge => 'प्रोफ़ाइल पर उम्र दिखाएं';

  @override
  String get settingsShowAgeBadgeSubtitle =>
      'गणना की गई उम्र सार्वजनिक रूप से दिखाएं';

  @override
  String get settingsChangePassword => 'पासवर्ड / सुरक्षा बदलें';

  @override
  String get settingsChangePasswordSubtitle =>
      'अपना पासवर्ड और सक्रिय सत्र प्रबंधित करें';

  @override
  String get settingsSectionAbout => 'ऐप और समुदाय के बारे में';

  @override
  String get settingsAboutApp => 'ऐप और फाउंडर डेस्क के बारे में';

  @override
  String get settingsAboutAppSubtitle =>
      'दृष्टिकोण, संस्थापक संदेश और शिक्षण पद्धति';

  @override
  String get settingsHelpDesk => 'हेल्प डेस्क और डायग्नोस्टिक्स';

  @override
  String get settingsHelpDeskSubtitle =>
      'बग रिपोर्ट करें, सिंक समस्याएं, या प्रश्न पूछें';

  @override
  String get settingsClearCache => 'इमेज कैश साफ़ करें';

  @override
  String get settingsClearCacheSubtitle =>
      'कैश की गई तस्वीरों द्वारा उपयोग की गई जगह खाली करता है';

  @override
  String get settingsClear => 'साफ़ करें';

  @override
  String get settingsTerms => 'नियम और गोपनीयता नीति';

  @override
  String get settingsTermsSubtitle =>
      'हमारी डेटा और छात्र सुरक्षा नीतियां पढ़ें';

  @override
  String get settingsLogOut => 'लॉग आउट';

  @override
  String get settingsRequestDeletion => 'खाता हटाने का अनुरोध करें';

  @override
  String get dashboardTodaySchedule => 'आज का शेड्यूल';

  @override
  String get dashboardTodayRoutine => 'आज की दिनचर्या';

  @override
  String get dashboardViewRoutine => 'दिनचर्या देखें';

  @override
  String get dashboardViewAll => 'सभी देखें';

  @override
  String get dashboardPerformanceSnapshot => 'प्रदर्शन स्नैपशॉट';

  @override
  String get dashboardAnalytics => 'विश्लेषण';

  @override
  String get dashboardTestsAttempted => 'दिए गए टेस्ट';

  @override
  String get dashboardAverageScore => 'औसत स्कोर';

  @override
  String get dashboardAccuracyRate => 'सटीकता दर';

  @override
  String get dashboardRecentTests => 'हाल के टेस्ट';

  @override
  String get dashboardAllPapers => 'सभी पेपर';

  @override
  String get navHome => 'होम';

  @override
  String get navStudy => 'अध्ययन';

  @override
  String get navTests => 'टेस्ट';

  @override
  String get navPerformance => 'प्रदर्शन';

  @override
  String get navProfile => 'प्रोफ़ाइल';
}
