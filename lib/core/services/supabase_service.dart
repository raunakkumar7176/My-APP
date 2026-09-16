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

    AppLogger.info('Initializing Supabase...');

    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
    );

    _client = Supabase.instance.client;
    AppLogger.info('Supabase initialized successfully.');
  }

  static Future<void> dispose() async {
    if (_client != null) {
      await _client!.dispose();
      _client = null;
      AppLogger.info('Supabase client disposed.');
    }
  }
}
