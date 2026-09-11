import 'package:shared_preferences/shared_preferences.dart';

abstract final class ConsentService {
  static const _kAnalytics = 'consent_analytics';
  static const _kCrash = 'consent_crash';
  static const _kShown = 'consent_shown';

  // In-memory flags — set by loadFromPrefs() at startup and by save() when
  // the user makes a choice. Sentry's beforeSend reads these synchronously.
  static bool analyticsGranted = false;
  static bool crashGranted = false;

  /// Call once from main() before runApp. Populates the in-memory flags.
  static Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    analyticsGranted = p.getBool(_kAnalytics) ?? false;
    crashGranted = p.getBool(_kCrash) ?? false;
  }

  static Future<bool> isShown() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kShown) ?? false;
  }

  /// Persists the user's choice and updates in-memory flags immediately so
  /// Sentry's beforeSend and AnalyticsService react without a restart.
  static Future<void> save({
    required bool analytics,
    required bool crash,
  }) async {
    analyticsGranted = analytics;
    crashGranted = crash;
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setBool(_kAnalytics, analytics),
      p.setBool(_kCrash, crash),
      p.setBool(_kShown, true),
    ]);
  }
}
