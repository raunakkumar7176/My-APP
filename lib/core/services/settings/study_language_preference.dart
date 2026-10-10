import 'package:shared_preferences/shared_preferences.dart';

import '../../logging/app_logger.dart';

/// Persists the user's chosen content language ('en'/'hi') for My Study —
/// Study Home, Subject→Chapters, Chapter Hub, Topic Theory, and Topic
/// Practice each used to keep their OWN local 'en'-default language state,
/// so picking Hindi on one screen reset back to English the moment the user
/// navigated to the next one. This is the single source of truth all five
/// now read on init and write through on toggle, so the choice survives
/// navigation and app restarts.
final class StudyLanguagePreference {
  StudyLanguagePreference._();
  static final StudyLanguagePreference instance = StudyLanguagePreference._();

  static const _prefsKey = 'study_language_code';

  String _languageCode = 'en';
  String get languageCode => _languageCode;

  /// Loads the persisted choice, if any. Call once before `runApp` so every
  /// My Study screen's first load already uses the right language.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      instance._languageCode = prefs.getString(_prefsKey) ?? 'en';
    } catch (e, st) {
      AppLogger.error('StudyLanguagePreference.initialize failed: $e', stackTrace: st);
      instance._languageCode = 'en';
    }
  }

  Future<void> setLanguage(String code) async {
    if (_languageCode == code) return;
    _languageCode = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code);
    } catch (e, st) {
      AppLogger.error('StudyLanguagePreference.setLanguage persist failed: $e', stackTrace: st);
    }
  }
}
