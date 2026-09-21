import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';

/// Persists and broadcasts the app's [ThemeMode]. Default is light (product
/// requirement), never the OS setting, until the user picks otherwise.
///
/// Follows the same static-service + ChangeNotifier shape as the rest of the
/// app's core services (`AuthService`, `ProfileService`): a single source of
/// truth, no state-management package.
final class ThemeService extends ChangeNotifier {
  ThemeService._();

  static final ThemeService instance = ThemeService._();

  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Loads the persisted choice, if any. Call once before `runApp` so the
  /// first frame already renders the right theme (no flash of the default).
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      instance._mode = _fromStored(stored) ?? ThemeMode.light;
    } catch (e, st) {
      AppLogger.error('ThemeService.initialize failed: $e', stackTrace: st);
      instance._mode = ThemeMode.light;
    }
    instance._loaded = true;
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (e, st) {
      AppLogger.error('ThemeService.setMode persist failed: $e', stackTrace: st);
    }
  }

  static ThemeMode? _fromStored(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }
}
