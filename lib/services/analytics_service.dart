import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/events/base_event.dart';
import '../config.dart';

class AnalyticsService {
  static late final Amplitude _amp;

  static Future<void> initialize() async {
    _amp = Amplitude(Configuration(apiKey: AppConfig.amplitudeApiKey));
    await _amp.isBuilt;
  }

  static void identify(String userId) {
    _amp.setUserId(userId);
  }

  static void track(String event, [Map<String, dynamic>? properties]) {
    _amp.track(BaseEvent(event, eventProperties: properties));
  }

  // Named event helpers
  static void puzzleCreated() => track('puzzle_created');
  static void puzzlePlayed(String puzzleId) =>
      track('puzzle_played', {'puzzle_id': puzzleId});
  static void puzzleCompleted(String puzzleId) =>
      track('puzzle_completed', {'puzzle_id': puzzleId});
  static void exportAttempted() => track('export_attempted');
  static void paywallShown(String trigger) =>
      track('paywall_shown', {'trigger': trigger});
  static void subscriptionStarted() => track('subscription_started');
}
