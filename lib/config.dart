abstract final class AppConfig {
  // Provide at build time: flutter run --dart-define=SUPABASE_URL=https://...
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  // Provide at build time: flutter run --dart-define=SUPABASE_ANON_KEY=...
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Base URL of the Node.js image-processing API.
  // Override at build time:
  //   flutter build web --dart-define=API_URL=https://your-api.example.com
  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000',
  );

  // Derived Supabase Storage base path (no trailing slash).
  static const String storageBaseUrl =
      '$supabaseUrl/storage/v1/object/public/images';

  static const String revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: 'test_qGsWqcsDcVGTWLyLdKZlDNFKymA',
  );

  static const int freePuzzleLimit = 3;

  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const String amplitudeApiKey = String.fromEnvironment('AMPLITUDE_API_KEY');

  static const String privacyPolicyUrl =
      'https://ucnacindrwptosfgkijv.supabase.co/storage/v1/object/public/legal/privacy-policy.html';
  static const String termsUrl =
      'https://ucnacindrwptosfgkijv.supabase.co/storage/v1/object/public/legal/terms.html';
  static const String cookiePolicyUrl =
      'https://ucnacindrwptosfgkijv.supabase.co/storage/v1/object/public/legal/cookie-policy.html';
}
