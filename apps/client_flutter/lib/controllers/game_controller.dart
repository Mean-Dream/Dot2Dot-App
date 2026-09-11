import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GameController extends ChangeNotifier {
  // ── State ────────────────────────────────────────────────────────────────────

  bool isGameMode = false;
  bool isHardMode = false;
  bool isMediumMode = false;
  bool isGameOver = false;
  bool showConnections = false;
  bool showHint = false;

  int lives = 3;
  static const int maxLives = 3;

  int nextTargetIndex = 0;
  List<Offset> userPath = [];
  Set<int> wrongDotIndices = {};

  // ── Mutations ────────────────────────────────────────────────────────────────

  void setDifficulty(String level) {
    isHardMode = level == 'hard';
    isMediumMode = level == 'medium';
    wrongDotIndices.clear();
    notifyListeners();
  }

  /// Resets all in-game progress without exiting game mode.
  void resetProgress() {
    nextTargetIndex = 0;
    userPath = [];
    wrongDotIndices.clear();
    isGameOver = false;
    lives = maxLives;
    notifyListeners();
  }

  /// Called when the player exits or a new game starts.
  /// Pass [resumeIndex] > 0 to restore a saved position instead of starting from dot 1.
  void enterGame({required bool isMedium, required bool isHard, int resumeIndex = 0}) {
    isGameMode = true;
    isHardMode = isHard;
    isMediumMode = isMedium;
    showConnections = !(isMedium || isHard);
    showHint = false;
    resetProgress();
    if (resumeIndex > 0) nextTargetIndex = resumeIndex;
    notifyListeners();
  }

  void exitGame() {
    isGameMode = false;
    resetProgress();
  }

  /// Returns true if this tap hit the current target dot.
  bool processTap({
    required Offset localPos,
    required List<dynamic> dots, // List<Dot>
    required double canvasWidth,
  }) {
    if (nextTargetIndex >= dots.length) return false;
    final scale = canvasWidth / 1024.0;
    final target = dots[nextTargetIndex];
    final targetPos = Offset(target.x * scale, target.y * scale);
    final distance = (localPos - targetPos).distance;

    if (distance < 45.0) {
      nextTargetIndex++;
      wrongDotIndices.clear();
      HapticFeedback.lightImpact();
      notifyListeners();
      return true;
    }

    // Check if the player hit a wrong dot
    for (int i = nextTargetIndex + 1; i < dots.length; i++) {
      final dot = dots[i];
      final pos = Offset(dot.x * scale, dot.y * scale);
      if ((localPos - pos).distance < 15.0) {
        if (!wrongDotIndices.contains(i)) {
          lives--;
          wrongDotIndices.add(i);
          HapticFeedback.heavyImpact();
        }
        break;
      }
    }

    if (lives <= 0) isGameOver = true;
    notifyListeners();
    return false;
  }

  void consumeHintLife() {
    lives--;
    showHint = true;
    notifyListeners();
  }

  void dismissHint() {
    showHint = false;
    notifyListeners();
  }
}
