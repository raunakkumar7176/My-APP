import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

final class AppLogger {
  AppLogger._();

  static final Logger _logger = kReleaseMode
      ? Logger(level: Level.off)
      : Logger(
          printer: PrettyPrinter(
            methodCount: 0,
            errorMethodCount: 5,
            lineLength: 80,
            colors: true,
            printEmojis: true,
          ),
        );

  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  static void warning(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Logs the *shape* of an RPC response (runtime type, list length, and the
  /// sorted keys of the first row) — never any values — so the live RPC
  /// contract can be read off a device log without exposing answers, tokens
  /// or user data.
  static void rpcShape(String rpcName, Object? response) {
    _logger.i('$rpcName response shape: ${describeShape(response)}');
  }

  /// Pure helper behind [rpcShape]; exposed for tests.
  static String describeShape(Object? response) {
    if (response == null) return 'null';
    if (response is List) {
      if (response.isEmpty) return 'List(empty)';
      return 'List(len=${response.length}) first=${describeShape(response.first)}';
    }
    if (response is Map) {
      final keys = response.keys.map((k) => k.toString()).toList()..sort();
      return 'Map(keys=$keys)';
    }
    return response.runtimeType.toString();
  }
}
