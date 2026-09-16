import 'package:flutter/foundation.dart';

/// [ChangeNotifier] whose [notifyListeners] is a no-op after [dispose].
///
/// The R4 controllers kick off async repository calls and notify when they
/// finish; if the screen was popped meanwhile (web evidence: "A
/// TestCreationController was used after being disposed"), the late
/// notification must be dropped instead of throwing.
abstract class DisposableNotifier extends ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
