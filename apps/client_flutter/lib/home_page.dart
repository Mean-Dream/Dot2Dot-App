import 'dart:async'; // For Timer
import 'dart:convert'; // For jsonEncode
import 'package:http/http.dart' as http; // For http.post
import 'package:flutter/material.dart';
import 'services/file_saver.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'config.dart';
import 'services/supabase_service.dart';
import 'models/dot_model.dart';
import 'services/pdf_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:shimmer/shimmer.dart';
import 'dart:math';
import '../models/project_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/scheduler.dart';
import 'package:confetti/confetti.dart';
import 'services/analytics_service.dart';
import 'services/purchase_service.dart';
import 'paywall_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'controllers/game_controller.dart';
import 'controllers/editor_controller.dart';
import 'controllers/project_controller.dart';
import 'models/undo_state.dart';
import 'services/offline_cache.dart';
import 'painters/dot_painter.dart';
import 'providers.dart';
import 'services/consent_service.dart';
import 'services/daily_challenge_service.dart';
import 'services/share_service.dart';
import 'theme/app_theme.dart';
import 'widgets/gallery_item.dart';

// ProjectState moved to models/undo_state.dart — re-exported here for
// any remaining references in this file during incremental migration.
export 'models/undo_state.dart' show ProjectState;

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with TickerProviderStateMixin {
  // â”€â”€ Controllers (provided via Riverpod) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  SupabaseService get _service => ref.read(supabaseServiceProvider);
  GameController get _gc => ref.read(gameControllerProvider.notifier).controller;
  EditorController get _ec => ref.read(editorControllerProvider.notifier).controller;
  ProjectController get _pc => ref.read(projectControllerProvider.notifier).controller;

  // â”€â”€ Animation controllers (require vsync: this) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  late ConfettiController _confettiController;
  late AnimationController _rippleController;
  late AnimationController _heartShakeController;
  Offset? _lastErasedPos;

  // â”€â”€ Text / transformation controllers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  late TransformationController _transformationController;
  late TextEditingController _nameController;
  double _currentScale = 1.0;

  // â”€â”€ Navigation & layout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _isInPuzzle = false;
  String? _currentMenuPath;
  double boxSize = 600;

  // â”€â”€ Daily challenge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _isDailyChallenge = false;
  bool _isDailyCompleted = false;
  int _dailyStreak = 0;

  // â”€â”€ UI overlays â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _mainStatus = '';
  String _subStatus = '';
  bool _isEditingName = false;
  bool _isSidebarOpen = true;
  bool _isDragging = false;
  int _activePointers = 0;

  // â”€â”€ Focus & input â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final FocusNode _mainFocusNode = FocusNode();
  Offset? _debugMousePos;
  final ValueNotifier<Offset?> _mousePosNotifier = ValueNotifier(null);
  final GlobalKey _canvasKey = GlobalKey();

  // â”€â”€ Timers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Timer? _autoSaveTimer;
  Timer? _debounce;
  Timer? _hintTimer;
  Timer? _loadingTimer;
  Timer? _wrongDotTimer;
  RealtimeChannel? _processingChannel;

  // â”€â”€ Loading tips carousel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  int _tipIndex = 0;
  final List<String> _processingTips = [
    "Uploading image to AI engine...",
    "AI: Identifying subject and removing background...",
    "AI: Tracing high-contrast edges...",
    "Tip: Use portraits with clear lighting for best results!",
    "Calculating optimal dot spacing...",
    "Finalizing your printable puzzle...",
  ];

  // â”€â”€ GameController delegates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool get _isGameMode => _gc.isGameMode;
  set _isGameMode(bool v) => _gc.isGameMode = v;
  bool get _isHardMode => _gc.isHardMode;
  set _isHardMode(bool v) => _gc.isHardMode = v;
  bool get _isMediumMode => _gc.isMediumMode;
  set _isMediumMode(bool v) => _gc.isMediumMode = v;
  bool get _isGameOver => _gc.isGameOver;
  set _isGameOver(bool v) => _gc.isGameOver = v;
  bool get _showConnections => _gc.showConnections;
  set _showConnections(bool v) => _gc.showConnections = v;
  bool get _showHint => _gc.showHint;
  set _showHint(bool v) => _gc.showHint = v;
  int get _lives => _gc.lives;
  set _lives(int v) => _gc.lives = v;
  static const int _maxLives = GameController.maxLives;
  int get _nextTargetIndex => _gc.nextTargetIndex;
  set _nextTargetIndex(int v) => _gc.nextTargetIndex = v;
  List<Offset> get _userPath => _gc.userPath;
  set _userPath(List<Offset> v) => _gc.userPath = v;
  Set<int> get _wrongDotIndices => _gc.wrongDotIndices;

  // â”€â”€ EditorController delegates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<Dot> get _dots => _ec.dots;
  set _dots(List<Dot> v) => _ec.dots = v;
  List<Offset> get _erasedPoints => _ec.erasedPoints;
  set _erasedPoints(List<Offset> v) => _ec.erasedPoints = v;
  Uint8List? get _selectedImageBytes => _ec.selectedImageBytes;
  set _selectedImageBytes(Uint8List? v) => _ec.selectedImageBytes = v;
  double? get _imageWidth => _ec.imageWidth;
  set _imageWidth(double? v) => _ec.imageWidth = v;
  double? get _imageHeight => _ec.imageHeight;
  set _imageHeight(double? v) => _ec.imageHeight = v;
  String? get _currentImageUrl => _ec.currentImageUrl;
  set _currentImageUrl(String? v) => _ec.currentImageUrl = v;
  bool get _isEraserMode => _ec.isEraserMode;
  set _isEraserMode(bool v) => _ec.isEraserMode = v;
  bool get _isRevealMode => _ec.isRevealMode;
  set _isRevealMode(bool v) => _ec.isRevealMode = v;
  bool get _isPanMode => _ec.isPanMode;
  set _isPanMode(bool v) => _ec.isPanMode = v;
  bool get _isInsertMode => _ec.isInsertMode;
  set _isInsertMode(bool v) => _ec.isInsertMode = v;
  int? get _insertAnchorIndex => _ec.insertAnchorIndex;
  set _insertAnchorIndex(int? v) => _ec.insertAnchorIndex = v;
  bool get _startNewPath => _ec.startNewPath;
  set _startNewPath(bool v) => _ec.startNewPath = v;
  bool get _hasUnsavedChanges => _ec.hasUnsavedChanges;
  set _hasUnsavedChanges(bool v) => _ec.hasUnsavedChanges = v;
  bool get _removeBg => _ec.removeBg;
  set _removeBg(bool v) => _ec.removeBg = v;
  bool get _showOriginal => _ec.showOriginal;
  set _showOriginal(bool v) => _ec.showOriginal = v;
  double get _bgOpacity => _ec.bgOpacity;
  set _bgOpacity(double v) => _ec.bgOpacity = v;
  double get _sparsity => _ec.sparsity;
  set _sparsity(double v) => _ec.sparsity = v;
  int get _currentSparsity => _ec.currentSparsity;
  set _currentSparsity(int v) => _ec.currentSparsity = v;
  List<ProjectState> get _undoStack => _ec.undoStack;
  set _undoStack(List<ProjectState> v) => _ec.undoStack = v;
  List<ProjectState> get _redoStack => _ec.redoStack;

  // â”€â”€ ProjectController delegates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String? get _currentProjectId => _pc.currentProjectId;
  set _currentProjectId(String? v) => _pc.currentProjectId = v;
  Project? get _currentProject => _pc.currentProject;
  set _currentProject(Project? v) => _pc.currentProject = v;
  List<Project> get _savedProjects => _pc.savedProjects;
  set _savedProjects(List<Project> v) => _pc.savedProjects = v;
  String? get _currentFileName => _pc.currentFileName;
  set _currentFileName(String? v) => _pc.currentFileName = v;
  bool get _isSyncing => _pc.isSyncing;
  set _isSyncing(bool v) => _pc.isSyncing = v;
  bool get _isLoading => _pc.isLoading;
  set _isLoading(bool v) => _pc.isLoading = v;
  bool get _isPremium => _pc.isPremium;
  set _isPremium(bool v) => _pc.isPremium = v;
  Future<List<Map<String, dynamic>>>? get _galleryFuture => _pc.galleryFuture;

  @override
  void initState() {
    super.initState();

    // 1. Animation controllers
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _heartShakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // 3. UI controllers
    _transformationController = TransformationController();
    _nameController = TextEditingController();
    _ec.showOriginal = false;

    // 4. Listeners
    _transformationController.addListener(() {
      if (mounted) {
        setState(() {
          _currentScale = _transformationController.value.getMaxScaleOnAxis();
        });
      }
    });

    // 5. Load data
    _pc.refreshProjects();
    _pc.refreshGallery();
    _loadEntitlement();
    _loadDailyState();
  }

  @override
  void dispose() {
    _heartShakeController.dispose();
    _rippleController.dispose();
    _transformationController.dispose();
    _nameController.dispose();
    _mainFocusNode.dispose();
    _mousePosNotifier.dispose();
    _autoSaveTimer?.cancel();
    _debounce?.cancel();
    _saveTimer?.cancel();
    _hintTimer?.cancel();
    _loadingTimer?.cancel();
    _wrongDotTimer?.cancel();
    _processingChannel?.unsubscribe();
    _confettiController.dispose();
    super.dispose();
  }

  void _showAccountDialog() {
    final email = _service.currentUserEmail ?? '';
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Account header
            Text('Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(email, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.55))),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // Theme picker
            Text('App Theme', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 12),
            Consumer(
              builder: (_, ref, _) {
                final currentId = ref.watch(themeProvider);
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: AppTheme.themes.map((theme) {
                    final bool selected = theme.id == currentId;
                    return GestureDetector(
                      onTap: () => ref.read(themeProvider.notifier).setTheme(theme.id),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.background,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? theme.primary : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: selected
                                  ? [BoxShadow(color: theme.primary.withValues(alpha: 0.5), blurRadius: 8)]
                                  : null,
                            ),
                            child: Center(
                              child: Container(
                                width: 20, height: 20,
                                decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            theme.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: selected ? theme.primary : cs.onSurface.withValues(alpha: 0.6),
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 20),
            const Divider(),

            // Privacy preferences
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_outline_rounded, color: cs.onSurface.withValues(alpha: 0.6)),
              title: const Text('Privacy preferences'),
              subtitle: Text('Manage analytics & crash reporting',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.45))),
              onTap: () {
                Navigator.of(ctx).pop();
                _showPrivacyPrefsDialog(context);
              },
            ),

            // Sign out
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout_rounded, color: cs.onSurface.withValues(alpha: 0.6)),
              title: const Text('Sign out'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _service.signOut();
                if (mounted) setState(() {});
              },
            ),

            // Delete account
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              title: const Text('Delete account and all data', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeleteAccount();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, all puzzles, and all uploaded images. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _service.deleteAccount();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Delete account error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadEntitlement() async {
    final premium = await PurchaseService.isPremium();
    if (mounted) setState(() => _isPremium = premium);
  }

  Future<void> _loadDailyState() async {
    final completed = await DailyChallengeService.isCompletedToday();
    final streak = await DailyChallengeService.getStreak();
    if (mounted) setState(() { _isDailyCompleted = completed; _dailyStreak = streak; });
  }

  // 2. THE BUILD METHOD
  @override
  Widget build(BuildContext context) {
    // Subscribe to all controllers so any notifyListeners() triggers a rebuild.
    ref.watch(gameControllerProvider);
    ref.watch(editorControllerProvider);
    ref.watch(projectControllerProvider);
    ref.watch(authControllerProvider);

    if (!_isInPuzzle) return _buildProjectPicker();

    final double boxSize = MediaQuery.of(context).size.height * 0.8;

    return KeyboardListener(
      focusNode: _mainFocusNode,
      autofocus: true,
      onKeyEvent: (event) {
        final isControlDown =
            HardwareKeyboard.instance.isLogicalKeyPressed(
              LogicalKeyboardKey.controlLeft,
            ) ||
            HardwareKeyboard.instance.isLogicalKeyPressed(
              LogicalKeyboardKey.controlRight,
            );

        if (event is KeyDownEvent) {
          if (isControlDown && event.logicalKey == LogicalKeyboardKey.keyZ) {
            _undo(); // â†©ï¸ Ctrl + Z
          }
          if (isControlDown && event.logicalKey == LogicalKeyboardKey.keyY) {
            _redo(); // â†ªï¸ Ctrl + Y
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.space) {
          final bool isSpaceDown = HardwareKeyboard.instance
              .isLogicalKeyPressed(LogicalKeyboardKey.space);
          if (isSpaceDown) {
            if (!_isPanMode) setState(() => _isPanMode = true);
          } else {
            // You can add logic here to revert _isPanMode if not locked
          }
        }
      },
      child: GestureDetector(
        onTap: () => _mainFocusNode.requestFocus(),
        child: Scaffold(
          body: Stack(
            children: [
              // 1. MAIN CONTENT LAYER
              Column(
                children: [
                  // Switch Top Bar based on Mode
                  _isGameMode ? _buildArcadeTopBar() : _buildStudioTopBar(),

                  Expanded(
                    child: Center(
                      // Logic Gate: If Game Mode, wrap in Game View logic
                      child: _buildCanvas(boxSize),
                    ),
                  ),
                ],
              ),

              // 2. STUDIO-ONLY OVERLAYS
              if (!_isGameMode) ...[
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildFloatingToolbar()),
                ),
              ],

              // OFFLINE BANNER
              if (_pc.isOffline)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: Colors.amber.shade700,
                    child: const SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_off, size: 14, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Offline — showing cached puzzles',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // 3. GLOBAL LOADING OVERLAY
              if (_isLoading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.75),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                            strokeWidth: 6,
                          ),
                          const SizedBox(height: 30),
                          Text(
                            _mainStatus,
                            style: const TextStyle(
                              // Warm Ivory White for crisp readability
                              color: Color(0xFFF1F7F4),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _subStatus,
                            style: TextStyle(
                              // ðŸ‘ˆ Removed 'const' from here!
                              color: const Color(0xFFF1F7F4).withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: const [
                    Color(0xFF4EFE98), // Neon Tyranno Green
                    Color(0xFF253B30), // Deep Forest Moss
                    Color(0xFFFA5A33), // Volcanic Magma Orange
                    Color(0xFFF7D060), // Amber Gold / Star Yellow
                    Color(0xFFD63447), // Prehistoric Lava Red
                  ],
                  //createParticlePath: drawStar, // Optional: custom star shape
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDailyChallengeCard() {
    final project = DailyChallengeService.getDailyProject(_savedProjects);
    if (project == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _isDailyCompleted
          ? null
          : () {
              _isDailyChallenge = true;
              _showGameSelectionSheet(project);
            },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isDailyCompleted
                ? [const Color(0xFF2E3B2E), const Color(0xFF1A2A1A)]
                : [const Color(0xFFB8860B), const Color(0xFF8B6914)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: _isDailyCompleted
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFFF7D060).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Left: icon + streak
            Column(
              children: [
                Icon(
                  _isDailyCompleted
                      ? Icons.check_circle_rounded
                      : Icons.local_fire_department_rounded,
                  color: _isDailyCompleted
                      ? Colors.greenAccent
                      : Colors.orange,
                  size: 36,
                ),
                const SizedBox(height: 4),
                if (_dailyStreak > 0)
                  Text(
                    '$_dailyStreak day${_dailyStreak == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFF7D060),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // Centre: text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DAILY CHALLENGE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF7D060),
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isDailyCompleted
                        ? 'Completed today — come back tomorrow!'
                        : '${project.dotCount} dots · tap to play',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            // Right: chevron or check
            if (!_isDailyCompleted)
              const Icon(Icons.chevron_right, color: Color(0xFFF7D060), size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryHeader() {
    // 1. Calculate how many total stars have been earned across all saved projects
    int earnedStars = _savedProjects.fold(0, (sum, p) {
      int count = 0;
      if (p.easyCleared) count++;
      if (p.mediumCleared) count++;
      if (p.hardCleared) count++;
      return sum + count;
    });

    int totalPossible = _savedProjects.length * 3;
    double progress = totalPossible > 0 ? earnedStars / totalPossible : 0;
    int percentage = (progress * 100).toInt();

    String curatorRank = "DOT NOVICE";
    Color rankColor = const Color(0xFFF1F7F4);

    if (percentage >= 90) {
      curatorRank = "LEGENDARY ARTIST";
      rankColor = const Color(0xFF4EFE98);
    } else if (percentage >= 70) {
      curatorRank = "GRAND CURATOR";
      rankColor = const Color(0xFFF7D060);
    } else if (percentage >= 45) {
      curatorRank = "MASTER CONNECTOR";
      rankColor = const Color(0xFFF7D060);
    } else if (percentage >= 25) {
      curatorRank = "DOT HUNTER";
      rankColor = const Color(0xFF253B30);
    } else if (percentage >= 10) {
      curatorRank = "PUZZLE APPRENTICE";
      rankColor = const Color(0xFF253B30);
    } else {
      curatorRank = "PUZZLE BEGINNER";
      rankColor = const Color(0xFFFA5A33);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            // ðŸ¦• Top Left: Subtle translucent Moss Green
            const Color(0xFF253B30).withOpacity(0.40),

            // ðŸŒ´ Bottom Right: Very soft, deeper dark jungle tint
            const Color(0xFF111E18).withOpacity(0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: rankColor.withOpacity(0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    curatorRank,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          rankColor, // âš¡ Automatically morphs colors based on the tier achieved!
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5, // Crisp museum placard spacing
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.5),
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "WONDERDOT ARCHIVE & MUSEUM",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              // The Star Counter Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "$earnedStars / $totalPossible",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ðŸŒŠ PROGRESS BAR
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 12,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "$percentage% DISCOVERED",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildGameView(double boxSize) {
    final bool hasLiftPoints = _dots.any((d) => d.isNewPath);
    return GestureDetector(
      onTapDown: (details) => _processGameTap(details.localPosition, boxSize),
      child: Stack(
        children: [
          _buildImageStack(boxSize),
          if (hasLiftPoints)
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.amber, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Lift pen',
                      style: TextStyle(color: Colors.amber, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ðŸŽ¨ Tool Icon for the Floating Pill
  Widget _buildToolIcon(
    IconData icon,
    bool isActive,
    VoidCallback onTap, {
    String tooltip = '',
  }) {
    final inner = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blueAccent.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: isActive ? Colors.blueAccent : Colors.grey),
      ),
    );
    return tooltip.isEmpty ? inner : Tooltip(message: tooltip, child: inner);
  }

  // ðŸŽ® Mode Selection Button (Studio vs Arcade)
  Widget _modeButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ðŸ–¼ï¸ Project Card for the Lobby
  Widget _buildProjectCard(Project project, {bool isGame = false}) {
    final String baseUrl = '${AppConfig.storageBaseUrl}/';

    // 2. Build the full path
    // If the DB already has 'https', use it. Otherwise, add the baseUrl.
    final String fullImagePath = project.imagePath!.startsWith('http')
        ? project.imagePath!
        : "$baseUrl${project.imagePath!}";
    // Use Uri.encodeFull to turn spaces into '%20' automatically
    final String safeUrl = Uri.encodeFull(fullImagePath);

    // ðŸ•µï¸â€â™‚ï¸ CHECK FOR COMPLETION: Has he cleared it on any difficulty yet?
    final bool isCleared =
        project.easyCleared || project.mediumCleared || project.hardCleared;

    return InkWell(
      onTap: () {
        // 1. CLEAR OLD DATA FIRST ðŸ§¹
        setState(() {
          _nextTargetIndex = 0;
          _userPath = [];
          _wrongDotIndices.clear();
          _isGameOver = false;
          // We force showConnections to false so the "preview" is clean
          _showConnections = false;
        });

        // 2. Load the new data
        _loadProject(project.toMap());

        // 3. Handle navigation
        if (isGame) {
          _showGameSelectionSheet(project);
        } else {
          setState(() {
            _isGameMode = false;
            _isInPuzzle = true;
          });
        }
      },
      child: Card(
        elevation: 2,
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.transparent,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (project.imagePath != null &&
                        project.imagePath!.isNotEmpty)
                      Positioned.fill(
                        child: (isCleared || !isGame)
                            // Editor mode always shows full image.
                            // Game mode shows full image only after clearing.
                            ? Image.network(
                                safeUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.white,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.sync,
                                          color: Colors.blue.shade700,
                                          size: 24,
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          "Syncing...",
                                          style: TextStyle(
                                            fontSize: 8,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            // ðŸ•µï¸â€â™‚ï¸ MYSTERY SILHOUETTE: Not beaten yet. Darken it out completely!
                            : ColorFiltered(
                                colorFilter: const ColorFilter.mode(
                                  Color(
                                    0xFF14221B,
                                  ), // ðŸ¦• Solid obsidian/dark jungle green matching your lobby background
                                  BlendMode
                                      .srcOver, // ðŸŽ¯ FIXED: srcOver completely covers everything (even white backgrounds)
                                ),
                                child: Image.network(
                                  safeUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.white,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.sync,
                                            color: Colors.blue.shade700,
                                            size: 24,
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            "Syncing...",
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                      )
                    else
                      Icon(Icons.image_outlined, color: Colors.grey.shade300),

                    // Dot preview overlay â€” editor mode only
                    if (!isGame && project.dots.isNotEmpty)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: ThumbnailDotPainter(
                            project.dots.map((d) {
                              try {
                                if (d is Map) {
                                  return Dot.fromJson(
                                    Map<String, dynamic>.from(d),
                                  );
                                }
                                if (d is List && d.length >= 2) {
                                  return Dot.fromIndexedList(0, d);
                                }
                              } catch (_) {}
                              return null;
                            }).whereType<Dot>().toList(),
                          ),
                        ),
                      ),

                    // ðŸŒŸ THE STAR BADGE (Top Left)
                    // Only show stars in the Gallery, not the Studio/Editor
                    if (_currentMenuPath == 'game' && !_isInPuzzle)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(
                              0.4,
                            ), // Dark pill for contrast
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1. Easy Star
                              _buildStar(
                                project.easyCleared,
                                Colors.orange,
                                ValueKey(
                                  "${project.id}_e_${project.easyCleared}",
                                ),
                                const Duration(
                                  milliseconds: 1200,
                                ), // Star 1 waits 1.2s
                              ),
                              const SizedBox(width: 2),
                              // 2. Medium Star
                              _buildStar(
                                project.mediumCleared,
                                Colors.purple,
                                ValueKey(
                                  "${project.id}_m_${project.mediumCleared}",
                                ),
                                const Duration(
                                  milliseconds: 1400,
                                ), // Star 2 waits 1.4s
                              ),
                              const SizedBox(width: 2),
                              // 3. Hard Star
                              _buildStar(
                                project.hardCleared,
                                Colors.red,
                                ValueKey(
                                  "${project.id}_h_${project.hardCleared}",
                                ),
                                const Duration(
                                  milliseconds: 1600,
                                ), // Star 3 waits 1.6s
                              ),
                            ],
                          ),
                        ),
                      ),

                    // â–¶ï¸ Play Overlay (Hides standard play arrow behind a mystery question mark if uncompleted)
                    if (isGame)
                      Positioned.fill(
                        child: Container(
                          color:
                              Colors.transparent, // Transparent to click past
                          child: Icon(
                            isCleared
                                ? Icons.play_circle_fill
                                : Icons.help_outline_rounded,
                            color: isCleared ? Colors.white : Colors.white70,
                            size: 40,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ðŸ·ï¸ PROJECT TITLE
                  Text(
                    project.name ?? "Untitled Wonder",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ðŸ”¢ Dot Count
                      Text(
                        "${project.dotCount} Dots",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),

                      // ðŸ—‘ï¸ Delete Icon
                      if (!isGame)
                        GestureDetector(
                          onTap: () => _confirmDelete(
                            context,
                            project.id,
                            project.imagePath ?? "",
                            project.name ?? "Untitled",
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                        ),

                      // ðŸ§© Difficulty Badge
                      _buildDifficultyBadge(project.dotCount),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper extractor to avoid messy double-nesting inside the main layout trees

  Widget _buildStar(bool isCleared, Color color, Key key, Duration delay) {
    return FutureBuilder(
      future: Future.delayed(delay),
      builder: (context, snapshot) {
        // While we are waiting, show the faint "Empty" star socket
        if (snapshot.connectionState != ConnectionState.done) {
          return Icon(
            Icons.star,
            color: Colors.white.withOpacity(0.1),
            size: 14,
          );
        }

        // Once the delay is over, run the "Boing" animation
        return TweenAnimationBuilder<double>(
          key: key,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.elasticOut,
          tween: Tween<double>(begin: 0.0, end: isCleared ? 1.0 : 0.0),
          builder: (context, value, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.star,
                  color: Colors.white.withOpacity(0.1),
                  size: 14,
                ),
                if (isCleared)
                  Transform.scale(
                    scale: value,
                    child: Icon(Icons.star, color: color, size: 14),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDifficultyBadge(int dotCount) {
    String label;
    Color color;

    if (dotCount > 250) {
      label = "HARD";
      color = Colors.red.shade700;
    } else if (dotCount > 100) {
      label = "MEDIUM";
      color = Colors.orange.shade700;
    } else {
      label = "EASY";
      color = Colors.green.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCreateNewCard() {
    return InkWell(
      onTap: _createNew,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: Colors.blueAccent.withOpacity(0.5),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_a_photo_outlined,
                color: Colors.blueAccent,
                size: 40,
              ),
              SizedBox(height: 8),
              Text(
                "New Puzzle",
                style: TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudioTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // 1. EXIT/HOME BUTTON
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Colors.blueGrey),
            onPressed: _handleExit, // Saves automatically and returns to Lobby
            tooltip: "Save and Exit",
          ),

          const VerticalDivider(width: 24, indent: 20, endIndent: 20),

          // 2. PROJECT TITLE & SYNC STATUS
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_isEditingName)
                      SizedBox(
                        width:
                            200, // Constrain width so it doesn't push buttons off screen
                        child: TextField(
                          controller: _nameController,
                          autofocus: true,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => setState(() {
                            _isEditingName = false;
                            _hasUnsavedChanges = true;
                          }),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () => setState(() => _isEditingName = true),
                        child: Text(
                          _nameController.text.isEmpty
                              ? "Untitled Wonder"
                              : _nameController.text,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        _isEditingName ? Icons.check_circle : Icons.edit,
                        size: 16,
                      ),
                      onPressed: () => setState(() {
                        if (_isEditingName) _hasUnsavedChanges = true;
                        _isEditingName = !_isEditingName;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. STUDIO ACTIONS (Export & View Controls)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Export Button
              TextButton.icon(
                onPressed: _dots.isEmpty
                    ? null
                    : () => _showExportMenu(context),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text("EXPORT"),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),

              const SizedBox(width: 8),

              // Zoom Reset (Crucial for Studio focus)
              IconButton(
                icon: const Icon(Icons.center_focus_strong_outlined, size: 20),
                onPressed: () =>
                    _transformationController.value = Matrix4.identity(),
                tooltip: "Reset View",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArcadeTopBar() {
    // Calculate progress percentage
    double progress = _dots.isEmpty ? 0 : (_nextTargetIndex / _dots.length);
    final bool canAffordHint = _lives > 1;

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. EXIT BUTTON
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.blueGrey,
            ),
            onPressed: _handleExit, // Our auto-save + exit function
            tooltip: "Exit to Lobby",
          ),

          const SizedBox(width: 8),

          // 2. PROGRESS SECTION (The "Centerpiece")
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Heart Display (The Dashboard)
                _buildShakingHearts(),
                const SizedBox(height: 4),
                // Tiny Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 120,
                    height: 4,
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.greenAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. GAME TOOLS (Difficulty & Hint)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isHardMode)
                const Tooltip(
                  message: "Hard Mode",
                  child: Icon(
                    Icons.psychology,
                    color: Colors.purpleAccent,
                    size: 22,
                  ),
                ),
              const SizedBox(width: 12),

              // THE HINT BUTTON
              ElevatedButton.icon(
                // Disable if hint is active OR they can't afford it
                onPressed: (_showHint || !canAffordHint)
                    ? null
                    : _handleHintLogic,
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: const Text("HINT"),
                style: ElevatedButton.styleFrom(
                  // Turn grey if they can't afford it
                  backgroundColor: canAffordHint
                      ? Colors.orangeAccent
                      : Colors.grey,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProjectPicker() {
    // ðŸ  STEP 1: THE MAIN MENU (Two big cards)
    if (_currentMenuPath == null) {
      final user = Supabase.instance.client.auth.currentUser;
      return Scaffold(
        backgroundColor: const Color(0xFF060A20),
        body: Stack(
          children: [
            // Cosmic gradient background
            Positioned.fill(
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.3),
                    radius: 1.2,
                    colors: [Color(0xFF111B56), Color(0xFF060A20)],
                  ),
                ),
              ),
            ),
            // Constellation / glow dots
            Positioned.fill(child: CustomPaint(painter: _HomeBackgroundPainter())),

            // Content
            SafeArea(
              child: Column(
                children: [
                  // Top bar — email + account/logout icons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        if (user?.email != null)
                          Expanded(
                            child: Text(
                              user!.email!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          const Spacer(),
                        Tooltip(
                          message: 'Account',
                          child: IconButton(
                            icon: const Icon(Icons.manage_accounts_outlined),
                            color: Colors.white.withValues(alpha: 0.65),
                            onPressed: () => _showAccountDialog(),
                          ),
                        ),
                        Tooltip(
                          message: 'Sign out',
                          child: IconButton(
                            icon: const Icon(Icons.logout_rounded),
                            color: Colors.white.withValues(alpha: 0.65),
                            onPressed: () async {
                              await _service.signOut();
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable body
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo + wordmark
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/icon/icon.png',
                                width: 72,
                                height: 72,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'WonderDot',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Connect the dots. Reveal the picture.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4),
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 36),

                            if (_savedProjects.isNotEmpty) ...[
                              _buildDailyChallengeCard(),
                              const SizedBox(height: 28),
                            ],

                            // Mode picker cards
                            Wrap(
                              spacing: 20,
                              runSpacing: 20,
                              alignment: WrapAlignment.center,
                              children: [
                                _buildCosmicModeCard(
                                  title: 'Editor Mode',
                                  icon: Icons.edit_note_rounded,
                                  color: const Color(0xFF4EFE98),
                                  description: 'Create & edit puzzles',
                                  onTap: () {
                                    setState(() => _currentMenuPath = 'editor');
                                    _refreshProjects();
                                  },
                                ),
                                _buildCosmicModeCard(
                                  title: 'Game Mode',
                                  icon: Icons.videogame_asset_rounded,
                                  color: const Color(0xFFF7D060),
                                  description: 'Play dot-to-dot puzzles',
                                  onTap: () {
                                    setState(() => _currentMenuPath = 'game');
                                    _refreshProjects();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ðŸ“‚ STEP 2: THE SUB-MENUS (Grid of Puzzles)
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentMenuPath == 'editor'
              ? "Select Puzzle to Edit"
              : "Choose a Challenge",
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _currentMenuPath = null),
        ),
      ),
      // ðŸŽ¯ THE CONTROLLER: Use a Column to stack the Header above the Grid/Empty State
      body: Column(
        children: [
          // ðŸ›ï¸ Header injects ONLY in Game Mode
          if (_currentMenuPath == 'game') _buildGalleryHeader(),

          // The rest of your view occupies the remaining space
          Expanded(
            child: _savedProjects.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "No puzzles found yet!",
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        if (_currentMenuPath == 'editor')
                          ElevatedButton(
                            onPressed: () => _createNew(),
                            child: const Text("Create First Puzzle"),
                          ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                    itemCount: _currentMenuPath == 'editor'
                        ? _savedProjects.length + 1
                        : _savedProjects.length,
                    itemBuilder: (context, index) {
                      if (_currentMenuPath == 'editor') {
                        if (index == 0) return _buildCreateNewCard();
                        return _buildProjectCard(
                          _savedProjects[index - 1],
                          isGame: false,
                        );
                      } else {
                        return _buildProjectCard(
                          _savedProjects[index],
                          isGame: true,
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final double screenWidth = MediaQuery.of(context).size.width;

    final double dynamicWidth = screenWidth < 450
        ? (screenWidth - 64) / 2
        : 200;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: dynamicWidth,
        height: screenWidth < 450 ? 180 : 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            const BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: screenWidth < 450 ? 44 : 64, color: color),
            SizedBox(height: screenWidth < 450 ? 10 : 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                // ðŸ¦– DINO UPGRADE: High contrast dark text on the white card
                color: const Color(0xFF111E18),
                fontSize: screenWidth < 450 ? 16 : 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCosmicModeCard({
    required String title,
    required IconData icon,
    required Color color,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1544).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameStartCard(Project project) {
    // ðŸŽ¯ Add this wrapper!
    return StatefulBuilder(
      builder: (context, setCardState) {
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                const Icon(
                  Icons.videogame_asset,
                  size: 48,
                  color: Color(0xFFF7D060),
                ),
                const SizedBox(height: 16),
                const Text(
                  "WonderDot",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Connect ${(_isHardMode ? project.dotsForLevel('hard') : _isMediumMode ? project.dotsForLevel('medium') : project.dotsForLevel('easy')).length} dots to reveal the picture!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),

                // ðŸ”´ LIVES PREVIEW
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (i) => const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        Icons.favorite,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // âš¡ DIFFICULTY SELECTOR
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      // ðŸŽ¯ EASY TAB
                      _buildDifficultyTab(
                        "Easy",
                        (!_isHardMode && !_isMediumMode),
                        true,
                        () {
                          setState(() {
                            _isHardMode = false;
                            _isMediumMode = false;
                          });
                          setCardState(() {});
                        },
                        subtitle: '${project.dotsForLevel('easy').length} dots',
                      ),

                      // ðŸŽ¯ MEDIUM TAB
                      _buildDifficultyTab(
                        "Medium",
                        _isMediumMode,
                        project.easyCleared,
                        () {
                          setState(() {
                            _isHardMode = false;
                            _isMediumMode = true;
                          });
                          setCardState(() {});
                        },
                        subtitle: '${project.dotsForLevel('medium').length} dots',
                        onLockedTap: () => _showDifficultyLockedPrompt(
                          context, 'Medium', 'Easy',
                        ),
                      ),

                      // ðŸŽ¯ HARD TAB
                      _buildDifficultyTab(
                        "Hard",
                        _isHardMode,
                        project.mediumCleared,
                        () {
                          setState(() {
                            _isHardMode = true;
                            _isMediumMode = false;
                          });
                          setCardState(() {});
                        },
                        subtitle: '${project.dotsForLevel('hard').length} dots',
                        onLockedTap: () => _showDifficultyLockedPrompt(
                          context, 'Hard', 'Medium',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context); // ðŸŽ¯ Close the sheet FIRST
                    _startGame(project); // ðŸš€ Then launch the game
                  },
                  child: const Text(
                    "PLAY GAME",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
                ),      // Column
              ),        // SizedBox
            ),          // SingleChildScrollView
          ),            // ConstrainedBox
        );              // Card
      },
    );
  }

  Widget _buildDifficultyTab(
    String label,
    bool isSelected,
    bool isUnlocked,
    VoidCallback onTap, {
    String? subtitle,
    VoidCallback? onLockedTap,
  }) {
    final Color textColor = isSelected
        ? Colors.white
        : (isUnlocked ? Colors.black54 : Colors.black26);

    return Expanded(
      child: GestureDetector(
        onTap: isUnlocked ? onTap : onLockedTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4EFE98)
                : (isUnlocked
                      ? Colors.transparent
                      : Colors.grey.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!isUnlocked)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.lock, size: 14, color: Colors.black26),
                    ),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: textColor.withValues(alpha: 0.75),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }


  void _redo() {
    if (_redoStack.isEmpty) return;

    setState(() {
      // 1. Push current layout state back onto the undo stack
      _undoStack.add(
        ProjectState(
          dots: List<Dot>.from(_dots),
          erasedPoints: List<Offset>.from(_erasedPoints),
        ),
      );

      // 2. Extrude the forward frame out of the redo stack
      final nextState = _redoStack.removeLast();
      _dots = nextState.dots;
      _erasedPoints = nextState.erasedPoints;
      _hasUnsavedChanges = true;
    });

    // Trigger save to synchronize backend database
    _debouncedSave();
  }





  void _showDifficultyLockedPrompt(BuildContext ctx, String difficulty, String prerequisite) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.lock_rounded, color: Color(0xFFF7D060), size: 36),
        title: Text('$difficulty Locked'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Complete $prerequisite first to unlock $difficulty,\nor go Premium to unlock all difficulties instantly.',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.star_rounded, size: 18),
                label: const Text(
                  'Upgrade to Premium',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF7D060),
                  foregroundColor: Colors.black87,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  // TODO: launch premium purchase flow
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Premium coming soon — stay tuned!')),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(
                  'Not now',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showGameSelectionSheet(Project project) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _buildGameStartCard(project),
    );
  }

  void _resetToHome() {
    // Capture progress before exitGame() resets it.
    final int progressIndex = _gc.nextTargetIndex;
    final String level = _isHardMode ? 'hard' : _isMediumMode ? 'medium' : 'easy';
    final String difficulty = '${level[0].toUpperCase()}${level.substring(1)}';

    _gc.exitGame();
    _ec.showOriginal = true;

    // Persist so the player resumes from this dot next session.
    if (_currentProject != null && progressIndex > 0) {
      _pc.saveProgress(
        _currentProject!.id,
        lastIndex: progressIndex,
        difficulty: difficulty,
      );
    }

    setState(() => _isInPuzzle = false);
  }



  Future<void> _handleSave() async {
    if (_dots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add some dots before saving!")),
      );
      return;
    }

    setState(() => _isLoading = true);

    // 1. Prepare Data
    final user = Supabase.instance.client.auth.currentUser;
    final jsonDots = _dots.map((d) => d.toJson()).toList();
    final jsonErasedPoints = _erasedPoints.map((p) => [p.dx, p.dy]).toList();

    // ðŸŽ¯ IMPORTANT: Use the public URL from the project state,
    // not a local _currentFileName variable which might be null.
    final Map<String, dynamic> projectData = {
      'name': _nameController.text.isEmpty
          ? "New Wonder"
          : _nameController.text,
      'dots': jsonDots,
      'erased_points': jsonErasedPoints,
      'sparsity': _sparsity.toInt(),
      'dot_count': _dots.length,
      // 'image_path': _currentFileName, // ðŸ›‘ REMOVE THIS - it's likely null
      'difficulty': _isHardMode ? 'Hard' : 'Easy',
      'updated_at': DateTime.now().toIso8601String(),
      'user_id': user?.id,
    };

    try {
      if (_currentProjectId != null) {
        await Supabase.instance.client
            .from('projects')
            .update(projectData)
            .eq('id', _currentProjectId!);

        print("âœ… Project updated successfully");
      } else {
        // ðŸ›‘ WE REMOVED THE INSERT LOGIC HERE.
        // Projects are now ONLY created via _pickAndUploadImage.
        print("âš ï¸ Save ignored: No Project ID. Use Upload first.");
        return;
      }

      setState(() {
        _hasUnsavedChanges = false;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Puzzle saved!",
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("âŒ Save Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startGame(Project project) async {
    final String level = _isHardMode ? 'hard' : _isMediumMode ? 'medium' : 'easy';

    // The list query omits dots_easy/medium/hard to keep payload small.
    // Fetch the full row now so dotsForLevel() returns calibrated sets.
    setState(() => _isLoading = true);
    final Project? full = await _pc.loadProjectDetail(project.id);
    setState(() => _isLoading = false);

    if (!mounted) return;
    if (full == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load puzzle data.')),
      );
      return;
    }

    final List<dynamic> rawDots = full.dotsForLevel(level);
    if (rawDots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No dots found for this puzzle.')),
      );
      return;
    }

    // Set editor/project state before enterGame() triggers the Riverpod rebuild.
    _ec.dots = rawDots.map((d) => Dot.fromMap(Map<String, dynamic>.from(d))).toList();
    _ec.showOriginal = false;
    _ec.isPanMode = false;
    _pc.currentProject = full;
    _transformationController.value = Matrix4.identity();

    // Resume from the saved dot index only when replaying the same difficulty.
    // Switching difficulty always starts fresh.
    final bool sameLevel = full.difficulty.toLowerCase() == level;
    final int resumeIndex = (sameLevel && full.lastIndex > 0) ? full.lastIndex : 0;

    _gc.enterGame(isMedium: _isMediumMode, isHard: _isHardMode, resumeIndex: resumeIndex);
    AnalyticsService.puzzlePlayed(full.id);

    setState(() => _isInPuzzle = true);
    _mainFocusNode.requestFocus();
  }

  // Placeholder for settings
  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // ðŸŽ¯ StatefulBuilder allows the sliders to move smoothly inside the popup
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min, // Fits to content
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Editor Settings",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  // â”€â”€ App Theme â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  const Text("App Theme"),
                  const SizedBox(height: 10),
                  Consumer(
                    builder: (ctx, ref, _) {
                      final currentId = ref.watch(themeProvider);
                      return Row(
                        children: AppTheme.themes.map((theme) {
                          final bool selected = theme.id == currentId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: GestureDetector(
                              onTap: () => ref
                                  .read(themeProvider.notifier)
                                  .setTheme(theme.id),
                              child: Column(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: theme.background,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: selected
                                            ? theme.primary
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: theme.primary
                                                    .withValues(alpha: 0.5),
                                                blurRadius: 8,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: theme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    theme.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: selected
                                          ? theme.primary
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),

                  // ðŸ–¼ï¸ BACKGROUND OPACITY
                  Text(
                    "Reference Image Opacity: ${(_bgOpacity * 100).toInt()}%",
                  ),
                  Slider(
                    value: _bgOpacity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) {
                      // Update the main UI
                      setState(() => _bgOpacity = val);
                      // Update the slider handle in the popup
                      setModalState(() => _bgOpacity = val);
                    },
                  ),

                  const SizedBox(height: 16),

                  // ðŸ“ DOT SPARSITY
                  Text("Auto-Trace Sparsity: ${_sparsity.toInt()}"),
                  Slider(
                    value: _sparsity,
                    min: 5,
                    max: 100,
                    onChanged: (val) {
                      setState(() => _sparsity = val);
                      setModalState(() => _sparsity = val);
                    },
                    onChangeEnd: (val) {
                      // ðŸŽ¯ This only triggers when the user lets go of the slider
                      _uploadAndProcess();
                    },
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: const Text('Privacy preferences'),
                    subtitle: const Text('Manage analytics & crash reporting'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _showPrivacyPrefsDialog(context),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPrivacyPrefsDialog(BuildContext sheetCtx) {
    bool analytics = ConsentService.analyticsGranted;
    bool crash = ConsentService.crashGranted;
    showDialog(
      context: sheetCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Privacy preferences'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Analytics'),
                subtitle: const Text('Usage data to improve the app'),
                value: analytics,
                onChanged: (v) => setDialogState(() => analytics = v),
              ),
              SwitchListTile(
                title: const Text('Crash reports'),
                subtitle: const Text('Anonymous crash logs'),
                value: crash,
                onChanged: (v) => setDialogState(() => crash = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await ConsentService.save(analytics: analytics, crash: crash);
                if (analytics && !AnalyticsService.isReady) {
                  try {
                    await AnalyticsService.initialize();
                  } catch (_) {}
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111E18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Export Puzzle',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(
              Icons.picture_as_pdf_outlined,
              color: Color(0xFFF7D060),
            ),
            title: const Text(
              'Print / Save PDF',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Printable puzzle + solution key (A4)',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(ctx);
              PdfService.generateAndPrint(
                _dots,
                _currentFileName ?? 'puzzle',
                imageBytes: _selectedImageBytes,
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.image_outlined,
              color: Color(0xFF4EFE98),
            ),
            title: const Text(
              'Save PNG',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'High-resolution image for sharing',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _saveToGallery();
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _refreshGallery() => _pc.refreshGallery();

  Future<void> _refreshProjects() => _pc.refreshProjects();

  // Map _saveCurrentProject to our existing debounced logic
  Future<void> _saveCurrentProject() async {
    // ðŸ›‘ STRICT GATEKEEPER
    // If _currentProjectId is null OR if we are currently in the middle of an upload,
    // do NOT touch the database.
    if (_currentProjectId == null || _isSyncing) {
      print("â³ Save blocked: Project not initialized or upload in progress.");
      return;
    }

    try {
      await _service.saveDots(_currentProjectId!, _dots);
      print("â˜ï¸ Dots successfully saved for ID: $_currentProjectId");
    } catch (e) {
      print("âŒ Error during save: $e");
    }
  }

  Future<void> _createNew() async {
    if (!_isPremium && _savedProjects.length >= AppConfig.freePuzzleLimit) {
      AnalyticsService.paywallShown('puzzle_limit');
      final subscribed = await showPaywall(context);
      if (subscribed) {
        AnalyticsService.subscriptionStarted();
        await _loadEntitlement();
      }
      return;
    }
    AnalyticsService.puzzleCreated();
    setState(() {
      // 1. Clear ID & Content
      _currentProjectId = null;
      _dots = [];
      _erasedPoints = [];
      _undoStack = [];
      _selectedImageBytes =
          null; // ðŸŽ¯ CRITICAL: Clears the old image from memory

      // 2. Reset UI States
      _isInPuzzle = true;
      _isGameMode = false;
      _showOriginal = true;
      _isEraserMode = false;

      // 3. Reset Names & Controllers
      _nameController.text = "Untitled Wonder";
      _currentFileName = "Untitled Wonder";

      // 4. Reset Status Indicators
      _mainStatus = "";
      _subStatus = "";
      _hasUnsavedChanges = false;
    });

    // Now that the state is clean, open the file picker
    _pickAndUploadImage();
  }

  void _autoSave() async {
    setState(() => _isSyncing = true);
    await _service.saveDots(_currentProject!.id, _dots);
    // Optional delay to make the user feel the "work" being done
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _isSyncing = false);
  }

  void _handleHintLogic() {
    if (_showHint) return;
    if (_lives <= 1) {
      _heartShakeController.forward(from: 0.0);
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Not enough hearts for a hint!"),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() {
      _lives--;
      _showHint = true;
      _heartShakeController.forward(from: 0.0);
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  void _showModeSelection(Project project) {
    // We use a local state variable inside the dialog to track the toggle
    bool tempHardMode = _isHardMode;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        // StatefulBuilder allows the toggle to animate
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          title: Column(
            children: [
              Text(
                project.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                "${project.dotCount} Total Dots",
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. DIFFICULTY TOGGLE
              SwitchListTile(
                title: const Text(
                  "Hard Mode",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text("No numbers, no help."),
                value: tempHardMode,
                activeColor: Colors.purpleAccent,
                onChanged: (val) => setDialogState(() => tempHardMode = val),
              ),
              const Divider(),
              const SizedBox(height: 10),
              // 2. MODE BUTTONS
              Row(
                children: [
                  Expanded(
                    child: _modeButton(
                      icon: Icons.architecture,
                      label: "STUDIO",
                      color: Colors.blueAccent,
                      onTap: () {
                        setState(() {
                          _currentProject = project;
                          _isGameMode = false;
                          _isInPuzzle = true;
                        });
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _modeButton(
                      icon: Icons.play_arrow_rounded,
                      label: "ARCADE",
                      color: Colors.orangeAccent,
                      onTap: () {
                        setState(() {
                          _currentProject = project;
                          _isGameMode = true;
                          _isHardMode =
                              tempHardMode; // Set the chosen difficulty
                          _isInPuzzle = true;
                          _lives = 3;
                        });
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShakingHearts() {
    return AnimatedBuilder(
      animation: _heartShakeController,
      builder: (context, child) {
        // This creates the "left-right" jitter
        final double offset = sin(_heartShakeController.value * pi * 4) * 8;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_maxLives, (index) {
              return Icon(
                index < _lives ? Icons.favorite : Icons.favorite_border,
                color: index < _lives ? Colors.red : Colors.grey,
                size: 30,
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildFloatingToolbar() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // âœï¸ Tool: Draw
          _buildToolIcon(
            Icons.edit,
            !_isEraserMode && !_isPanMode && !_isRevealMode,
            () => setState(() {
              _isEraserMode = false;
              _isPanMode = false;
              _isRevealMode = false;
              _mainFocusNode.requestFocus();
            }),
            tooltip: 'Draw',
          ),
          const SizedBox(width: 8),

          // ðŸ§½ Tool: Eraser
          _buildToolIcon(
            Icons.auto_fix_high,
            _isEraserMode,
            () => setState(() {
              _isEraserMode = true;
              _isPanMode = false;
              _isRevealMode = false;
            }),
            tooltip: 'Eraser',
          ),

          // ðŸ”¢ Delete by number â€” only visible while eraser mode is active
          if (_isEraserMode) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Delete dot by number',
              child: IconButton(
                icon: const Icon(Icons.tag, size: 18),
                color: const Color(0xFFF7D060),
                onPressed: _showDeleteByNumberDialog,
              ),
            ),
          ],

          const SizedBox(width: 8),

          // ðŸ‘ Tool: Reveal Brush â€” paint background reveals without touching dots
          _buildToolIcon(
            Icons.visibility_outlined,
            _isRevealMode,
            () => setState(() {
              _isRevealMode = true;
              _isEraserMode = false;
              _isPanMode = false;
            }),
            tooltip: 'Reveal brush',
          ),
          const SizedBox(width: 8),

          // âœ‹ Tool: Pan Mode
          _buildToolIcon(
            Icons.front_hand,
            _isPanMode,
            () => setState(() {
              _isPanMode = true;
              _isEraserMode = false;
              _isRevealMode = false;
            }),
            tooltip: 'Pan / Scroll',
          ),
          const SizedBox(width: 8),

          // ➕ Tool: Insert After
          _buildToolIcon(
            Icons.add_circle_outline,
            _isInsertMode,
            () => setState(() {
              _isInsertMode = !_isInsertMode;
              _isEraserMode = false;
              _isPanMode = false;
              _isRevealMode = false;
              if (!_isInsertMode) _insertAnchorIndex = null;
            }),
            tooltip: 'Insert dot after…',
          ),

          if (_isInsertMode) ...[
            const SizedBox(width: 4),
            Text(
              _insertAnchorIndex != null
                  ? 'After #${_insertAnchorIndex! + 1}'
                  : 'Tap a dot',
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          VerticalDivider(
            width: 24,
            indent: 8,
            endIndent: 8,
            color: const Color(0xFFF1F7F4).withOpacity(0.2),
          ),

          // â›“ï¸ Tool: Pen Lift (Path Toggle)
          Tooltip(
            message: _startNewPath ? "Pen Lifted" : "Pen Down",
            child: IconButton(
              icon: Icon(_startNewPath ? Icons.link_off : Icons.link),
              // ðŸ¦– DINO UPGRADE: Amber Gold for lifted, Soft Ivory for bound paths
              color: _startNewPath
                  ? const Color(0xFFF7D060)
                  : const Color(0xFFF1F7F4),
              onPressed: () => setState(() => _startNewPath = !_startNewPath),
            ),
          ),

          // â†©ï¸ UNDO BUTTON
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: "Undo (Ctrl+Z)",
            // ðŸŽ¨ Active: Neon Green Accent | Disabled: Faint Moss
            color: _undoStack.isEmpty
                ? const Color(0xFF253B30)
                : const Color(0xFF4EFE98),
            onPressed: _undoStack.isEmpty ? null : _undo,
          ),

          // â†ªï¸ REDO BUTTON
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: "Redo (Ctrl+Y)",
            color: _redoStack.isEmpty
                ? const Color(0xFF253B30)
                : const Color(0xFF4EFE98),
            onPressed: _redoStack.isEmpty ? null : _redo,
          ),

          VerticalDivider(
            color: const Color(0xFFF1F7F4).withOpacity(0.2),
            width: 20,
          ),

          // âš™ï¸ ðŸŽ›ï¸ Action: Studio Parameters (Updated to settings gear icon!)
          IconButton(
            icon: const Icon(Icons.settings),
            color: const Color(0xFFF1F7F4),
            tooltip: "Studio Parameters",
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(
                  0xFF111E18,
                ), // Deep Jungle sheet context
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (context) {
                  return StatefulBuilder(
                    builder: (BuildContext context, StateSetter setModalState) {
                      return _buildConfigurationSection(setModalState);
                    },
                  );
                },
              );
            },
          ),

          VerticalDivider(
            width: 24,
            indent: 8,
            endIndent: 8,
            color: const Color(0xFFF1F7F4).withOpacity(0.2),
          ),

          // â˜ï¸ Action: Save to Supabase
          Tooltip(
            message: "Save to Cloud",
            child: IconButton(
              icon: Icon(
                _hasUnsavedChanges ? Icons.cloud_upload : Icons.cloud_done,
                color: _hasUnsavedChanges
                    ? const Color(0xFFFA5A33)
                    : const Color(0xFF4EFE98),
              ),
              onPressed: _handleSave,
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildHearts() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_maxLives, (index) {
        // Determine if the heart is filled or empty
        bool isFilled = index < _lives;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Icon(
            isFilled ? Icons.favorite : Icons.favorite_border,
            color: isFilled ? Colors.red : Colors.grey.withOpacity(0.5),
            size: 32,
            // ðŸŽ¯ Optional: Add a subtle shadow to make hearts visible on any background
            shadows: const [
              Shadow(
                blurRadius: 4,
                color: Colors.black26,
                offset: Offset(2, 2),
              ),
            ],
          ),
        );
      }),
    );
  }

  // 3. THE UPDATED IMAGE STACK
  Widget _buildImageStack(double boxSize) {
    return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFFBF8FF),
        child: Center(
          child: Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  spreadRadius: 5,
                ), // Added comma
              ],
            ),
            child: ClipRect(
              child: MouseRegion(
                // ðŸŽ¯ FIX: Check BOTH the toggle state AND the hardware spacebar
                cursor:
                    (_isPanMode ||
                        HardwareKeyboard.instance.isLogicalKeyPressed(
                          LogicalKeyboardKey.space,
                        ))
                    ? SystemMouseCursors.grab
                    : MouseCursor.defer,
                onHover: (_) {
                  final bool spaceDown = HardwareKeyboard.instance
                      .isLogicalKeyPressed(LogicalKeyboardKey.space);

                  // ðŸŽ¯ Only auto-reset _isPanMode if the Spacebar was the one that turned it on.
                  // We check if the spacebar is up and we aren't "locked" into pan mode by the button.
                  if (!spaceDown &&
                      _isPanMode &&
                      !HardwareKeyboard.instance.isLogicalKeyPressed(
                        LogicalKeyboardKey.space,
                      )) {
                    // If you want the button to stay active, we only reset if a certain "spaceDown" flag is used.
                    // But for most apps, just checking _isPanMode is enough!
                  }
                },
                child: InteractiveViewer(
                  onInteractionEnd: (_) {
                    // ðŸŽ¯ Safety check: If the spacebar isn't actually down anymore, force pan mode OFF.
                    final isSpaceStillDown = HardwareKeyboard.instance
                        .isLogicalKeyPressed(LogicalKeyboardKey.space);
                    if (!isSpaceStillDown && _isPanMode) {
                      setState(() => _isPanMode = false);
                    }
                  },
                  transformationController: _transformationController,
                  // ðŸ–ï¸ Only allow panning when the mode is active (via Spacebar or Toggle)
                  panEnabled: true,
                  scaleEnabled: true,
                  minScale: 1.0,
                  maxScale: 5.0,
                  onInteractionStart: (_) {
                    _mousePosNotifier.value = null;
                  },
                  child: SizedBox(
                    key: _canvasKey,
                    width: boxSize,
                    height: boxSize,
                    child: Stack(
                      children: [
                        // 1. Layer A: Reference Image
                        // In game mode the image must ALWAYS render so that
                        // MaskPainter's transparent holes actually reveal the
                        // image rather than punching through to white.
                        // In studio mode _showOriginal and _bgOpacity control
                        // visibility as before.
                        if (_selectedImageBytes != null &&
                            (_showOriginal || _isGameMode || _isRevealMode))
                          Positioned.fill(
                            child: Opacity(
                              opacity: (_isGameMode || _isRevealMode) ? 1.0 : _bgOpacity,
                              child: Image.memory(
                                _selectedImageBytes!,
                                // BoxFit.fill matches the server's 1024Ã—1024
                                // square processing space so dots align with
                                // the reference image for any aspect ratio.
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),

                        // 2. Layer B: Masking (Eraser/Game/Reveal Mode)
                        // In editor reveal mode the mask is semi-transparent so
                        // the image remains visible everywhere and brushed holes
                        // reveal it at full brightness (clear visual feedback).
                        if (_isGameMode || _isEraserMode || _isRevealMode)
                          Positioned.fill(
                            child: Opacity(
                              opacity: (_isRevealMode && !_isGameMode) ? 0.6 : 1.0,
                              child: CustomPaint(
                                painter: MaskPainter(
                                  erasedPoints: _erasedPoints,
                                  isGameMode: _isGameMode || _isRevealMode,
                                  currentZoom: _currentScale,
                                ),
                              ),
                            ),
                          ),

                        // 3. Layer C: Logic & Painting
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring:
                                _isPanMode, // ðŸš¦ When true, clicks "fall through" to the InteractiveViewer
                            child: Listener(
                              onPointerDown: (event) {
                                _activePointers++;
                                // Process game taps here, in the Listener, rather
                                // than in GestureDetector.onTapDown.
                                // Listener.onPointerDown fires synchronously and
                                // immediately â€” it never enters the gesture arena,
                                // so InteractiveViewer cannot consume the event
                                // first (a common cause of missed taps on web).
                                if (_activePointers == 1 && _isGameMode) {
                                  _processGameTap(event.localPosition, boxSize);
                                }
                              },
                              onPointerUp: (event) => _activePointers--,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (details) {
                                  // Keep focus request here so Ctrl+Z/Y shortcuts
                                  // work after clicking the canvas in editor mode.
                                  _mainFocusNode.requestFocus();
                                  // Game taps are handled above in onPointerDown.
                                },

                                // ðŸš« REMOVED: onPanStart, onPanUpdate, and onPanCancel!
                                // Removing these lets InteractiveViewer instantly detect pinch-to-zoom and panning
                                // without our logic engine accidentally intercepting the gesture.
                                onTapUp: (details) {
                                  // If more than one finger is present, they are zooming/panning. Abort!
                                  if (_activePointers > 1) return;

                                  // ðŸ“ EDITOR MODE: Handles adding dots safely on mouse-up / single-tap release
                                  _handleCanvasTap(details, boxSize);
                                },

                                child: MouseRegion(
                                  cursor: (_isEraserMode || _isRevealMode)
                                      ? SystemMouseCursors.precise
                                      : (_isGameMode
                                            ? SystemMouseCursors.click
                                            : SystemMouseCursors.basic),
                                  onHover: (event) => _mousePosNotifier.value =
                                      event.localPosition,
                                  onExit: (_) => _mousePosNotifier.value = null,
                                  // ValueListenableBuilder isolates hover repaints to
                                  // just the painter + cursor ring â€” no full-tree rebuild.
                                  child: ValueListenableBuilder<Offset?>(
                                    valueListenable: _mousePosNotifier,
                                    builder: (context, mousePos, _) {
                                      return Stack(
                                        children: [
                                          // Positioned.fill ensures CustomPaint
                                          // inherits the full canvas size from the
                                          // Stack, not loose 0Ã—0 constraints.
                                          Positioned.fill(
                                            child: AnimatedBuilder(
                                              animation: _rippleController,
                                              builder: (context, child) {
                                                return CustomPaint(
                                                painter: DotPainter(
                                                  currentZoom:
                                                      _transformationController
                                                          .value
                                                          .getMaxScaleOnAxis(),
                                                  dots: _dots,
                                                  isPenUp: _startNewPath,
                                                  mousePos: mousePos,
                                                  lastErasedPos: _lastErasedPos,
                                                  rippleValue:
                                                      _rippleController.value,
                                                  showLines:
                                                      (_showConnections ||
                                                          !_isGameMode) &&
                                                      !(_isGameMode &&
                                                          (_isMediumMode ||
                                                              _isHardMode)),
                                                  isEraserMode: _isEraserMode,
                                                  isGameMode: _isGameMode,
                                                  isHardMode: _isHardMode,
                                                  isMediumMode: _isMediumMode,
                                                  nextTargetIndex:
                                                      _nextTargetIndex,
                                                  showHint: _showHint,
                                                  wrongDotIndices:
                                                      _wrongDotIndices,
                                                  displayWidth: boxSize,
                                                  displayHeight: boxSize,
                                                  originalWidth:
                                                      _imageWidth ?? 1024,
                                                  originalHeight:
                                                      _imageHeight ?? 1024,
                                                  isPanMode: _isPanMode,
                                                  insertAnchorIndex: _insertAnchorIndex,
                                                ),
                                              );
                                            },
                                          ),  // closes AnimatedBuilder
                                        ),    // closes Positioned.fill
                                          // Cursor ring â€” only repaints on hover
                                          if (!_isGameMode && mousePos != null)
                                            Positioned(
                                              left: mousePos.dx - 15,
                                              top: mousePos.dy - 15,
                                              child: IgnorePointer(
                                                child: Container(
                                                  width: 30,
                                                  height: 30,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: _isEraserMode
                                                          ? Colors.red
                                                              .withOpacity(0.6)
                                                          : _isRevealMode
                                                          ? Colors.amber
                                                              .withOpacity(0.8)
                                                          : Colors.blue
                                                              .withOpacity(0.5),
                                                      width: 2,
                                                    ),
                                                    color: _isEraserMode
                                                        ? Colors.red
                                                            .withOpacity(0.05)
                                                        : _isRevealMode
                                                        ? Colors.amber
                                                            .withOpacity(0.08)
                                                        : Colors.blue
                                                            .withOpacity(0.05),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ], // End of Stack children
                    ), // End of Stack
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }

  void _checkPanStatus() {
    final bool isSpaceDown = HardwareKeyboard.instance.isLogicalKeyPressed(
      LogicalKeyboardKey.space,
    );
    if (_isPanMode != isSpaceDown) {
      setState(() {
        _isPanMode = isSpaceDown;
      });
    }
  }

  void _resetView() {
    setState(() {
      _transformationController.value = Matrix4.identity();
    });
  }

  void _reset() {
    // ðŸ›‘ Stop any pending auto-saves before they fire
    _autoSaveTimer?.cancel();

    setState(() {
      _dots = []; // Clear current edited dots
      _undoStack = []; // Clear undo history
      _erasedPoints = []; // ðŸ§¹ Forget everything we erased!
      _isEraserMode = false;
      _sparsity = 20.0; // Reset to default sparsity
      _currentSparsity = 20;
      _hasUnsavedChanges = true;
    });

    // ðŸ›¡ï¸ DINO SAFETY GUARD: Only re-request AI dots if we actually have an active image
    // on screen to process! If it's null, stop right here!
    if (_selectedImageBytes == null) {
      print("ðŸ¦• Clear Canvas Reset complete (No image to process).");
      return;
    }

    // Automatically trigger a fresh "Generate Dots" ONLY if an image exists
    _uploadAndProcess();
    print("ðŸ”„ Full Reset: Canvas and Eraser memory cleared.");
  }

  void _zoom(double scaleFactor) {
    setState(() {
      _currentScale = (_currentScale * scaleFactor).clamp(1.0, 5.0);
      // Create a matrix that scales the view
      _transformationController.value = Matrix4.identity()
        ..scale(_currentScale);
    });
  }

  void _resetZoom() {
    setState(() {
      _currentScale = 1.0;
      _transformationController.value = Matrix4.identity();
    });
  }

  Future<void> _pickAndUploadImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result != null && result.files.first.bytes != null) {
      Uint8List fileBytes = result.files.first.bytes!;
      String fileName = result.files.first.name;
      final decodedImage = await decodeImageFromList(fileBytes);

      setState(() {
        _isSyncing = true;
        _currentProjectId = null;

        // ðŸ§¹ NEW: Reset the canvas and data immediately
        _dots = [];
        _erasedPoints = [];
        _currentProject = null;
        _userPath = []; // Reset game path if any
        _nextTargetIndex = 1; // Reset game progress
      });

      try {
        // STEP 1: Upload Storage First
        print("ðŸ›°ï¸ UPLOADING IMAGE...");
        String cleanName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '_');
        final String cloudName =
            '${DateTime.now().millisecondsSinceEpoch}_$cleanName';

        await Supabase.instance.client.storage
            .from('images')
            .uploadBinary(
              cloudName,
              fileBytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );

        final String publicUrl = Supabase.instance.client.storage
            .from('images')
            .getPublicUrl(cloudName);
        print("ðŸ”— URL GENERATED: $publicUrl");

        // STEP 2: Create the Database Row with the URL
        print("ðŸ“ CREATING DB ROW...");
        final response = await Supabase.instance.client
            .from('projects')
            .insert({
              'name': fileName.split('.').first,
              'image_path': publicUrl, // ðŸŽ¯ Included from the start!
              'user_id': Supabase.instance.client.auth.currentUser?.id,
              'status': 'ready',
              'dots': [],
              'erased_points': [],
            })
            .select()
            .single();

        print("âœ… DB ROW CREATED: ${response['id']}");

        // STEP 3: Switch UI
        setState(() {
          _currentProjectId = response['id'];
          _dots = [];
          _currentProject = Project.fromMap(response);
          _imageWidth = decodedImage.width.toDouble();
          _imageHeight = decodedImage.height.toDouble();
          _selectedImageBytes = fileBytes;
          _showOriginal = true;
          _isSyncing = false;
          _isInPuzzle = true; // ðŸ Go to editor
        });
      } catch (e) {
        print("â€¼ï¸ UPLOAD FAIL: $e");
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<List<Project>> getAllProjects() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final response = await Supabase.instance.client
        .from('projects')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    // Convert the list of Maps into a list of Project objects
    return (response as List).map((map) => Project.fromMap(map)).toList();
  }

  Future<void> _handleExit() async {
    await _saveCurrentProject();

    // ðŸŽ¯ FIX: Fetch the latest projects so the new one shows up in the gallery!
    await _loadUserProjects();

    setState(() {
      _isInPuzzle = false;
    });
  }

  Future<void> _loadUserProjects() async {
    try {
      // 1. Fetch the raw data from the service
      final List<Map<String, dynamic>> data = await _service.getAllProjects();
      print("Fetched ${data.length} projects from Supabase");
      // 2. Convert each Map into a Project object using our factory
      setState(() {
        _savedProjects = data.map((map) => Project.fromMap(map)).toList();
      });
    } catch (e) {
      print("Error loading projects: $e");
    }
  }

  Future<void> _updateProjectName(String newName) async {
    if (newName.isEmpty || _currentProjectId == null) {
      setState(() => _isEditingName = false);
      return;
    }

    try {
      await Supabase.instance.client
          .from('projects')
          .update({'name': newName})
          .eq('id', _currentProjectId!);

      setState(() {
        _currentFileName = newName;
        _isEditingName = false;
      });
      _refreshGallery();
    } catch (e) {
      print("Error renaming project: $e");
      setState(() => _isEditingName = false);
    }
  }

  /// Renders the current dot puzzle off-screen at 300 DPI (10" Ã— 10" square)
  /// using PictureRecorder â€” no widget capture, no screenshot dependency.
  Future<Uint8List?> _renderPuzzlePng() async {
    // 300 DPI Ã— 10 inches = 3000 px per side.
    const int exportSize = 3000;
    const double virtualSize = 1024.0;
    final double scale = exportSize / virtualSize;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final exportRect = Rect.fromLTWH(0, 0, exportSize.toDouble(), exportSize.toDouble());

    // 1. White background.
    canvas.drawRect(exportRect, Paint()..color = Colors.white);

    // 2. Connecting lines â€” respect isNewPath breaks.
    final linePaint = Paint()
      ..color = const Color(0xCC000000)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    for (int i = 1; i < _dots.length; i++) {
      if (_dots[i].isNewPath) continue;
      canvas.drawLine(
        Offset(_dots[i - 1].x * scale, _dots[i - 1].y * scale),
        Offset(_dots[i].x * scale, _dots[i].y * scale),
        linePaint,
      );
    }

    // 3. Dots with sequence numbers â€” scaled to 300 DPI.
    const double dotRadius = 14.0;
    for (int i = 0; i < _dots.length; i++) {
      final x = _dots[i].x * scale;
      final y = _dots[i].y * scale;

      canvas.drawCircle(Offset(x, y), dotRadius, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, y),
        dotRadius,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${_dots[i].sequenceOrder}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(exportSize, exportSize);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveToGallery() async {
    if (_dots.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final bytes = await _renderPuzzlePng();
      if (bytes == null) throw Exception('PNG encoding returned null bytes');
      await saveImageBytes(bytes, '${_currentFileName ?? 'dot2dot_puzzle'}.png');
    } catch (e) {
      debugPrint('âŒ PNG Export Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Export failed — please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _confirmReset() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Reset Project?"),
            content: const Text(
              "This will clear all your manual erasures and return the dots to their original density. This cannot be undone.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                child: const Text("Reset Everything"),
              ),
            ],
          ),
        ) ??
        false; // Default to false if they click outside the box
  }

  Future<void> updateProjectStats(
    String projectId, {
    int? dotCount,
    String? difficulty,
  }) async {
    await Supabase.instance.client
        .from('projects')
        .update({
          if (dotCount != null) 'dot_count': dotCount,
          if (difficulty != null) 'difficulty': difficulty,
        })
        .eq('id', projectId);
  }

  Future<void> _saveManualEdits() async {
    if (_currentProjectId == null || !_hasUnsavedChanges) return;

    // ðŸŽ¯ FIX: Use dot.toJson() to preserve labels, order, and jumps!
    final jsonDots = _dots.map((d) => d.toJson()).toList();

    final jsonErasedPoints = _erasedPoints.map((p) => [p.dx, p.dy]).toList();

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client
          .from('projects')
          .update({
            'dots':
                jsonDots, // Now contains [{x:.., y:.., is_new_path:..}, ...]
            'erased_points': jsonErasedPoints,
            'sparsity': _sparsity.toInt(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _currentProjectId!);

      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("âŒ Sync error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onAddDot(Offset pos) {
    setState(() {
      // ðŸŽ¯ Save history snapshot
      _undoStack.add(
        ProjectState(
          dots: List<Dot>.from(_dots),
          erasedPoints: List<Offset>.from(_erasedPoints),
        ),
      );
      if (_undoStack.length > 100) _undoStack.removeAt(0);
      _redoStack.clear(); // Wiped on new state branch

      _dots.add(
        Dot(
          x: pos.dx,
          y: pos.dy,
          sequenceOrder: _dots.length + 1,
          label: '${_dots.length + 1}',
        ),
      );
      _isSyncing = true;
    });

    _debouncedSave();
  }

  // Use a simple timer to avoid hitting the DB 60 times a second
  Timer? _saveTimer;
  void _debouncedSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () async {
      if (_currentProject != null) {
        await _service.saveDots(_currentProject!.id, _dots);
        // Update the dot count in the project metadata too
        await _service.updateProjectStats(
          _currentProject!.id,
          dotCount: _dots.length,
        );
        if (mounted) setState(() => _isSyncing = false);
      }
    });
  }

  void _processGameTap(Offset localPos, double boxSize) {
    if (_nextTargetIndex >= _dots.length) return;

    // Find the true context container boundaries
    final RenderBox? canvasBox =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;

    // CRITICAL: Ensure we measure the true visual layout box dimensions accurately.
    // If the canvasBox isn't attached yet, fall back to the exact bounded boxSize constraint.
    final double realWidth = (canvasBox != null && canvasBox.hasSize)
        ? canvasBox.size.width
        : boxSize;

    // Use the exact width factor bounding your 1024x1024 project template
    double scale = realWidth / 1024.0;

    // 1. Target Logic
    final targetDot = _dots[_nextTargetIndex];
    final targetPos = Offset(targetDot.x * scale, targetDot.y * scale);
    final distance = (localPos - targetPos).distance;

    // Debug statement to help you see exactly what the math is doing when your son taps!
    print(
      "Tapped at: $localPos, Target is at: $targetPos, Calculated Distance: $distance (Scale: $scale)",
    );

    if (distance < 45.0) {
      // Slightly increased hit radius for more forgiving touches on mobile/web!
      print("ðŸŽ¯ TARGET HIT! Current Index: $_nextTargetIndex");
      setState(() {
        _nextTargetIndex++;
        _wrongDotIndices.clear();
        HapticFeedback.lightImpact();
        _rippleController.forward(from: 0.0);
      });

      if (_nextTargetIndex >= _dots.length) {
        _handleWin();
      }
      return; // ðŸ˜Š Exits early on success!
    } else {
      // âŒ WRONG HIT logic
      bool hitAnyOtherDot = false;

      for (int i = 0; i < _dots.length; i++) {
        // ðŸŽ¯ THE FIX: Skip the current target AND any dots he has already successfully connected!
        // If he accidentally taps an old dot, we ignore it instead of punishing him.
        if (i <= _nextTargetIndex) continue;

        // Use the identical real layout scale factor for mistake checks
        final dotX = _dots[i].x * scale;
        final dotY = _dots[i].y * scale;
        final dPos = Offset(dotX, dotY);

        if ((localPos - dPos).distance < 15.0) {
          hitAnyOtherDot = true;

          setState(() {
            if (!_wrongDotIndices.contains(i)) {
              _lives--;
              _wrongDotIndices.add(i);
              HapticFeedback.heavyImpact();
            }
          });
          break;
        }
      }

      if (hitAnyOtherDot && _lives <= 0) {
        _handleGameOver();
      }
    }
  }

  void _handleCanvasTap(dynamic details, double boxSize) {
    // ðŸ›¡ï¸ SECURITY FIX: If we are in game mode, abort immediately!
    // Game mode is already fully handled inside onTapDown.
    if (_isGameMode) return;

    // --- EXISTING EDITOR LOGIC ---
    if (_isPanMode) return;

    final RenderBox? box =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final Offset localOffset = details.localPosition;
    double invScale = 1024 / boxSize;
    Offset touch1024 = Offset(
      localOffset.dx * invScale,
      localOffset.dy * invScale,
    );

    setState(() => _debugMousePos = localOffset);

    if (_isEraserMode) {
      // Collect all dots within a 30 px hit radius (wider than the old 14 px
      // click radius so overlapping dots are reliably surfaced).
      const double hitRadius = 30.0;
      final List<Dot> nearby = _dots.where((dot) {
        return (Offset(dot.x, dot.y) - touch1024).distance < hitRadius;
      }).toList();

      if (nearby.isEmpty) return;

      if (nearby.length == 1) {
        // Unambiguous â€” delete immediately, same as before.
        _deleteDotByLabel(nearby.first.label);
      } else {
        // Multiple overlapping dots â€” let the user choose which one.
        nearby.sort((a, b) => a.sequenceOrder.compareTo(b.sequenceOrder));
        _showEraserDisambiguationMenu(details.globalPosition, nearby);
      }
    } else if (_isRevealMode) {
      // Reveal mode â€” paint a background reveal circle at this position.
      // Does NOT touch _dots. The MaskPainter will render a transparent hole
      // in the canvas mask so the reference image shows through.
      setState(() {
        _undoStack.add(
          ProjectState(
            dots: List<Dot>.from(_dots),
            erasedPoints: List<Offset>.from(_erasedPoints),
          ),
        );
        if (_undoStack.length > 100) _undoStack.removeAt(0);
        _redoStack.clear();

        _erasedPoints.add(touch1024);
        HapticFeedback.lightImpact();
        _hasUnsavedChanges = true;
      });

      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(
        const Duration(seconds: 2),
        () => _saveManualEdits(),
      );
    } else if (_isInsertMode) {
      // Insert mode — tap existing dot to set anchor, tap empty space to insert.
      const double hitRadius = 30.0;
      final Dot? tappedDot = _dots.cast<Dot?>().firstWhere(
        (d) => (Offset(d!.x, d.y) - touch1024).distance < hitRadius,
        orElse: () => null,
      );

      if (tappedDot != null) {
        setState(() => _insertAnchorIndex = _dots.indexOf(tappedDot));
        HapticFeedback.selectionClick();
        return;
      }

      final int? anchor = _insertAnchorIndex;
      if (anchor == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tap an existing dot first to set the insertion point.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      setState(() {
        _undoStack.add(ProjectState(
          dots: List<Dot>.from(_dots),
          erasedPoints: List<Offset>.from(_erasedPoints),
        ));
        if (_undoStack.length > 100) _undoStack.removeAt(0);
        _redoStack.clear();

        final int insertPos = anchor + 1;
        _dots.insert(
          insertPos,
          Dot(
            x: touch1024.dx,
            y: touch1024.dy,
            sequenceOrder: insertPos + 1,
            label: '${insertPos + 1}',
            isNewPath: false,
          ),
        );
        for (int i = 0; i < _dots.length; i++) {
          _dots[i] = _dots[i].copyWith(sequenceOrder: i + 1, label: '${i + 1}');
        }
        _insertAnchorIndex = insertPos;
        HapticFeedback.mediumImpact();
        _hasUnsavedChanges = true;
      });

      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(seconds: 2), () => _saveManualEdits());

    } else {
      // Draw mode â€” add a new dot at the end.
      setState(() {
        _undoStack.add(
          ProjectState(
            dots: List<Dot>.from(_dots),
            erasedPoints: List<Offset>.from(_erasedPoints),
          ),
        );
        if (_undoStack.length > 100) _undoStack.removeAt(0);
        _redoStack.clear();

        final int nextNumber = _dots.length + 1;
        _dots.add(
          Dot(
            x: touch1024.dx,
            y: touch1024.dy,
            sequenceOrder: nextNumber,
            label: '$nextNumber',
            isNewPath: _startNewPath,
          ),
        );
        _startNewPath = false;
        HapticFeedback.mediumImpact();
        _hasUnsavedChanges = true;
      });

      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(
        const Duration(seconds: 2),
        () => _saveManualEdits(),
      );
    }
  }

  // â”€â”€â”€ Eraser helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Single source of truth for deleting a dot by its label string.
  /// Handles undo snapshot, resequencing, erased-point tracking, and auto-save.
  void _deleteDotByLabel(String label) {
    final int idx = _dots.indexWhere((d) => d.label == label);
    if (idx == -1) return;

    setState(() {
      _undoStack.add(
        ProjectState(
          dots: List<Dot>.from(_dots),
          erasedPoints: List<Offset>.from(_erasedPoints),
        ),
      );
      if (_undoStack.length > 100) _undoStack.removeAt(0);
      _redoStack.clear();

      _dots.removeAt(idx);

      // Resequence labels after the removed dot.
      for (int i = 0; i < _dots.length; i++) {
        _dots[i] = _dots[i].copyWith(sequenceOrder: i + 1, label: '${i + 1}');
      }

      _hasUnsavedChanges = true;
    });

    HapticFeedback.lightImpact();
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(
      const Duration(seconds: 2),
      () => _saveManualEdits(),
    );
  }

  /// Shows a contextual popup listing overlapping dot candidates so the user
  /// can pick exactly which dot to delete instead of guessing.
  void _showEraserDisambiguationMenu(
    Offset globalPos,
    List<Dot> candidates,
  ) {
    final RelativeRect position = RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      globalPos.dx,
      globalPos.dy,
    );

    showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            'Delete which dot?',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
        ...candidates.map(
          (dot) => PopupMenuItem<String>(
            value: dot.label,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.circle, size: 8, color: Colors.black54),
                const SizedBox(width: 8),
                Text(
                  'Dot ${dot.label}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    ).then((selectedLabel) {
      if (selectedLabel != null) _deleteDotByLabel(selectedLabel);
    });
  }

  /// Opens a dialog where the user types a dot number to delete directly,
  /// without having to click on the canvas at all.
  void _showDeleteByNumberDialog() {
    final TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete dot by number'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Dot number',
            hintText: '1 â€“ ${_dots.length}',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _confirmDeleteByNumber(ctx, ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _confirmDeleteByNumber(ctx, ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  void _confirmDeleteByNumber(BuildContext ctx, String input) {
    final int? n = int.tryParse(input.trim());
    if (n == null || n < 1 || n > _dots.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enter a number between 1 and ${_dots.length}'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    Navigator.pop(ctx);
    _deleteDotByLabel(n.toString());
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  // ðŸ† 1. THE WIN LOGIC
  void _handleWin() {
    print("ðŸš€ Inside _handleWin function");

    // 1. Identify which difficulty was cleared
    bool easyWon = !_isMediumMode && !_isHardMode;
    bool mediumWon = _isMediumMode;
    bool hardWon = _isHardMode;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentProject == null) return;

      // 2. Create the updated object FIRST
      final updated = _currentProject!.copyWith(
        easyCleared: _currentProject!.easyCleared || easyWon,
        mediumCleared: _currentProject!.mediumCleared || mediumWon,
        hardCleared: _currentProject!.hardCleared || hardWon,
        lastIndex: 0, // level complete â€” next play starts from dot 1
      );

      // 3. Update the UI and Local Cache
      setState(() {
        _currentProject = updated;

        // Update local list so the gallery reflects changes even before a refresh
        int index = _savedProjects.indexWhere((p) => p.id == updated.id);
        if (index != -1) {
          _savedProjects[index] = updated;
        }
      });

      // 4. ðŸ”¥ THE PERSISTENCE: Save this specific 'updated' object to Supabase
      _saveToDatabase(updated);

      // Mark daily challenge complete and refresh the banner.
      if (_isDailyChallenge) {
        _isDailyChallenge = false;
        DailyChallengeService.markCompleted().then((newStreak) {
          if (mounted) {
            setState(() { _isDailyCompleted = true; _dailyStreak = newStreak; });
          }
        });
      }

      _confettiController.play();
      if (_currentProjectId != null) {
        AnalyticsService.puzzleCompleted(_currentProjectId!);
      }

      // 5. Show Dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "WONDERFUL!",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars, color: Colors.orange, size: 60),
                const SizedBox(height: 16),
                Text(
                  "You've successfully revealed the ${updated.name}!",
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.share_outlined),
                    label: const Text("Share"),
                    onPressed: () => ShareService.shareCompletion(updated),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _isGameMode = false;
                        _isInPuzzle = false;
                      });
                      _refreshGallery();
                    },
                    child: const Text("BACK TO GALLERY"),
                  ),
                ],
              ),
            ],
          );
        },
      );
    });
  }

  // ðŸ’€ 2. THE GAME OVER LOGIC
  void _handleGameOver() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("GAME OVER"),
        content: const Text("You ran out of lives! Want to try again?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isInPuzzle = false); // Quit to menu
            },
            child: const Text("QUIT"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (_currentProject != null) {
                _startGame(
                  _currentProject!,
                ); // ðŸ‘ˆ Use the saved project to restart
              }
            },
            child: const Text("RETRY"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToDatabase(Project project) async {
    try {
      await Supabase.instance.client
          .from('projects')
          .update(project.toMap())
          .eq('id', project.id);

      print("âœ… All progress (Stars, Index, and Eraser) saved to Supabase!");
    } catch (e) {
      print("âŒ SUPABASE ERROR: $e");
    }
  }

  void _generateInitialDots(int count) {
    if (_imageWidth == null || _imageHeight == null) return;

    setState(() {
      setState(() {
        // ðŸŽ¯ Save history snapshot before clearing out old layout
        _undoStack.add(
          ProjectState(
            dots: List<Dot>.from(_dots),
            erasedPoints: List<Offset>.from(_erasedPoints),
          ),
        );
        if (_undoStack.length > 20) _undoStack.removeAt(0);
        _redoStack.clear(); // Wiped on new state branch

        _dots.clear();
        // For now, let's just place dots in a circular pattern as a placeholder
        // In a real AI version, your Node server would return the outline points!
        for (int i = 0; i < count; i++) {
          double angle = (i / count) * 2 * 3.14159;
          double rx = (_imageWidth! / 3) * (0.8 + (i % 2 == 0 ? 0.2 : 0));
          _dots.add(
            Dot(
              x: (_imageWidth! / 2) + rx * (0.5 * cos(angle)),
              y: (_imageHeight! / 2) + rx * (0.5 * sin(angle)),
              sequenceOrder: i + 1,
              label: '${i + 1}',
            ),
          );
        }
      });
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;

    setState(() {
      // 1. Save current active layout into redo stack before shifting backwards
      _redoStack.add(
        ProjectState(
          dots: List<Dot>.from(_dots),
          erasedPoints: List<Offset>.from(_erasedPoints),
        ),
      );

      // 2. Extrude the latest frame out of the history stack
      final previousState = _undoStack.removeLast();
      _dots = previousState.dots;
      _erasedPoints = previousState.erasedPoints;
      _hasUnsavedChanges = true;
    });

    // Trigger save to synchronize backend database
    _debouncedSave();
  }

  void _loadProject(Map<String, dynamic> projectData) {
    // If we're re-opening the project that is already loaded in this session,
    // the image bytes are still in memory â€” skip the network download entirely.
    final bool reuseImage =
        projectData['id'] != null &&
        projectData['id'] == _currentProjectId &&
        _selectedImageBytes != null;

    setState(() {
      _isLoading = !reuseImage;
      if (!reuseImage) _selectedImageBytes = null;
      _nextTargetIndex = 0; // ðŸŽ¯ RESET
      _userPath = []; // ðŸŽ¯ RESET
      _wrongDotIndices.clear(); // ðŸŽ¯ RESET
      _isGameOver = false; // ðŸŽ¯ RESET
      _currentProjectId = projectData['id'];

      final String? savedUrl = projectData['image_path'];
      _currentImageUrl = (savedUrl != null && savedUrl.isNotEmpty) ? savedUrl : null;

      _nameController.text = projectData['name'] ?? "Untitled Wonder";

      // 2. Sparsity & Constants
      _currentSparsity = projectData['sparsity'] ?? 20;
      _sparsity = (_currentSparsity).toDouble();

      // 3. The Dots (Diagnostic "Final Boss" Version)
      final dynamic dotsData = projectData['dots'];
      print("ðŸ” DEBUG: dotsData type is ${dotsData.runtimeType}");
      print("ðŸ” DEBUG: dotsData content: $dotsData");

      List<dynamic> rawDots = [];

      if (dotsData is String) {
        try {
          rawDots = jsonDecode(dotsData) as List<dynamic>;
          print("ðŸ” DEBUG: Parsed from String. Length: ${rawDots.length}");
        } catch (e) {
          print("âŒ DEBUG: JSON Decode error: $e");
        }
      } else if (dotsData is List) {
        rawDots = dotsData;
        print("ðŸ” DEBUG: Identified as List. Length: ${rawDots.length}");
      } else {
        print(
          "âŒ DEBUG: dotsData is neither String nor List. It is ${dotsData.runtimeType}",
        );
      }

      _dots = rawDots.map<Dot>((val) {
        // Try Map/JSON format
        if (val is Map) {
          return Dot.fromJson(Map<String, dynamic>.from(val));
        }
        // Try List [x, y] format
        if (val is List && val.length >= 2) {
          return Dot.fromIndexedList(0, val); // Placeholder index
        }
        return Dot(x: 0, y: 0, sequenceOrder: 1, label: "?");
      }).toList();

      print("âœ… Successfully Parsed ${_dots.length} dots from DB");

      // 4. The Erasures
      final List<dynamic> rawErasures =
          projectData['erased_points'] as List? ?? [];
      _erasedPoints = rawErasures.map((e) {
        return Offset((e[0] as num).toDouble(), (e[1] as num).toDouble());
      }).toList();

      // 5. Interface Cleanup
      _undoStack = [];
      _hasUnsavedChanges = false;

      // Determine mode based on where we came from
      _isGameMode = _currentMenuPath == 'game';
      _isInPuzzle = true;
      _showOriginal = true;
    });

    if (reuseImage) return; // bytes already in memory â€” nothing to download

    if (_currentImageUrl != null) {
      _downloadImage(_currentImageUrl!);
    } else {
      print("âš ï¸ No valid image URL for project: $_currentProjectId");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadImage(String url) async {
    if (mounted) setState(() => _isLoading = true);

    // Try local cache first so the puzzle opens instantly when offline.
    if (_currentProjectId != null) {
      final cached = await OfflineCache.loadImage(_currentProjectId!);
      if (cached != null) {
        final decodedImage = await decodeImageFromList(cached);
        if (mounted) {
          setState(() {
            _selectedImageBytes = cached;
            _imageWidth = decodedImage.width.toDouble();
            _imageHeight = decodedImage.height.toDouble();
            _isLoading = false;
            _showOriginal = true;
            _isInPuzzle = true;
          });
        }
        // Still try to refresh from network in background (silently).
        _refreshImageFromNetwork(url);
        return;
      }
    }

    await _refreshImageFromNetwork(url);
  }

  Future<void> _refreshImageFromNetwork(String url) async {
    try {
      const String bucketMarker = '/images/';
      final int idx = url.indexOf(bucketMarker);
      final String storagePath = idx != -1
          ? Uri.decodeComponent(
              url.substring(idx + bucketMarker.length).split('?').first,
            )
          : Uri.decodeComponent(url.split('/').last.split('?').first);

      final Uint8List bytes = await Supabase.instance.client.storage
          .from('images')
          .download(storagePath);

      // Persist for future offline use.
      if (_currentProjectId != null) {
        OfflineCache.saveImage(_currentProjectId!, bytes);
      }

      final decodedImage = await decodeImageFromList(bytes);
      if (mounted) {
        setState(() {
          _selectedImageBytes = bytes;
          _imageWidth = decodedImage.width.toDouble();
          _imageHeight = decodedImage.height.toDouble();
          _isLoading = false;
          _showOriginal = true;
          _isInPuzzle = true;
        });
      }
    } catch (e) {
      debugPrint('âŒ Image download error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String id,
    String path,
    String name,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Project?"),
        content: Text(
          "Are you sure you want to delete '$name'? This cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("DELETE", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteProject(id, path);

        setState(() {
          _savedProjects.removeWhere((p) => p.id == id);
          if (_currentProjectId == id) {
            _currentProjectId = null;
            _selectedImageBytes = null;
            _dots = [];
            _isInPuzzle = false;
          }
        });
        _refreshGallery();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Project deleted successfully")),
        );
      } catch (e) {
        print("Delete error: $e");
      }
    }
  }

  void _onSparsityChanged(double value) {
    setState(() {
      _currentSparsity = value.toInt();
    });

    // Cancel the previous timer if it's still running
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Start a new 500ms timer
    _debounce = Timer(const Duration(milliseconds: 500), () {
      // ðŸŽ¯ THIS runs only after the user stops for 0.5 seconds
      _triggerReprocess();
    });
  }

  Future<void> _triggerReprocess() async {
    if (_currentProjectId == null) return;

    setState(() {
      _mainStatus = "Adjusting dots...";
      _subStatus = "Sparsity: $_currentSparsity";
    });

    try {
      // We will build this endpoint in your Node.js index.ts next!
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/reprocess'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'projectId': _currentProjectId,
          'sparsity': _currentSparsity,
        }),
      );

      if (response.statusCode == 200) {
        // Start polling again to get the new dots
        _waitForProcessing(_currentProjectId!);
      }
    } catch (e) {
      print("Reprocess error: $e");
    }
  }

  Future<void> _waitForProcessing(String projectId) async {
    // Cancel any subscription left over from a previous processing run.
    await _processingChannel?.unsubscribe();

    // Safety-net: unsubscribe after 7 minutes regardless.
    final timeout = Timer(const Duration(minutes: 7), () async {
      await _processingChannel?.unsubscribe();
      _processingChannel = null;
      if (mounted) setState(() => _mainStatus = "Processing timed out");
    });

    _processingChannel = Supabase.instance.client
        .channel('processing-$projectId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'projects',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: projectId,
          ),
          callback: (payload) async {
            final status = payload.newRecord['status'] as String?;
            if (status == 'completed' || status == 'error') {
              timeout.cancel();
              await _processingChannel?.unsubscribe();
              _processingChannel = null;
            }
            if (status == 'completed') {
              // Fetch the full row â€” realtime payload may omit unchanged columns.
              final data = await Supabase.instance.client
                  .from('projects')
                  .select()
                  .eq('id', projectId)
                  .single();
              if (mounted) {
                _loadProject(data);
                setState(() {
                  _mainStatus = "Done!";
                  _subStatus = "";
                });
              }
            } else if (status == 'error') {
              if (mounted) setState(() => _mainStatus = "Generation failed");
            }
          },
        )
        .subscribe();
  }

  Future<void> _uploadAndProcess({
    Uint8List? droppedBytes,
    String? droppedName,
  }) async {
    // ðŸªµ DEBUG LOG
    print("ðŸªµ [_uploadAndProcess] TRIGGERED!");
    print(
      "   -> passed droppedBytes: ${droppedBytes != null ? '${droppedBytes.length} bytes' : 'NULL'}",
    );
    print("   -> passed droppedName: $droppedName");
    print(
      "   -> current _selectedImageBytes state: ${_selectedImageBytes != null ? '${_selectedImageBytes!.length} bytes' : 'NULL'}",
    );

    try {
      Uint8List? imageToUse = droppedBytes ?? _selectedImageBytes;
      String? nameToUse = droppedName ?? _currentFileName;

      if (imageToUse == null) {
        print(
          "ðŸªµ [_uploadAndProcess] imageToUse is NULL. Launching FilePicker native window...",
        );

        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );

        if (result == null || result.files.single.bytes == null) {
          print(
            "ðŸªµ [_uploadAndProcess] Native FilePicker window was CANCELLED by user.",
          );
          return;
        }

        print(
          "ðŸªµ [_uploadAndProcess] Native FilePicker picked file successfully: ${result.files.single.name}",
        );
        imageToUse = result.files.single.bytes;
        nameToUse = result.files.single.name;
      }

      // Validate file type before touching the server
      final ext = (nameToUse ?? '').split('.').last.toLowerCase();
      const supportedExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
      if (!supportedExts.contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              '.$ext files aren\'t supported. Please use a JPG, PNG, or WebP image.',
            ),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 4),
          ));
        }
        return;
      }

      // ðŸŽ¯ Only reset the ID if it's a TRULY new file from the computer
      if (droppedBytes != null || droppedName != null) {
        _erasedPoints = [];
        _currentProjectId = null;
      }

      // 2. Initial State Setup
      setState(() {
        _selectedImageBytes = imageToUse;
        _currentFileName = nameToUse;
        _isLoading = true;
        _dots = [];
        _mainStatus = "Preparing...";
        _subStatus = "Uploading to secure storage...";
      });

      // 2. Start the Tip Carousel
      _tipIndex = 0;
      _loadingTimer?.cancel();
      _loadingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
        setState(() {
          _tipIndex = (_tipIndex + 1) % _processingTips.length;
          _subStatus = _processingTips[_tipIndex];
        });
      });

      // 3. Upload and get Project ID
      final projectId = await _service.uploadImage(
        imageToUse!,
        nameToUse ?? "wonder_${DateTime.now().millisecondsSinceEpoch}",
        _sparsity.toInt(),
        projectId: _currentProjectId,
        removeBg: _removeBg,
      );

      setState(() {
        _currentProjectId = projectId;
      });

      // 4. Polling Loop
      int attempts = 0;
      const int maxAttempts = 360; // 6 minutes — matches server job_timeout
      await Future.delayed(const Duration(seconds: 2)); // Initial grace period

      while (attempts < maxAttempts) {
        await Future.delayed(const Duration(seconds: 1));

        // Fetch latest status
        final data = await _service.getProjectStatus(projectId);
        final String currentStatus = data['status'];

        print("ðŸ“¡ Polling Status: $currentStatus for ID: $projectId");

        if (currentStatus == 'processing') {
          setState(() {
            _mainStatus = _removeBg
                ? "AI BACKGROUND REMOVAL"
                : "AI EDGE DETECTION";
            _subStatus = "Analyzing image details...";
            _isLoading = true;
          });
        }

        // --- CASE 1: SUCCESS ---
        if (currentStatus == 'completed') {
          _loadingTimer?.cancel();

          // If the user navigated to a different project while this was processing,
          // don't overwrite their current state — just update the gallery.
          if (_currentProjectId != projectId) {
            if (mounted) _refreshGallery();
            return;
          }

          // Grab raw dots from the Service
          List<Dot> rawDots = List<Dot>.from(data['dots']);

          // Filter based on Eraser Memory (Ghost Zones)
          List<Dot> filteredDots = rawDots.where((newDot) {
            return !_erasedPoints.any((erasedPos) {
              final double dist =
                  (Offset(newDot.x, newDot.y) - erasedPos).distance;
              return dist < 25.0;
            });
          }).toList();

          // Re-index for UI display
          for (int i = 0; i < filteredDots.length; i++) {
            filteredDots[i] = filteredDots[i].copyWith(label: '${i + 1}');
          }

          if (mounted) {
            setState(() {
              _dots = filteredDots;
              _isLoading = false;
              _mainStatus = "";
              _subStatus = "";
            });
            _refreshGallery();
          }

          print("âœ… Process complete: ${_dots.length} dots rendered.");
          return;
        }

        // --- CASE 3: ERROR ---
        if (currentStatus == 'error') {
          throw Exception("worker_error");
        }

        attempts++;
      }

      if (attempts >= maxAttempts) {
        throw Exception("timeout");
      }
    } catch (e) {
      _loadingTimer?.cancel();
      debugPrint('Processing failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _mainStatus = "";
          _subStatus = "";
        });
        final msg = e.toString().contains("timeout")
            ? "Dot generation is taking too long — please try again."
            : "Couldn't generate dots. Try a different image or adjust the sparsity slider.";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Helper for the empty gallery state
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_motion, color: Colors.grey[300], size: 48),
            const SizedBox(height: 16),
            Text(
              "No puzzles yet!\nUpload a photo to start.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper for the Zoom Buttons in the Top Bar
  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            onPressed: () => _zoom(0.8),
            tooltip: "Zoom Out",
          ),
          Text(
            "${(_currentScale * 100).toInt()}%",
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => _zoom(1.2),
            tooltip: "Zoom In",
          ),
          if (_currentScale > 1.0)
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _resetZoom,
              tooltip: "Reset Zoom",
            ),
        ],
      ),
    );
  }

  // The PDF Export Logic (Make sure to run: flutter pub add pdf printing)
  Widget _buildEraserCrosshair(double boxSize) {
    // 1. Get the current zoom/pan data from the controller matrix
    final Matrix4 matrix = _transformationController.value;
    final double scale = matrix.getMaxScaleOnAxis();
    final double tx = matrix.getTranslation().x;
    final double ty = matrix.getTranslation().y;

    // 2. Adjust the local mouse position to match the global stack position
    // We multiply the local position by the scale and add the translation offset
    final double visualX = (_debugMousePos!.dx * scale) + tx;
    final double visualY = (_debugMousePos!.dy * scale) + ty;

    return Positioned(
      // 15 is half the container width (30) to center the "X"
      left: visualX - 15,
      top: visualY - 15,
      child: IgnorePointer(
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.red.withOpacity(0.5), width: 2),
          ),
          child: const Center(
            child: Icon(Icons.close, color: Colors.red, size: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // ðŸ” Sidebar Toggle
          IconButton(
            icon: Icon(_isSidebarOpen ? Icons.menu_open : Icons.menu),
            onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
            tooltip: "Toggle Sidebar",
          ),

          const SizedBox(width: 8),

          // 1. App Title
          if (MediaQuery.of(context).size.width > 700) _buildProjectName(),

          // 2. CENTER PIECE: Hearts
          Expanded(
            child: _isGameMode
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: _buildShakingHearts(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // 3. TOOLS GROUP
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. ALWAYS show Zoom Controls (even in Game Mode)
              _buildZoomControls(),

              // Add a 'Reset View' button for desktop users
              IconButton(
                icon: const Icon(Icons.fullscreen_exit, size: 20),
                tooltip: "Reset View",
                onPressed: () =>
                    _transformationController.value = Matrix4.identity(),
              ),

              if (!_isGameMode) ...[
                // --- CREATOR ONLY ---
                const VerticalDivider(width: 20, indent: 16, endIndent: 16),
                _buildSyncStatus(),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(
                    _isEraserMode ? Icons.auto_fix_high : Icons.auto_fix_off,
                    color: _isEraserMode ? Colors.blueAccent : Colors.grey,
                  ),
                  tooltip: "Eraser Mode",
                  onPressed: () =>
                      setState(() => _isEraserMode = !_isEraserMode),
                ),
                IconButton(
                  onPressed: _undoStack.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo, size: 20),
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                  ),
                ),

                if (MediaQuery.of(context).size.width > 800) ...[
                  const VerticalDivider(width: 32, indent: 16, endIndent: 16),
                  TextButton.icon(
                    onPressed: _saveToGallery,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text("PNG"),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _dots.isEmpty
                        ? null
                        : () => PdfService.generateAndPrint(
                            _dots,
                            _currentFileName ?? "puzzle",
                            imageBytes: _selectedImageBytes,
                          ),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text("Export PDF"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                ],
              ] else ...[
                // --- GAME ONLY TOOLS ---
                if (_isHardMode)
                  const Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: Icon(
                      Icons.psychology,
                      color: Colors.purple,
                      size: 22,
                    ),
                  ),

                // ðŸŽ¯ THE HINT BUTTON
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_lives <= 1) {
                        _heartShakeController.forward(from: 0.0);
                        HapticFeedback.vibrate();
                        return;
                      }
                      setState(() {
                        _lives--;
                        _showHint = true;
                        _heartShakeController.forward(from: 0.0);
                      });
                      Timer(const Duration(seconds: 3), () {
                        if (mounted) setState(() => _showHint = false);
                      });
                    },
                    icon: const Icon(Icons.lightbulb_outline, size: 18),
                    label: const Text("HINT"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ], // End of Game Tools Spread
            ], // End of Tools Row Children
          ), // End of Tools Row
        ], // End of Main Row Children
      ), // End of Main Row
    ); // End of Container
  }

  Widget _buildConfigurationSection(StateSetter setModalState) {
    final int estimatedDots = (4500 / (_sparsity + 6)).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- SECTION 1: HEADER & GENERATE ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "DOT STUDIO",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF7D060), // ðŸŒŸ Amber Gold Title Label
                  letterSpacing: 2.0,
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4EFE98), // ðŸ¦– Neon Green progress loader
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ðŸŽ¯ MAIN ACTION: GENERATE
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text(
                "GENERATE AI DOTS",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(
                  0xFF4EFE98,
                ), // ðŸ¦– Neon Tyranno Green Hero button
                foregroundColor: const Color(
                  0xFF111E18,
                ), // Deep Charcoal text contrast
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                _uploadAndProcess();
              },
            ),
          ),
          const SizedBox(height: 24),

          // --- SECTION 2: AI PARAMETERS ---
          _buildSectionHeader("AI PARAMETERS"),
          _buildToggle(
            "Remove Background",
            "AI will attempt to isolate the subject",
            _removeBg,
            Icons.layers_clear_outlined,
            (val) {
              setModalState(
                () => _removeBg = val,
              ); // âš¡ Updates the modal UI immediately!
              setState(
                () => _removeBg = val,
              ); // Updates the core background state logic
            },
          ),
          const SizedBox(height: 16),

          // Sparsity / Complexity Control
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Complexity",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF1F7F4),
                ),
              ),
              Text(
                "~$estimatedDots dots",
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF4EFE98), // Neon Green feedback indicator
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _sparsity,
            min: 5,
            max: 100,
            activeColor: const Color(0xFF4EFE98), // Neon Slider handle
            inactiveColor: const Color(0xFF253B30), // Moss background track
            onChanged: (val) {
              setModalState(() => _sparsity = val);
              setState(() => _sparsity = val);
            },
          ),
          const SizedBox(height: 16),

          // --- SECTION 3: DISPLAY SETTINGS ---
          _buildSectionHeader("VIEW OPTIONS"),
          _buildToggle(
            "Show Reference Image",
            null,
            _showOriginal,
            Icons.image_outlined,
            (val) {
              setModalState(
                () => _showOriginal = val,
              ); // âš¡ Fixes Reference toggle!
              setState(() => _showOriginal = val);
            },
          ),
          _buildToggle(
            "Show Connections",
            null,
            _showConnections,
            Icons.polyline_outlined,
            (val) {
              setModalState(
                () => _showConnections = val,
              ); // âš¡ Fixes Connections toggle!
              setState(() => _showConnections = val);
            },
          ),

          const Divider(height: 40, color: Colors.white10),

          // --- SECTION 5: EXPORT & RESET ---
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: const Text("PDF"),
                  onPressed: () => PdfService.generateAndPrint(
                    _dots,
                    _currentFileName ?? "puzzle",
                    imageBytes: _selectedImageBytes,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(
                      0xFFF7D060,
                    ), // Amber Gold label
                    side: const BorderSide(color: Color(0xFFF7D060)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text("RESET"),
                  onPressed: _handleReset,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(
                      0xFFFA5A33,
                    ), // Volcanic red warning highlight
                    side: const BorderSide(color: Color(0xFFFA5A33)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ðŸŽ¨ Helper for Section Headers
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  // Helper for the toggles themselves
  Widget _buildToggle(
    String title,
    String? subtitle,
    bool value,
    IconData icon,
    Function(bool) onChanged,
  ) {
    return SwitchListTile(
      secondary: Icon(
        icon,
        size: 20,
        color: value
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            )
          : null,
      value: value,
      activeColor: Theme.of(context).colorScheme.primary,
      activeTrackColor: Theme.of(context).colorScheme.surface,
      inactiveThumbColor: Colors.grey,
      inactiveTrackColor: Colors.black26,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }

  Widget _buildProjectName() {
    if (_currentProjectId == null) {
      return const Text(
        "DOT2DOT AI",
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
      );
    }

    if (_isEditingName) {
      return SizedBox(
        width: 200,
        child: TextField(
          controller: _nameController,
          autofocus: true,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
          onSubmitted: (newName) => _updateProjectName(newName),
          onTapOutside: (_) => setState(() => _isEditingName = false),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        _nameController.text = _currentFileName ?? "Untitled Puzzle";
        setState(() => _isEditingName = true);
      },
      child: Row(
        children: [
          Text(
            _currentFileName ?? "Untitled Puzzle",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Icon(Icons.edit_outlined, size: 14, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  Widget _buildSyncStatus() {
    if (_isLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blueAccent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "Syncing...",
            style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
          ),
        ],
      );
    }

    if (_hasUnsavedChanges) {
      return Row(
        children: [
          Icon(Icons.edit_note, color: Colors.orange.shade400, size: 20),
          const SizedBox(width: 4),
          Text(
            "Unsaved changes...",
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(Icons.cloud_done, color: Colors.green.shade400, size: 20),
        const SizedBox(width: 4),
        Text(
          "All changes saved",
          style: TextStyle(color: Colors.green.shade700, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCanvas(double boxSize) {
    // ðŸ›¡ï¸ Ensure dragging an image only works when you are actually in Studio Mode
    if (_isGameMode) return _buildGameView(boxSize);

    return DropTarget(
      onDragDone: (detail) async {
        final file = detail.files.first;
        final ext = file.name.split('.').last.toLowerCase();
        const supportedExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
        if (!supportedExts.contains(ext)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                '.$ext files aren\'t supported. Please drop a JPG, PNG, or WebP image.',
              ),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 4),
            ));
          }
          return;
        }
        final bytes = await file.readAsBytes();

        setState(() {
          // 1. Load the dropped image straight into your active canvas state variable
          _selectedImageBytes = bytes;
          _currentFileName = file.name;

          // 2. Fresh slate: Wipe out any old puzzle tracking or auto-dots
          _dots.clear();
          _wrongDotIndices.clear();
          _nextTargetIndex = 0;

          // 3. Keep loading false so it skips the overlay and drops right into the workspace
          _isLoading = false;
        });
      },
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: Stack(
        children: [
          // LAYER 1: The Main Work Area
          Center(
            child: Container(
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                // ðŸŽ¨ DINO UPGRADE: Earthy dark background slate for drawing
                color: const Color(0xFF1B2A22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDragging
                      ? const Color(
                          0xFF4EFE98,
                        ) // Glow neon green when dragging over it!
                      : Colors.white10,
                  width: _isDragging ? 3 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 15,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              // THE LOGIC GATE
              child: _isLoading
                  ? _buildLoadingOverlay()
                  : (_selectedImageBytes == null)
                  ? _buildUploadPlaceholder()
                  : _buildImageStack(boxSize),
            ),
          ),

          // LAYER 2: THE MINI MAP (Floats cleanly on top)
          if (_selectedImageBytes != null && !_isLoading)
            Positioned(
              bottom: 20,
              right: 20,
              child: _buildMiniMap(
                boxSize,
              ), // ðŸ‘ˆ Re-inserting your Mini Map here
            ),
          if (_isLoading)
            Container(
              color: Colors.black12, // Subtle dimming
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        if (_mainStatus.isEmpty) ...[
                          SizedBox(height: 12),
                          Text(
                            "AI is recalculating dots...",
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonItem() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 120, height: 12, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(width: 80, height: 10, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // A sleek, thin progress indicator
          const SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: Color(0xFFEEEEEE),
              color: Colors.black,
              minHeight: 2,
            ),
          ),
          const SizedBox(height: 32),
          // The Main Task
          Text(
            _mainStatus.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 2.0,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          // The Rotating Tip
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(
              _subStatus,
              key: ValueKey(_subStatus), // Animates the text change
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadPlaceholder() {
    print(
      "ðŸªµ [_buildUploadPlaceholder] Widget is building onto the screen right now.",
    );
    return Container(
      // Match the dark moss-slate background theme of Dot Studio
      color: const Color(0xFF0D1511),
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      child: Container(
        width: 400,
        height: 250,
        decoration: BoxDecoration(
          color: const Color(0xFF16221B), // Slightly lighter container card
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(
              0xFF4EFE98,
            ).withOpacity(0.3), // Subtle neon glow border
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            // ðŸŽ¯ SAFE CLICK TRIGGER: Only triggers when deliberately clicked!
            onTap: () {
              print(
                "ðŸŽ¯ [INKWELL CLICK] User explicitly clicked the placeholder card container!",
              );
              _uploadAndProcess();
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Neon Green Icon
                const Icon(
                  Icons.add_a_photo_outlined,
                  size: 56,
                  color: Color(0xFF4EFE98),
                ),
                const SizedBox(height: 20),
                const Text(
                  "DRAG & DROP IMAGE",
                  style: TextStyle(
                    color: Color(0xFFF1F7F4),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "or click to browse computer files",
                  style: TextStyle(
                    color: const Color(0xFFF1F7F4).withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaticGridDashboardCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // ðŸ¦– SAFE TRACKING: Clear variables to prepare a new manual puzzle workspace layout
          setState(() {
            _selectedImageBytes = null;
            _dots = [];
            _currentProjectId = null;
            _currentFileName = null;
            _isLoading = false;
            _mainStatus = "";
            _subStatus = "";
          });
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, size: 48, color: Colors.blue[300]),
            const SizedBox(height: 12),
            Text(
              "New Puzzle",
              style: TextStyle(
                color: Colors.blue[600],
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 320,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP: A clean header instead of the messy settings
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 40, 16, 20),
            child: Text(
              "FOSSIL EXPLORER",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Colors.black,
              ),
            ),
          ),

          const Divider(height: 1),

          // 2. MIDDLE: The Gallery (Now it has more room to breathe!)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              "MY PROJECTS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: _buildGallery()),

          const Divider(height: 1),

          // 3. BOTTOM: Logout
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextButton.icon(
              onPressed: () async => await _service.signOut(),
              icon: const Icon(Icons.logout, size: 14, color: Colors.grey),
              label: const Text(
                "Sign Out",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TOP ACTION BUTTON: Keep your existing button!
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                print("ðŸš¨ [GALLERY BUTTON] 'New Puzzle' clicked!");

                // ðŸ›‘ Cancel any lingering AI polling tasks, carousels, or auto-saves safely
                print("ðŸš¨ [GALLERY BUTTON] Canceling active timers...");
                _loadingTimer?.cancel();
                _autoSaveTimer?.cancel();

                setState(() {
                  _selectedImageBytes = null;
                  _dots = [];
                  _undoStack = [];
                  _erasedPoints = [];
                  _currentProjectId = null;
                  _currentFileName = null;
                  _isLoading = false;
                  _mainStatus = "";
                  _subStatus = "";
                  _isEraserMode = false;
                });

                print(
                  "ðŸš¨ [GALLERY BUTTON] State variables successfully wiped to null.",
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text("New Puzzle"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),

        const Divider(height: 1),

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            "RECENT PROJECTS",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.1,
            ),
          ),
        ),

        // 2. THE DYNAMIC LIST
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _galleryFuture,
            builder: (context, snapshot) {
              // âœ¨ UPGRADED LOADING STATE: The Shimmer
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListView.builder(
                  itemCount: 5,
                  itemBuilder: (context, index) =>
                      _buildSkeletonItem(), // Pulse here!
                );
              }

              if (snapshot.hasError) {
                return const Center(child: Text("Error loading gallery"));
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _buildEmptyState();
              }

              final projects = snapshot.data!;
              final cs = Theme.of(context).colorScheme;
              final currentUserId =
                  Supabase.instance.client.auth.currentUser?.id;

              // Split into owned and featured sections
              final myProjects = projects
                  .where((p) => p['user_id'] == currentUserId)
                  .toList();
              final featured = projects
                  .where((p) =>
                      p['is_public'] == true &&
                      p['user_id'] != currentUserId)
                  .toList();

              // Build a flat list with section-header sentinel maps interspersed
              final List<Map<String, dynamic>> rows = [];
              if (myProjects.isNotEmpty && featured.isNotEmpty) {
                rows.add({'_header': 'MY PUZZLES'});
              }
              rows.addAll(myProjects);
              if (featured.isNotEmpty) {
                rows.add({'_header': 'FEATURED'});
                rows.addAll(featured);
              }

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: ListView.separated(
                  key: ValueKey(projects.length),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) {
                    if (rows[index].containsKey('_header')) {
                      return const SizedBox.shrink();
                    }
                    final next = index + 1;
                    if (next < rows.length &&
                        rows[next].containsKey('_header')) {
                      return const SizedBox.shrink();
                    }
                    return const Divider(height: 1);
                  },
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row.containsKey('_header')) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          row['_header'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface.withValues(alpha: 0.35),
                            letterSpacing: 1.1,
                          ),
                        ),
                      );
                    }

                    final pMap = row;
                    final p = Project.fromMap(pMap);
                    final isOwned = pMap['user_id'] == currentUserId;

                    return GalleryItem(
                      project: pMap,
                      isActive: _currentProjectId == p.id,
                      onTap: (projectData) => _loadProject(projectData),
                      isGameMenu: _currentMenuPath == 'game',
                      onDelete: isOwned
                          ? (id, fileName) => _confirmDelete(
                              context, id, p.imagePath ?? '', p.name)
                          : null,
                    );
                  },
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildGalleryIcon(Map<String, dynamic> p, bool isActive) {
    final bool isProcessing = p['status'] == 'processing';

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isProcessing
            ? Colors.orange.withOpacity(0.1)
            : (isActive ? Colors.blueAccent : Colors.blue.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isProcessing
            ? Icons.sync
            : (isActive ? Icons.edit : Icons.extension_outlined),
        size: 20,
        color: isProcessing
            ? Colors.orange
            : (isActive ? Colors.white : Colors.blue),
      ),
    );
  }

  Widget _buildMiniMap(double boxSize) {
    // 1. Setup the dimensions
    double miniSize = 120.0; // Fixed size for the mini-map square
    double scale = _transformationController.value.getMaxScaleOnAxis();

    // 2. Get the current pan/zoom values
    double tx = _transformationController.value.getTranslation().x;
    double ty = _transformationController.value.getTranslation().y;

    // 3. Calculate viewport indicator (the blue box)
    // We calculate how much of the "total zoomed area" is visible
    double viewW = miniSize / scale;
    double viewH = miniSize / scale;

    // Map the top-left corner from the big canvas to the mini-map
    double viewX = (-tx / (boxSize * scale)) * miniSize;
    double viewY = (-ty / (boxSize * scale)) * miniSize;

    return Container(
      width: miniSize,
      height: miniSize,
      clipBehavior:
          Clip.antiAlias, // Keeps the inner image inside the rounded corners
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Stack(
        children: [
          // LAYER 1: Ghostly Reference Image
          if (_selectedImageBytes != null)
            Opacity(
              opacity: 0.2,
              child: Image.memory(
                _selectedImageBytes!,
                width: miniSize,
                height: miniSize,
                fit: BoxFit.fill,
              ),
            ),

          // LAYER 2: The Viewport Indicator
          Positioned(
            left: viewX,
            top: viewY,
            child: Container(
              width: viewW,
              height: viewH,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent, width: 1.5),
                color: Colors.blueAccent.withOpacity(0.1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleGameInteraction(dynamic details, double boxSize) {
    if (!_isGameMode || _dots.isEmpty || _isGameOver) return;

    final RenderBox? box =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Offset localOffset = box.globalToLocal(details.globalPosition);

    // 1. Convert Screen pixels to 1024 Virtual Canvas
    double scale = 1024 / boxSize;
    Offset mouse1024 = Offset(localOffset.dx * scale, localOffset.dy * scale);

    setState(() {
      // 2. Check if we hit the NEXT target dot
      if (_nextTargetIndex <= _dots.length) {
        final targetDot = _dots[_nextTargetIndex];
        final double distToTarget =
            (Offset(targetDot.x, targetDot.y) - mouse1024).distance;

        if (distToTarget < 25.0) {
          // âœ… SUCCESS LOGIC
          _userPath.add(Offset(targetDot.x, targetDot.y));
          _nextTargetIndex++;

          if (_nextTargetIndex >= _dots.length) {
            _handleWinCondition();
            return; // ðŸ›‘ EXIT HERE so penalty logic doesn't run!
          }
        } else {
          // âŒ CHECK FOR PENALTY
          // We only take a life if the user is close to a dot that is NOT the target.
          // We use a slightly smaller radius (20.0) so they don't lose lives by accident.
          bool hitWrongDot = _dots.asMap().entries.any((entry) {
            int idx = entry.key;
            Dot dot = entry.value;
            if (idx == _nextTargetIndex || idx < _nextTargetIndex) return false;

            final double distToWrong =
                (Offset(dot.x, dot.y) - mouse1024).distance;
            return distToWrong < 20.0;
          });

          if (hitWrongDot) {
            setState(() {
              _lives--;
              // ðŸŽ¯ Trigger the animation!
              _heartShakeController.forward(from: 0.0);

              HapticFeedback.vibrate();

              if (_lives <= 0) {
                _isGameOver = true;
                _showGameOverDialog();
              }
            });
          }
        }
      }
    });
  }

  void _handleReset() async {
    final shouldReset =
        await _confirmReset(); // Use your existing confirmation dialog
    if (shouldReset) {
      _reset(); // Call your main reset function
    }
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Out of Lives!"),
        content: const Text("You ran out of lives! Want to try again?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetGame();
            },
            child: const Text("Restart"),
          ),
        ],
      ),
    );
  }

  void _showWinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Wonderful!", textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "You've connected all the dots and revealed the picture!",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_isHardMode)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.emoji_events, color: Colors.amber),
                    SizedBox(width: 8),
                    Text(
                      "HARD MODE MASTER",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _resetGame();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text("Play Again"),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _resetGame() {
    setState(() {
      _lives = 3;
      _nextTargetIndex = 0;
      _isGameOver = false;
      _userPath.clear();
      _wrongDotIndices.clear(); // ðŸŽ¯ Clear red dots on Retry
      // Re-hide lines for Medium/Hard on reset
      if (_isMediumMode || _isHardMode) {
        _showConnections = false;
      } else {
        _showConnections = true;
      }
    });
  }

  void _handleWinCondition() {
    setState(() {
      _isGameOver = true;
      _isGameMode =
          false; // ðŸŽ¯ Exit game logic so clicks don't trigger penalties
      _showOriginal = true;
    });

    // 1. Success Haptics
    HapticFeedback.heavyImpact();
    Future.delayed(
      const Duration(milliseconds: 300),
      () => HapticFeedback.heavyImpact(),
    );

    // 2. Play with the Ripple (Celebration Ripples)
    _lastErasedPos = const Offset(512, 512); // Center of 1024 canvas
    _rippleController.repeat(
      period: const Duration(milliseconds: 800),
      count: 2,
    );

    // 3. Show the Victory Overlay
    _showVictoryDialog();
  }

  void _showVictoryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Force them to celebrate!
      builder: (context) => Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, size: 72, color: Colors.amber),
                const SizedBox(height: 16),
                const Text(
                  "PUZZLE COMPLETE!",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "You completed the puzzle with $_lives lives left.",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (index) => Icon(
                      index < _lives ? Icons.favorite : Icons.favorite_border,
                      color: Colors.redAccent,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: StadiumBorder(),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _resetToHome(); // Back to project picker
                  },
                  child: const Text(
                    "BACK TO COLLECTION",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cosmic background painter — mirrors the auth page's visual identity.
class _HomeBackgroundPainter extends CustomPainter {
  static const _accents = [
    (0.10, 0.12, Color(0xFF00E5E5), 36.0),
    (0.08, 0.55, Color(0xFF9B59F5), 28.0),
    (0.88, 0.08, Color(0xFFFF4DAD), 30.0),
    (0.50, 0.30, Color(0xFFFFD060), 22.0),
    (0.25, 0.75, Color(0xFF4285F4), 26.0),
    (0.78, 0.65, Color(0xFFFF6B35), 22.0),
    (0.85, 0.40, Color(0xFF4FC3F7), 20.0),
    (0.40, 0.20, Color(0xFFCC4EFF), 18.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle dot grid
    final gridPaint = Paint()
      ..color = const Color(0xFF4285F4).withValues(alpha: 0.045);
    const gap = 48.0;
    for (double x = gap; x < size.width; x += gap) {
      for (double y = gap; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1.5, gridPaint);
      }
    }
    // Coloured accent glows
    for (final (xf, yf, color, r) in _accents) {
      final c = Offset(xf * size.width, yf * size.height);
      canvas.drawCircle(
        c, r,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
      canvas.drawCircle(c, r * 0.35, Paint()..color = color.withValues(alpha: 0.6));
    }
  }

  @override
  bool shouldRepaint(_HomeBackgroundPainter old) => false;
}
