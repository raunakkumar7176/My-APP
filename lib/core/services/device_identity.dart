import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A random, persistent per-install identifier — generated once on first
/// launch and stored locally forever (until the app is uninstalled/data
/// cleared). Used only to tell "which physical install of the app" a
/// server-side action (single-device-login enforcement) is talking about;
/// it carries no other meaning and is never derived from real device
/// hardware info.
final class DeviceIdentity {
  DeviceIdentity._();

  static const _prefsKey = 'device_identity_id';
  static String? _cached;

  static Future<String> current() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }

    final generated = _generate();
    await prefs.setString(_prefsKey, generated);
    _cached = generated;
    return generated;
  }

  static String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
