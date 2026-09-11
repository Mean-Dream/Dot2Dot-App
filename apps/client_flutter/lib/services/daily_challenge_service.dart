import 'package:shared_preferences/shared_preferences.dart';
import '../models/project_model.dart';

abstract final class DailyChallengeService {
  static String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Picks today's puzzle deterministically from [projects].
  /// All users with the same project list see the same puzzle on the same day.
  static Project? getDailyProject(List<Project> projects) {
    if (projects.isEmpty) return null;
    final days = DateTime.now().difference(DateTime(2024, 1, 1)).inDays;
    return projects[days % projects.length];
  }

  static Future<bool> isCompletedToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('daily_completed_date') == _todayKey;
  }

  static Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('daily_streak') ?? 0;
  }

  /// Marks today's challenge complete and updates the streak.
  /// Safe to call multiple times — idempotent if already done today.
  static Future<int> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('daily_completed_date') == _todayKey) {
      return prefs.getInt('daily_streak') ?? 1;
    }

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    int streak = prefs.getInt('daily_streak') ?? 0;
    streak = (prefs.getString('daily_completed_date') == yKey) ? streak + 1 : 1;

    await prefs.setString('daily_completed_date', _todayKey);
    await prefs.setInt('daily_streak', streak);
    return streak;
  }
}
