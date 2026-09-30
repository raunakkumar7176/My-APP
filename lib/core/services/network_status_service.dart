import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// App-wide "do we currently have a network connection" signal. A single
/// `ChangeNotifier` singleton (matching every other app-wide service in
/// this codebase — `ThemeService`, `LocaleService`, `ProfileService` — no
/// Riverpod anywhere in this app), so a global overlay widget can listen
/// to it without every screen re-implementing its own connectivity check.
///
/// Deliberately reports connectivity TYPE changes (wifi/mobile/none), not
/// actual internet reachability — `connectivity_plus` can't prove a real
/// route to the internet exists (e.g. connected to a wifi with no
/// internet), only that the device has *a* network interface up. That is
/// the same tradeoff every "no internet" banner in a production app makes;
/// a full reachability probe (pinging a real server) would be a much
/// heavier, battery-costly addition for a Hobby-tier app like this one.
final class NetworkStatusService extends ChangeNotifier {
  NetworkStatusService._();
  static final NetworkStatusService instance = NetworkStatusService._();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// How many currently-mounted screens consider themselves "an active
  /// test in progress" — incremented/decremented by those screens
  /// (`TestTakingScreen`), never guessed here. While this is > 0, the
  /// global overlay shows a small non-intrusive banner instead of the
  /// full-screen motivating dialog, so a student's attempt is never
  /// covered or interrupted by it.
  int _activeTestScreenCount = 0;
  bool get isInActiveTest => _activeTestScreenCount > 0;

  void enterActiveTestScreen() {
    _activeTestScreenCount++;
  }

  void exitActiveTestScreen() {
    _activeTestScreenCount = (_activeTestScreenCount - 1).clamp(0, 1 << 30);
  }

  Future<void> initialize() async {
    if (_sub != null) return; // already initialized
    try {
      final initial = await Connectivity().checkConnectivity();
      _apply(initial);
    } catch (_) {
      // Best-effort — if the plugin itself fails to report, assume online
      // rather than blocking the whole app behind a false "offline" state.
    }
    _sub = Connectivity().onConnectivityChanged.listen(_apply);
  }

  /// Manual re-check, for the overlay's "Reconnect" button — the stream
  /// above already fires on real changes, but a user tapping the button
  /// expects an immediate re-evaluation, not a wait for the next event.
  Future<void> recheck() async {
    try {
      final result = await Connectivity().checkConnectivity();
      _apply(result);
    } catch (_) {
      // No-op — stays in whatever state it already was.
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online != _isOnline) {
      _isOnline = online;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
