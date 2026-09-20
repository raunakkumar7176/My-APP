enum Environment { dev, staging, production }

/// Holds the current app configuration. Set once at startup via [initialize].
AppConfig? _currentConfig;

final class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.appName,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.nextApiUrl,
  });

  final Environment environment;
  final String appName;
  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Base URL of the Next.js server (no trailing slash).
  /// Used for AI generation and other server-side operations.
  final String nextApiUrl;

  bool get isDev => environment == Environment.dev;
  bool get isStaging => environment == Environment.staging;
  bool get isProduction => environment == Environment.production;

  static AppConfig dev() => const AppConfig._(
        environment: Environment.dev,
        appName: 'My Preparation (Dev)',
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
        nextApiUrl: String.fromEnvironment(
          'NEXT_API_URL',
          defaultValue: 'http://localhost:3000',
        ),
      );

  static AppConfig staging() => const AppConfig._(
        environment: Environment.staging,
        appName: 'My Preparation (Staging)',
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
        nextApiUrl: String.fromEnvironment(
          'NEXT_API_URL',
          defaultValue: 'https://my-prepration.vercel.app',
        ),
      );

  static AppConfig production() => const AppConfig._(
        environment: Environment.production,
        appName: 'My Preparation',
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
        nextApiUrl: String.fromEnvironment(
          'NEXT_API_URL',
          defaultValue: 'https://my-prepration.vercel.app',
        ),
      );

  /// The current app configuration. Throws if [initialize] was not called.
  static AppConfig get current {
    final c = _currentConfig;
    if (c == null) {
      throw StateError('AppConfig not initialized. Call AppConfig.initialize() first.');
    }
    return c;
  }

  /// Call once at app startup with the resolved config.
  static void initialize(AppConfig config) => _currentConfig = config;

  static AppConfig fromEnvironment() {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'staging':
        return staging();
      case 'production':
        return production();
      default:
        return dev();
    }
  }
}
