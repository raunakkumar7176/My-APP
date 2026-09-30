import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';

/// Persists and broadcasts the app's [Locale]. Default is English until the
/// user picks otherwise — never silently follows the OS locale, matching
/// [ThemeService]'s same explicit-default philosophy.
///
/// Only 'en' and 'hi' are real, translated locales right now (see
/// `lib/l10n/app_en.arb` / `app_hi.arb`) — this covers Settings and the
/// Dashboard so far; most other screens still render in English regardless
/// of the selected locale because their strings haven't been localized yet.
/// That is a real, disclosed gap, not something this service hides.
final class LocaleService extends ChangeNotifier {
  LocaleService._();

  static final LocaleService instance = LocaleService._();

  static const _prefsKey = 'app_locale';
  static const supportedLocales = [Locale('en'), Locale('hi')];

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Loads the persisted choice, if any. Call once before `runApp` so the
  /// first frame already renders in the right language.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      instance._locale = supportedLocales.firstWhere(
        (l) => l.languageCode == stored,
        orElse: () => const Locale('en'),
      );
    } catch (e, st) {
      AppLogger.error('LocaleService.initialize failed: $e', stackTrace: st);
      instance._locale = const Locale('en');
    }
    instance._loaded = true;
  }

  Future<void> setLocale(Locale locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, locale.languageCode);
    } catch (e, st) {
      AppLogger.error('LocaleService.setLocale persist failed: $e', stackTrace: st);
    }
  }
}
