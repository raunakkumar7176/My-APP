enum Environment { dev, staging, production }

final class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.appName,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  final Environment environment;
  final String appName;
  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get isDev => environment == Environment.dev;
  bool get isStaging => environment == Environment.staging;
  bool get isProduction => environment == Environment.production;

  static AppConfig dev() => const AppConfig._(
        environment: Environment.dev,
        appName: 'My Preparation (Dev)',
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
      );

  static AppConfig staging() => const AppConfig._(
        environment: Environment.staging,
        appName: 'My Preparation (Staging)',
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
      );

  static AppConfig production() => const AppConfig._(
        environment: Environment.production,
        appName: 'My Preparation',
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
      );

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
