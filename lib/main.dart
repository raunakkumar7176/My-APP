import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_config.dart';
import 'core/errors/error_handler.dart';
import 'core/logging/app_logger.dart';
import 'core/services/auth_service.dart';
import 'core/services/supabase_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    ErrorHandler.initialize();

    AppLogger.info('Starting application...');

    final config = AppConfig.fromEnvironment();
    AppConfig.initialize(config);
    AppLogger.info('Environment: ${config.environment.name}');

    try {
      await SupabaseService.initialize(config);
      AuthService.initialize();
    } catch (e) {
      AppLogger.error('Failed to initialize services: $e');
    }

    runApp(App(config: config));
  }, ErrorHandler.handleZoneError);
}
