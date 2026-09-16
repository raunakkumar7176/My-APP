import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

final class ErrorHandler {
  const ErrorHandler._();

  static void initialize() {
    FlutterError.onError = (details) {
      AppLogger.error(
        'Flutter Error',
        error: details.exception,
        stackTrace: details.stack,
      );
      developer.log(
        details.exceptionAsString(),
        name: 'FlutterError',
        error: details.exception,
        stackTrace: details.stack,
      );
    };
  }

  static Future<void> handleZoneError(Object error, StackTrace stackTrace) async {
    AppLogger.error(
      'Zone Error',
      error: error,
      stackTrace: stackTrace,
    );
    developer.log(
      'Uncaught zone error',
      name: 'ZoneError',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
