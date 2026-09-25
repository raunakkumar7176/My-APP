import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app_config.dart';
import '../logging/app_logger.dart';

final class SupabaseService {
  SupabaseService._();

  static SupabaseClient? _client;

  static SupabaseClient get client {
    if (_client == null) {
      throw StateError(
        'SupabaseClient not initialized. Call SupabaseService.initialize() first.',
      );
    }
    return _client!;
  }

  static bool get isInitialized => _client != null;

  @visibleForTesting
  static void setClientForTesting(SupabaseClient client) {
    _client = client;
  }

  static Future<void> initialize(AppConfig config) async {
    if (isInitialized) {
      AppLogger.warning('Supabase already initialized, skipping.');
      return;
    }

    if (config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) {
      throw ArgumentError(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be provided via compile-time environment variables.\n'
        'Run with: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
    // Never log the URL or key values themselves (the URL is not secret,
    // but there is no reason to put either in logs) — only that both were
    // actually supplied, which is what a misconfigured dart-define build
    // needs to diagnose.
    AppLogger.info('AUTH_DEBUG: Supabase URL configured');

    AppLogger.info('AUTH_DEBUG: Initializing Supabase...');

    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
    );

    _client = Supabase.instance.client;
    AppLogger.info('AUTH_DEBUG: Supabase initialized');
  }

  static Future<void> dispose() async {
    if (_client != null) {
      await _client!.dispose();
      _client = null;
      AppLogger.info('Supabase client disposed.');
    }
  }
}
