import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_config.dart';
import 'core/errors/error_handler.dart';
import 'core/logging/app_logger.dart';
import 'core/services/auth_service.dart';
import 'core/services/locale_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/supabase_service.dart';
import 'core/services/theme_service.dart';

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
    await ThemeService.initialize();
    await LocaleService.initialize();

    runApp(App(config: config));

    // Push setup must never block app startup or crash it — e.g. before a
    // real google-services.json is configured, Firebase.initializeApp()
    // fails, and PushNotificationService.initialize() catches that and
    // simply leaves push disabled for this session. Started after the
    // first frame so cold start renders immediately.
    Future(() async {
      try {
        await PushNotificationService.instance.initialize();
      } catch (e) {
        AppLogger.error('Push notification setup failed: $e');
      }
    });
  }, ErrorHandler.handleZoneError);
}
