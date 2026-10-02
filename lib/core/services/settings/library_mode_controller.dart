import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../logging/app_logger.dart';
import '../push_notification_service.dart';

/// Central state and policy controller for Library Mode (Silent Study Shield).
///
/// Features:
/// 1. Manual Quick Toggle (Instant silence across all channels).
/// 2. Timer-Based "Focus Session" (e.g. 30m, 1h, 2h study sessions with countdown).
/// 3. Auto-Trigger integration during active study routine slots.
/// 4. Synchronizes with [PushNotificationService] to enforce muted audio and gentle haptics.
class LibraryModeController extends ChangeNotifier {
  LibraryModeController._();
  static final LibraryModeController instance = LibraryModeController._();

  static const String _keyEnabled = 'is_library_mode_enabled';
  static const String _keySessionEnd = 'library_mode_session_end_ms';
  static const String _keyAutoRoutine = 'library_mode_auto_routine_enabled';

  bool _isLibraryMode = false;
  DateTime? _sessionEndTime;
  bool _autoRoutineEnabled = true;
  Timer? _countdownTimer;

  bool get isLibraryMode => _isLibraryMode;
  DateTime? get sessionEndTime => _sessionEndTime;
  bool get autoRoutineEnabled => _autoRoutineEnabled;

  /// Returns the remaining focus session duration, or null if no timer is active.
  Duration? get remainingTime {
    if (_sessionEndTime == null) return null;
    final diff = _sessionEndTime!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Formatted remaining time e.g. "01:45:20" or "45m".
  String? get formattedRemainingTime {
    final rem = remainingTime;
    if (rem == null) return null;
    final hours = rem.inHours;
    final minutes = rem.inMinutes.remainder(60);
    final seconds = rem.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Initializes persisted state on startup.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isLibraryMode = prefs.getBool(_keyEnabled) ?? false;
      _autoRoutineEnabled = prefs.getBool(_keyAutoRoutine) ?? true;

      final sessionEndMs = prefs.getInt(_keySessionEnd);
      if (sessionEndMs != null) {
        final end = DateTime.fromMillisecondsSinceEpoch(sessionEndMs);
        if (end.isAfter(DateTime.now())) {
          _sessionEndTime = end;
          _isLibraryMode = true;
          _startCountdownTimer();
        } else {
          // Session expired while app was closed
          await prefs.remove(_keySessionEnd);
          _sessionEndTime = null;
          _isLibraryMode = false;
          await prefs.setBool(_keyEnabled, false);
        }
      }
      notifyListeners();
    } catch (e) {
      AppLogger.warning('LibraryModeController init failed: $e');
    }
  }

  /// Toggles Library Mode on or off manually.
  Future<void> toggleLibraryMode() async {
    await setLibraryMode(!_isLibraryMode);
  }

  /// Sets Library Mode status.
  Future<void> setLibraryMode(bool enabled) async {
    if (_isLibraryMode == enabled && _sessionEndTime == null) return;
    _isLibraryMode = enabled;
    if (!enabled) {
      _sessionEndTime = null;
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, enabled);
      if (!enabled) {
        await prefs.remove(_keySessionEnd);
      }
      // Reconfigure push notification channels to reflect silent/normal state
      await PushNotificationService.instance.setLibraryMode(enabled);
    } catch (e) {
      AppLogger.warning('Failed to persist library mode: $e');
    }
  }

  /// Starts a timed focus session (e.g. 1 hour, 2 hours).
  /// Automatically disables library mode when the duration elapses.
  Future<void> startFocusSession(Duration duration) async {
    final now = DateTime.now();
    _sessionEndTime = now.add(duration);
    _isLibraryMode = true;
    _startCountdownTimer();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, true);
      await prefs.setInt(_keySessionEnd, _sessionEndTime!.millisecondsSinceEpoch);
      await PushNotificationService.instance.setLibraryMode(true);
    } catch (e) {
      AppLogger.warning('Failed to start focus session: $e');
    }
  }

  /// Stops an active focus session and restores normal audio.
  Future<void> stopFocusSession() async {
    await setLibraryMode(false);
  }

  /// Updates whether Routine slots should auto-trigger Library Mode.
  Future<void> setAutoRoutineEnabled(bool enabled) async {
    if (_autoRoutineEnabled == enabled) return;
    _autoRoutineEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoRoutine, enabled);
    } catch (e) {
      AppLogger.warning('Failed to save auto routine preference: $e');
    }
  }

  /// Routine slot automation callback: called during routine evaluation.
  Future<void> handleRoutineSlotChange({required bool isStudySlotActive}) async {
    if (!_autoRoutineEnabled) return;
    // Don't override an explicit manual timer session
    if (_sessionEndTime != null && _sessionEndTime!.isAfter(DateTime.now())) return;

    if (isStudySlotActive && !_isLibraryMode) {
      await setLibraryMode(true);
    } else if (!isStudySlotActive && _isLibraryMode && _sessionEndTime == null) {
      await setLibraryMode(false);
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sessionEndTime == null) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(_sessionEndTime!)) {
        timer.cancel();
        _sessionEndTime = null;
        setLibraryMode(false);
      } else {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}
