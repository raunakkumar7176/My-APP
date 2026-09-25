import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../state/attempt_controller.dart';

/// Event type strings sent to `rpc_record_integrity_event`. Kept as plain
/// strings (not re-encoded from a Dart enum) so the server's stored
/// `violations` entries stay self-describing without a lookup table.
abstract final class IntegrityEventType {
  static const appBackgrounded = 'app_backgrounded';
  static const multiWindowEntered = 'multi_window_entered';
}

/// Bridges native Android integrity signals (FLAG_SECURE toggling,
/// multi-window/split-screen detection) and Flutter-side app-lifecycle
/// transitions to [AttemptController.recordIntegrityEvent] — active only
/// while attached to a live, in-progress attempt screen.
///
/// Every mechanism here is detection/prevention only. The server
/// (`rpc_record_integrity_event`) is the sole authority on counts,
/// thresholds and any resulting auto-submit; this class never decides
/// anything itself, it only reports what the OS told it.
class TestIntegrityMonitor with WidgetsBindingObserver {
  TestIntegrityMonitor({
    required this.controller,
    MethodChannel? channel,
    this.inactiveGracePeriod = const Duration(seconds: 2),
  }) : _channel = channel ?? const MethodChannel('my_praperation/integrity');

  final AttemptController controller;
  final MethodChannel _channel;

  /// How long an `inactive` lifecycle state (a system dialog, notification
  /// shade, permission prompt — or the brief moment before `paused`) is
  /// given to return to `resumed` before it is escalated to a real event.
  /// Avoids the false positives called out for normal system transitions.
  final Duration inactiveGracePeriod;

  Timer? _inactiveDebounce;
  bool _attached = false;

  /// Enables FLAG_SECURE and starts observing lifecycle/multi-window
  /// signals. Call once when a live test screen is entered.
  void start() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onNativeCall);
    unawaited(_setSecure(true));
  }

  /// Disables FLAG_SECURE and stops observing. Call once when the live test
  /// screen is left (terminal submission or navigation away) — this must
  /// never remain active past the attempt screen's own lifetime, which is
  /// why the screen calls this from `dispose()`.
  void stop() {
    if (!_attached) return;
    _attached = false;
    _inactiveDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    unawaited(_setSecure(false));
  }

  Future<void> _setSecure(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecureFlag', {'enabled': enabled});
    } catch (_) {
      // Best-effort: screenshot prevention is defense-in-depth, not the
      // security boundary (the server-side deadline/idempotency checks
      // are) — a platform without this channel (web/desktop/iOS today)
      // must not crash or block the test.
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onMultiWindowModeChanged') {
      final args = call.arguments;
      final isMultiWindow =
          args is Map && args['isInMultiWindowMode'] == true;
      if (isMultiWindow) {
        controller.recordIntegrityEvent(IntegrityEventType.multiWindowEntered);
      }
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // A true backgrounding (user switched away) — the real signal,
        // reported immediately; cancel any pending "inactive" grace timer
        // so one transition is never reported twice.
        _inactiveDebounce?.cancel();
        controller.recordIntegrityEvent(IntegrityEventType.appBackgrounded);
      case AppLifecycleState.inactive:
        _inactiveDebounce?.cancel();
        _inactiveDebounce = Timer(inactiveGracePeriod, () {
          controller.recordIntegrityEvent(IntegrityEventType.appBackgrounded);
        });
      case AppLifecycleState.resumed:
        // Returning to the test is expected, good behaviour — purely local
        // (no server event), keeping calls to a minimum per the
        // performance requirement; just cancel any pending grace timer.
        _inactiveDebounce?.cancel();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
