import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'controllers/game_controller.dart';
import 'controllers/editor_controller.dart';
import 'controllers/project_controller.dart';
import 'controllers/auth_controller.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';

// ── SupabaseService ────────────────────────────────────────────────────────────

final supabaseServiceProvider = Provider<SupabaseService>(
  (_) => SupabaseService(),
);

// ── ChangeNotifier bridge ──────────────────────────────────────────────────────
//
// Riverpod 3.x removed ChangeNotifierProvider.  These Notifier classes bridge
// the gap: the int state acts as a rebuild counter (incremented on every
// notifyListeners()), while the ChangeNotifier instance lives on the Notifier
// and is accessed via `.notifier.controller`.  Callers watch the provider to
// subscribe to rebuilds; they read `.notifier.controller` to access the state.

class _GameBridge extends Notifier<int> {
  late final GameController controller = GameController();

  @override
  int build() {
    controller.addListener(_tick);
    ref.onDispose(() {
      controller.removeListener(_tick);
      controller.dispose();
    });
    return 0;
  }

  void _tick() => state++;
}

class _EditorBridge extends Notifier<int> {
  late final EditorController controller = EditorController();

  @override
  int build() {
    controller.addListener(_tick);
    ref.onDispose(() {
      controller.removeListener(_tick);
      controller.dispose();
    });
    return 0;
  }

  void _tick() => state++;
}

class _ProjectBridge extends Notifier<int> {
  late ProjectController controller;

  @override
  int build() {
    controller = ProjectController(ref.read(supabaseServiceProvider));
    controller.addListener(_tick);
    ref.onDispose(() {
      controller.removeListener(_tick);
      controller.dispose();
    });
    return 0;
  }

  // Defer the state increment to a microtask so that ChangeNotifier
  // callbacks firing during a build phase don't trigger Riverpod's
  // "Tried to modify a provider while the widget tree was building" error.
  void _tick() => Future.microtask(() => state++);
}

class _AuthBridge extends Notifier<int> {
  late AuthController controller;

  @override
  int build() {
    controller = AuthController(ref.read(supabaseServiceProvider));
    controller.addListener(_tick);
    ref.onDispose(() {
      controller.removeListener(_tick);
      controller.dispose();
    });
    return 0;
  }

  void _tick() => Future.microtask(() => state++);
}

// ── Public providers ───────────────────────────────────────────────────────────

final gameControllerProvider =
    NotifierProvider<_GameBridge, int>(_GameBridge.new);

final editorControllerProvider =
    NotifierProvider<_EditorBridge, int>(_EditorBridge.new);

final projectControllerProvider =
    NotifierProvider<_ProjectBridge, int>(_ProjectBridge.new);

final authControllerProvider =
    NotifierProvider<_AuthBridge, int>(_AuthBridge.new);

// ── Theme ──────────────────────────────────────────────────────────────────────

class ThemeNotifier extends Notifier<String> {
  @override
  String build() {
    _loadSaved();
    return 'cosmic';
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('theme_id') ?? 'cosmic';
  }

  Future<void> setTheme(String id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('theme_id', id);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, String>(ThemeNotifier.new);
