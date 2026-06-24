import 'dart:async'; // For Timer
import 'dart:convert'; // For jsonEncode
import 'package:http/http.dart' as http; // For http.post
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:pdf/pdf.dart';
import 'services/file_saver.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'config.dart';
import 'services/supabase_service.dart';
import 'models/dot_model.dart';
import 'services/pdf_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:shimmer/shimmer.dart';
import 'dart:math'; // 🎯 Fixes 'sin'
import '../models/project_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/scheduler.dart';
import 'package:confetti/confetti.dart';
import 'services/analytics_service.dart';
import 'services/purchase_service.dart';
import 'paywall_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class ProjectState {
  final List<Dot> dots;
  final List<Offset> erasedPoints;

  ProjectState({required this.dots, required this.erasedPoints});
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final SupabaseService _service = SupabaseService();
  final ScreenshotController _screenshotController = ScreenshotController();

  // Game / UI state (was incorrectly declared as file-scope globals)
  String _mainStatus = '';
  String _subStatus = '';
  bool _isDragging = false;
  int _nextTargetIndex = 0;
  List<Offset> _userPath = [];
  bool _isGameMode = false;
  bool _isHardMode = false;
  bool _isMediumMode = false;

  bool _showConnections = false;
  bool _isEraserMode = false;
  bool _isRevealMode = false;
  bool _hasUnsavedChanges = false; // To show the save button only when needed
  bool _isEditingName = false;
  bool _isSidebarOpen = true; // Default to open for desktop
  final FocusNode _mainFocusNode = FocusNode();
  bool _isPanMode = false;
  bool _startNewPath = false;
  String? _currentImageUrl; // 👈 Add this line
  String?
  _currentMenuPath; // null = Main Menu, 'editor' = Editor, 'game' = Game
  Timer? _wrongDotTimer; // Resets the color after a moment
  Set<int> _wrongDotIndices = {};
  int _activePointers = 0;

  Future<List<Map<String, dynamic>>>? _galleryFuture;
  late ConfettiController _confettiController;
  List<ProjectState> _undoStack = [];
  List<ProjectState> _redoStack = [];
  late TransformationController _transformationController;
  late TextEditingController _nameController;
  Timer? _autoSaveTimer;
  double _currentScale = 1.0;
  List<Offset> _erasedPoints = []; // Stores the center of every "pop" you made

  Timer? _loadingTimer;
  final List<String> _processingTips = [
    "📤 Uploading image to AI engine...",
    "🧠 AI: Identifying subject and removing background...",
    "✍️ AI: Tracing high-contrast edges...",
    "💡 Tip: Use portraits with clear lighting for best results!",
    "📏 Calculating optimal dot spacing...",
    "✨ Finalizing your printable puzzle...",
  ];

  String? _currentProjectId;
  Timer? _debounce;
  Timer? _hintTimer;
  int _currentSparsity = 20; // Your existing sparsity variable

  int _tipIndex = 0;
  List<Dot> _dots = [];
  bool _isLoading = false;
  Uint8List? _selectedImageBytes;
  String? _currentFileName;
  double? _imageWidth;
  double? _imageHeight;
  bool _isAutoMode = false;

  Project? _currentProject;
  List<Project> _savedProjects = [];

  Offset? _debugMousePos;
  final ValueNotifier<Offset?> _mousePosNotifier = ValueNotifier(null);
  final GlobalKey _canvasKey = GlobalKey();
  bool _showHint = false;

  int _lives = 3;
  static const int _maxLives = 3;
  bool _isGameOver = false;

  // Settings
  double _sparsity = 20.0;
  bool _removeBg = false;
  bool _showOriginal = true;
  double _bgOpacity = 0.3; // Default to 30% visibility

  late AnimationController _rippleController;
  Offset? _lastErasedPos;
  late AnimationController _heartShakeController;

  bool _isInPuzzle = false;
  bool _isSyncing = false;
  double boxSize = 600; // Adjust based on your layout needs
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    // 1. Load your Projects immediately
    _refreshProjects();
    _galleryFuture = _service.getAllProjects();
    _loadEntitlement();

    // 2. Animation Controllers
    _heartShakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // 3. UI & Text Controllers
    _transformationController = TransformationController();
    _nameController = TextEditingController();
    _showOriginal = false;

    // 4. Listeners
    _transformationController.addListener(() {
      if (mounted) {
        setState(() {
          _currentScale = _transformationController.value.getMaxScaleOnAxis();
        });
      }
    });
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
    _confettiController.dispose();
    super.dispose();
  }

  void _showAccountDialog() {
    final email = _service.currentUserEmail ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: const TextStyle(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 24),
            TextButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('Delete my account and all data',
                  style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(ctx).pop();
                _confirmDeleteAccount();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadEntitlement() async {
    final premium = await PurchaseService.isPremium();
    if (mounted) setState(() => _isPremium = premium);
  }

  // 2. THE BUILD METHOD
  @override
  Widget build(BuildContext context) {
    if (!_service.isAuthenticated) return _buildLoginPage();
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
            _undo(); // ↩️ Ctrl + Z
          }
          if (isControlDown && event.logicalKey == LogicalKeyboardKey.keyY) {
            _redo(); // ↪️ Ctrl + Y
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

              // 3. GLOBAL LOADING OVERLAY
              if (_isLoading)
                Positioned.fill(
                  child: Container(
                    // 🌴 DINO UPGRADE: Translucent Jungle Green instead of plain black dimming
                    color: const Color(0xFF111E18).withOpacity(0.85),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            // 🦖 DINO UPGRADE: Neon Tyranno Green spinner!
                            color: Color(0xFF4EFE98),
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
                              // 👈 Removed 'const' from here!
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

    // 🌍 Dino-Upgraded Rank Tiers & Dynamic Color Assignments
    String curatorRank = "BABY RAPTOR EXPLORER 🔍";
    Color rankColor = const Color(0xFFF1F7F4); // Default: Crisp Ivory White

    if (percentage >= 90) {
      curatorRank = "APEX APATOSAURUS DIRECTOR 🏛️";
      rankColor = const Color(
        0xFF4EFE98,
      ); // 🏆 Neon Tyranno Green for the highest honor!
    } else if (percentage >= 70) {
      curatorRank = "SENIOR DINO CURATOR 📜";
      rankColor = const Color(0xFFF7D060); // ⭐ Bright Amber Gold
    } else if (percentage >= 45) {
      curatorRank = "CHIEF PALEONTOLOGIST 🏺";
      rankColor = const Color(0xFFF7D060); // ⭐ Bright Amber Gold
    } else if (percentage >= 25) {
      curatorRank = "FOSSIL HUNTER ⛏️";
      rankColor = const Color(0xFF253B30); // 🌲 Tough Moss Green
    } else if (percentage >= 10) {
      curatorRank = "EGG INCUBATION ASSISTANT 🧪";
      rankColor = const Color(0xFF253B30); // 🌲 Tough Moss Green
    } else {
      // If they somehow get less than 10% or fail early
      curatorRank = "VOLCANIC REFUGEE 🌋";
      rankColor = const Color(0xFFFA5A33); // 🔥 Magma Orange/Red warning line
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            // 🦕 Top Left: Subtle translucent Moss Green
            const Color(0xFF253B30).withOpacity(0.40),

            // 🌴 Bottom Right: Very soft, deeper dark jungle tint
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
                          rankColor, // ⚡ Automatically morphs colors based on the tier achieved!
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

          // 🌊 PROGRESS BAR
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

  Widget _buildGameStats() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 📉 Progress Text
          Text(
            "Progress: $_nextTargetIndex / ${_dots.length}",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          // ❤️ Lives Display
          Row(
            children: List.generate(3, (index) {
              return Icon(
                index < _lives ? Icons.favorite : Icons.favorite_border,
                color: Colors.redAccent,
                size: 20,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildGameView(double boxSize) {
    return GestureDetector(
      // 🎯 FIX: Pass both the details AND the boxSize
      onTapDown: (details) => _handleCanvasTap(details, boxSize),
      child: Stack(children: [_buildImageStack(boxSize)]),
    );
  }

  // 🎨 Tool Icon for the Floating Pill
  Widget _buildToolIcon(IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
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
  }

  // 🎮 Mode Selection Button (Studio vs Arcade)
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

  // 🖼️ Project Card for the Lobby
  Widget _buildProjectCard(Project project, {bool isGame = false}) {
    final String baseUrl = '${AppConfig.storageBaseUrl}/';

    // 2. Build the full path
    // If the DB already has 'https', use it. Otherwise, add the baseUrl.
    final String fullImagePath = project.imagePath!.startsWith('http')
        ? project.imagePath!
        : "$baseUrl${project.imagePath!}";
    // Use Uri.encodeFull to turn spaces into '%20' automatically
    final String safeUrl = Uri.encodeFull(fullImagePath);

    // 🕵️‍♂️ CHECK FOR COMPLETION: Has he cleared it on any difficulty yet?
    final bool isCleared =
        project.easyCleared || project.mediumCleared || project.hardCleared;

    return InkWell(
      onTap: () {
        // 1. CLEAR OLD DATA FIRST 🧹
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
                            // 🕵️‍♂️ MYSTERY SILHOUETTE: Not beaten yet. Darken it out completely!
                            : ColorFiltered(
                                colorFilter: const ColorFilter.mode(
                                  Color(
                                    0xFF14221B,
                                  ), // 🦕 Solid obsidian/dark jungle green matching your lobby background
                                  BlendMode
                                      .srcOver, // 🎯 FIXED: srcOver completely covers everything (even white backgrounds)
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

                    // Dot preview overlay — editor mode only
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

                    // 🌟 THE STAR BADGE (Top Left)
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

                    // ▶️ Play Overlay (Hides standard play arrow behind a mystery question mark if uncompleted)
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
                  // 🏷️ PROJECT TITLE
                  Text(
                    project.name ?? "Untitled Fossil",
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
                      // 🔢 Dot Count
                      Text(
                        "${project.dotCount} Dots",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),

                      // 🗑️ Delete Icon
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

                      // 🧩 Difficulty Badge
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
  Widget _buildSyncingPlaceholder() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sync, color: Colors.blue.shade700, size: 24),
          const SizedBox(height: 4),
          const Text(
            "Syncing...",
            style: TextStyle(fontSize: 8, color: Colors.grey),
          ),
        ],
      ),
    );
  }

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

  Widget _buildLoginPage() {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => /* Trigger your login logic */ {},
          child: const Text("Please Login"),
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
                              ? "Untitled Dinosaur"
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
    // 🏠 STEP 1: THE MAIN MENU (Two big cards)
    if (_currentMenuPath == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        body: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 32.0,
                ),
                child: Wrap(
                  spacing: 24.0,
                  runSpacing: 24.0,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildPathCard(
                      title: "Editor Mode",
                      icon: Icons.edit_note,
                      color: const Color(0xFF4EFE98),
                      onTap: () {
                        setState(() => _currentMenuPath = 'editor');
                        _refreshProjects();
                      },
                    ),
                    _buildPathCard(
                      title: "Game Mode",
                      icon: Icons.videogame_asset,
                      color: const Color(0xFFF7D060),
                      onTap: () {
                        setState(() => _currentMenuPath = 'game');
                        _refreshProjects();
                      },
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Row(
                children: [
                  Tooltip(
                    message: 'Account',
                    child: IconButton(
                      icon: const Icon(Icons.manage_accounts_outlined),
                      color: Colors.grey.shade500,
                      onPressed: () => _showAccountDialog(),
                    ),
                  ),
                  Tooltip(
                    message: 'Sign out',
                    child: IconButton(
                      icon: const Icon(Icons.logout_rounded),
                      color: Colors.grey.shade500,
                      onPressed: () async {
                        await _service.signOut();
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 📂 STEP 2: THE SUB-MENUS (Grid of Puzzles)
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
      // 🎯 THE CONTROLLER: Use a Column to stack the Header above the Grid/Empty State
      body: Column(
        children: [
          // 🏛️ Header injects ONLY in Game Mode
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
                // 🦖 DINO UPGRADE: High contrast dark text on the white card
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

  Widget _buildGameStartCard(Project project) {
    // 🎯 Add this wrapper!
    return StatefulBuilder(
      builder: (context, setCardState) {
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(20),
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
                  "Dino-Connect",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Connect ${_dots.length} dots to reveal the creature!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),

                // 🔴 LIVES PREVIEW
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

                // ⚡ DIFFICULTY SELECTOR
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      // 🎯 EASY TAB
                      _buildDifficultyTab(
                        "Easy",
                        (!_isHardMode && !_isMediumMode),
                        true, // Always unlocked
                        () {
                          setState(() {
                            _isHardMode = false;
                            _isMediumMode = false;
                          });
                          setCardState(() {});
                        },
                      ),

                      // 🎯 MEDIUM TAB
                      _buildDifficultyTab(
                        "Medium",
                        _isMediumMode,
                        project.easyCleared, // 🔑 Unlocks if Easy is done
                        () {
                          setState(() {
                            _isHardMode = false;
                            _isMediumMode = true;
                          });
                          setCardState(() {});
                        },
                      ),

                      // 🎯 HARD TAB
                      _buildDifficultyTab(
                        "Hard",
                        _isHardMode,
                        project.mediumCleared, // 🔑 Unlocks if Medium is done
                        () {
                          setState(() {
                            _isHardMode = true;
                            _isMediumMode = false;
                          });
                          setCardState(() {});
                        },
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
                    Navigator.pop(context); // 🎯 Close the sheet FIRST
                    _startGame(project); // 🚀 Then launch the game
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildDifficultyTab(
    String label,
    bool isSelected,
    bool isUnlocked, // 🔒 New Parameter
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        // Only allow the tap if the difficulty is actually unlocked
        onTap: isUnlocked ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4EFE98)
                : (isUnlocked
                      ? Colors.transparent
                      : Colors.grey.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
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
                  color: isSelected
                      ? Colors.white
                      : (isUnlocked ? Colors.black54 : Colors.black26),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveSnapshot() {
    // Deep copy the current dots list so changes don't overwrite history
    final currentDotsCopy = _dots.map((d) => Dot.fromMap(d.toMap())).toList();

    _undoStack.add(
      ProjectState(
        dots: List<Dot>.from(_dots),
        erasedPoints: List<Offset>.from(_erasedPoints),
      ),
    );
    _redoStack.clear(); // New actions wipe out forward redo history

    // Optional: Cap the history size at 50 actions to save memory
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
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

  void _setDifficulty(String level) {
    setState(() {
      if (level == 'easy') {
        _isHardMode = false;
        _isMediumMode = false;
      } else if (level == 'medium') {
        _isHardMode = false;
        _isMediumMode = true;
      } else if (level == 'hard') {
        _isHardMode = true;
        _isMediumMode = false;
      }
      // Optional: Reset game or clear wrong dots when changing difficulty
      _wrongDotIndices.clear();
    });
  }

  void _clearEditorState() {
    setState(() {
      _dots = [];
      _erasedPoints = [];
      _currentProjectId = null;
      _currentProject = null;
      _selectedImageBytes = null;
      _currentImageUrl = null;
      _nameController.text = "New Fossil";
    });
  }

  void _resequenceDots() {
    setState(() {
      for (int i = 0; i < _dots.length; i++) {
        // Update both the sequence order and the visual label
        _dots[i] = _dots[i].copyWith(
          sequenceOrder: i + 1,
          label: (i + 1).toString(),
        );
      }
    });
  }

  void _autoGenerateDots() {
    if (!_isAutoMode || _selectedImageBytes == null) return;

    // 🦖 Future Logic:
    // This is where you'll use an algorithm to detect edges
    // and place dots based on the _sparsity value.
    print("Auto-generating dots with sparsity: $_sparsity");

    setState(() {
      // For now, let's just make it clear it's being called
      _hasUnsavedChanges = true;
    });
  }

  void _showGameSelectionSheet(Project project) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildGameStartCard(project),
    );
  }

  void _resetToHome() {
    setState(() {
      _isInPuzzle = false; // This takes you back to the project picker
      _isGameMode = false; // Turn off game logic
      _isGameOver = false; // Reset game over state
      _nextTargetIndex = 0; // Reset progress
      _userPath = []; // Clear the lines
      _lives = 3; // Refill hearts
      _showOriginal = true; // Reset visibility
      _wrongDotIndices.clear(); // Clear red dots when leaving
    });
  }

  Future<List<Project>> _fetchProjects() async {
    // Get the raw maps from your service
    final List<Map<String, dynamic>> data = await _service.getAllProjects();

    // 🎯 Map them into Project objects using your Project.fromMap
    return data.map((map) => Project.fromMap(map)).toList();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final bytes = await image.readAsBytes();

      // 🎨 Get dimensions so the canvas scales correctly
      final decodedImage = await decodeImageFromList(bytes);

      setState(() {
        _selectedImageBytes = bytes;
        _imageWidth = decodedImage.width.toDouble();
        _imageHeight = decodedImage.height.toDouble();
        _currentFileName = image.name;

        // Reset everything for the new masterpiece
        _dots = [];
        _erasedPoints = [];
        _currentProjectId = null; // Important: This is a NEW project
        _nameController.text = image.name.split('.').first; // Auto-fill name
        _hasUnsavedChanges = true;
      });
    }
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

    // 🎯 IMPORTANT: Use the public URL from the project state,
    // not a local _currentFileName variable which might be null.
    final Map<String, dynamic> projectData = {
      'name': _nameController.text.isEmpty
          ? "New Fossil"
          : _nameController.text,
      'dots': jsonDots,
      'erased_points': jsonErasedPoints,
      'sparsity': _sparsity.toInt(),
      'dot_count': _dots.length,
      // 'image_path': _currentFileName, // 🛑 REMOVE THIS - it's likely null
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

        print("✅ Project updated successfully");
      } else {
        // 🛑 WE REMOVED THE INSERT LOGIC HERE.
        // Projects are now ONLY created via _pickAndUploadImage.
        print("⚠️ Save ignored: No Project ID. Use Upload first.");
        return;
      }

      setState(() {
        _hasUnsavedChanges = false;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Dino Fossil synchronized! 🦖☁️",
          ), // The 🦖 is likely what triggered the font warning
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("❌ Save Error: $e");
      setState(() => _isLoading = false);
    }
  }

  void _startGame(Project project) {
    if (project.dots.isEmpty) {
      print("❌ Error: No dots found for this project!");
      return;
    }

    setState(() {
      _currentProject = project;

      _dots = project.dots
          .map((d) => Dot.fromMap(Map<String, dynamic>.from(d)))
          .toList();

      _isGameMode = true;
      _isInPuzzle = true;
      AnalyticsService.puzzlePlayed(project.id);

      // 🎯 ADD THESE TO RESET THE CURSOR
      _transformationController.value = Matrix4.identity();
      _isPanMode = false;

      _nextTargetIndex = 0;
      _lives = 3;
      _isGameOver = false;
      _wrongDotIndices.clear();
      _userPath = [];
      _showOriginal = false;

      if (_isMediumMode || _isHardMode) {
        _showConnections = false;
      } else {
        _showConnections = true;
      }
    });
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
        // 🎯 StatefulBuilder allows the sliders to move smoothly inside the popup
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

                  // 🖼️ BACKGROUND OPACITY
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

                  // 📏 DOT SPARSITY
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
                      // 🎯 This only triggers when the user lets go of the slider
                      _uploadAndProcess();
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
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

  void _refreshGallery() {
    setState(() {
      _galleryFuture = _service.getAllProjects();
    });
  }

  Future<void> _refreshProjects() async {
    setState(() => _isLoading = true);
    try {
      // Fetch directly from the service
      final List<Map<String, dynamic>> data = await _service.getAllProjects();

      setState(() {
        // Map the maps to your Project objects
        _savedProjects = data.map((map) => Project.fromMap(map)).toList();
        _isLoading = false;
      });
      print("✅ Loaded ${_savedProjects.length} projects.");
    } catch (e) {
      setState(() => _isLoading = false);
      print("❌ Error refreshing gallery: $e");
    }
  }

  // Map _saveCurrentProject to our existing debounced logic
  Future<void> _saveCurrentProject() async {
    // 🛑 STRICT GATEKEEPER
    // If _currentProjectId is null OR if we are currently in the middle of an upload,
    // do NOT touch the database.
    if (_currentProjectId == null || _isSyncing) {
      print("⏳ Save blocked: Project not initialized or upload in progress.");
      return;
    }

    try {
      await _service.saveDots(_currentProjectId!, _dots);
      print("☁️ Dots successfully saved for ID: $_currentProjectId");
    } catch (e) {
      print("❌ Error during save: $e");
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
          null; // 🎯 CRITICAL: Clears the old image from memory

      // 2. Reset UI States
      _isInPuzzle = true;
      _isGameMode = false;
      _showOriginal = true;
      _isEraserMode = false;

      // 3. Reset Names & Controllers
      _nameController.text = "Untitled Fossil";
      _currentFileName = "Untitled Fossil";

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
          content: Text("Not enough hearts for a hint! 💔"),
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
                subtitle: const Text("No numbers, no help. 🧠"),
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
        // 🌴 DINO UPGRADE: Translucent Moss Green instead of white
        color: const Color(0xFF253B30).withOpacity(0.95),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFF4EFE98).withOpacity(0.2),
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
          // ✏️ Tool: Draw
          _buildToolIcon(
            Icons.edit,
            !_isEraserMode && !_isPanMode && !_isRevealMode,
            () => setState(() {
              _isEraserMode = false;
              _isPanMode = false;
              _isRevealMode = false;
              _mainFocusNode.requestFocus();
            }),
          ),
          const SizedBox(width: 8),

          // 🧽 Tool: Eraser
          _buildToolIcon(
            Icons.auto_fix_high,
            _isEraserMode,
            () => setState(() {
              _isEraserMode = true;
              _isPanMode = false;
              _isRevealMode = false;
            }),
          ),

          // 🔢 Delete by number — only visible while eraser mode is active
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

          // 👁 Tool: Reveal Brush — paint background reveals without touching dots
          _buildToolIcon(
            Icons.visibility_outlined,
            _isRevealMode,
            () => setState(() {
              _isRevealMode = true;
              _isEraserMode = false;
              _isPanMode = false;
            }),
          ),
          const SizedBox(width: 8),

          // ✋ Tool: Pan Mode
          _buildToolIcon(
            Icons.front_hand,
            _isPanMode,
            () => setState(() {
              _isPanMode = true;
              _isEraserMode = false;
              _isRevealMode = false;
            }),
          ),

          VerticalDivider(
            width: 24,
            indent: 8,
            endIndent: 8,
            color: const Color(0xFFF1F7F4).withOpacity(0.2),
          ),

          // ⛓️ Tool: Pen Lift (Path Toggle)
          Tooltip(
            message: _startNewPath ? "Pen Lifted" : "Pen Down",
            child: IconButton(
              icon: Icon(_startNewPath ? Icons.link_off : Icons.link),
              // 🦖 DINO UPGRADE: Amber Gold for lifted, Soft Ivory for bound paths
              color: _startNewPath
                  ? const Color(0xFFF7D060)
                  : const Color(0xFFF1F7F4),
              onPressed: () => setState(() => _startNewPath = !_startNewPath),
            ),
          ),

          // ↩️ UNDO BUTTON
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: "Undo (Ctrl+Z)",
            // 🎨 Active: Neon Green Accent | Disabled: Faint Moss
            color: _undoStack.isEmpty
                ? const Color(0xFF253B30)
                : const Color(0xFF4EFE98),
            onPressed: _undoStack.isEmpty ? null : _undo,
          ),

          // ↪️ REDO BUTTON
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

          // ⚙️ 🎛️ Action: Studio Parameters (Updated to settings gear icon!)
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

          // ☁️ Action: Save to Supabase
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
            // 🎯 Optional: Add a subtle shadow to make hearts visible on any background
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
    return Screenshot(
      controller: _screenshotController,
      child: Container(
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
                // 🎯 FIX: Check BOTH the toggle state AND the hardware spacebar
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

                  // 🎯 Only auto-reset _isPanMode if the Spacebar was the one that turned it on.
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
                    // 🎯 Safety check: If the spacebar isn't actually down anymore, force pan mode OFF.
                    final isSpaceStillDown = HardwareKeyboard.instance
                        .isLogicalKeyPressed(LogicalKeyboardKey.space);
                    if (!isSpaceStillDown && _isPanMode) {
                      setState(() => _isPanMode = false);
                    }
                  },
                  transformationController: _transformationController,
                  // 🖐️ Only allow panning when the mode is active (via Spacebar or Toggle)
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
                            (_showOriginal || _isGameMode))
                          Positioned.fill(
                            child: Opacity(
                              opacity: _isGameMode ? 1.0 : _bgOpacity,
                              child: Image.memory(
                                _selectedImageBytes!,
                                // BoxFit.fill matches the server's 1024×1024
                                // square processing space so dots align with
                                // the reference image for any aspect ratio.
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),

                        // 2. Layer B: Masking (Eraser/Game Mode)
                        if (_isGameMode || _isEraserMode)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: MaskPainter(
                                erasedPoints: _erasedPoints,
                                isGameMode: _isGameMode,
                                currentZoom: _currentScale,
                              ),
                            ),
                          ),

                        // 3. Layer C: Logic & Painting
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring:
                                _isPanMode, // 🚦 When true, clicks "fall through" to the InteractiveViewer
                            child: Listener(
                              onPointerDown: (event) {
                                _activePointers++;
                                // Process game taps here, in the Listener, rather
                                // than in GestureDetector.onTapDown.
                                // Listener.onPointerDown fires synchronously and
                                // immediately — it never enters the gesture arena,
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

                                // 🚫 REMOVED: onPanStart, onPanUpdate, and onPanCancel!
                                // Removing these lets InteractiveViewer instantly detect pinch-to-zoom and panning
                                // without our logic engine accidentally intercepting the gesture.
                                onTapUp: (details) {
                                  // If more than one finger is present, they are zooming/panning. Abort!
                                  if (_activePointers > 1) return;

                                  // 📝 EDITOR MODE: Handles adding dots safely on mouse-up / single-tap release
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
                                  // just the painter + cursor ring — no full-tree rebuild.
                                  child: ValueListenableBuilder<Offset?>(
                                    valueListenable: _mousePosNotifier,
                                    builder: (context, mousePos, _) {
                                      return Stack(
                                        children: [
                                          // Positioned.fill ensures CustomPaint
                                          // inherits the full canvas size from the
                                          // Stack, not loose 0×0 constraints.
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
                                                ),
                                              );
                                            },
                                          ),  // closes AnimatedBuilder
                                        ),    // closes Positioned.fill
                                          // Cursor ring — only repaints on hover
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
    // 🛑 Stop any pending auto-saves before they fire
    _autoSaveTimer?.cancel();

    setState(() {
      _dots = []; // Clear current edited dots
      _undoStack = []; // Clear undo history
      _erasedPoints = []; // 🧹 Forget everything we erased!
      _isEraserMode = false;
      _sparsity = 20.0; // Reset to default sparsity
      _currentSparsity = 20;
      _hasUnsavedChanges = true;
    });

    // 🛡️ DINO SAFETY GUARD: Only re-request AI dots if we actually have an active image
    // on screen to process! If it's null, stop right here!
    if (_selectedImageBytes == null) {
      print("🦕 Clear Canvas Reset complete (No image to process).");
      return;
    }

    // Automatically trigger a fresh "Generate Dots" ONLY if an image exists
    _uploadAndProcess();
    print("🔄 Full Reset: Canvas and Eraser memory cleared.");
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

        // 🧹 NEW: Reset the canvas and data immediately
        _dots = [];
        _erasedPoints = [];
        _currentProject = null;
        _userPath = []; // Reset game path if any
        _nextTargetIndex = 1; // Reset game progress
      });

      try {
        // STEP 1: Upload Storage First
        print("🛰️ UPLOADING IMAGE...");
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
        print("🔗 URL GENERATED: $publicUrl");

        // STEP 2: Create the Database Row with the URL
        print("📝 CREATING DB ROW...");
        final response = await Supabase.instance.client
            .from('projects')
            .insert({
              'name': fileName.split('.').first,
              'image_path': publicUrl, // 🎯 Included from the start!
              'user_id': Supabase.instance.client.auth.currentUser?.id,
              'status': 'ready',
              'dots': [],
              'erased_points': [],
            })
            .select()
            .single();

        print("✅ DB ROW CREATED: ${response['id']}");

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
          _isInPuzzle = true; // 🏁 Go to editor
        });
      } catch (e) {
        print("‼️ UPLOAD FAIL: $e");
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

    // 🎯 FIX: Fetch the latest projects so the new one shows up in the gallery!
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

  Future<void> _saveToGallery() async {
    if (_dots.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // All dots live in 1024×1024 virtual coordinate space. Export at 2000×2000.
      const int exportSize = 2000;
      const double virtualSize = 1024.0;
      final double scale = exportSize / virtualSize;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final exportRect = Rect.fromLTWH(0, 0, exportSize.toDouble(), exportSize.toDouble());

      // 1. Background: white fill.
      canvas.drawRect(exportRect, Paint()..color = Colors.white);

      // 2. Connecting lines (respect isNewPath breaks, same as DotPainter).
      final linePaint = Paint()
        ..color = const Color(0xCC000000)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (int i = 1; i < _dots.length; i++) {
        if (_dots[i].isNewPath) continue;
        canvas.drawLine(
          Offset(_dots[i - 1].x * scale, _dots[i - 1].y * scale),
          Offset(_dots[i].x * scale, _dots[i].y * scale),
          linePaint,
        );
      }

      // 3. Dots with sequence numbers.
      for (int i = 0; i < _dots.length; i++) {
        final x = _dots[i].x * scale;
        final y = _dots[i].y * scale;

        canvas.drawCircle(Offset(x, y), 10, Paint()..color = Colors.white);
        canvas.drawCircle(
          Offset(x, y),
          10,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );

        final tp = TextPainter(
          text: TextSpan(
            text: '${_dots[i].sequenceOrder}',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
      }

      // 4. Encode and save.
      final picture = recorder.endRecording();
      final img = await picture.toImage(exportSize, exportSize);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();

      if (byteData == null) throw Exception('PNG encoding returned null bytes');

      await saveImageBytes(
        byteData.buffer.asUint8List(),
        '${_currentFileName ?? 'dot2dot_puzzle'}.png',
      );
    } catch (e) {
      debugPrint('❌ PNG Export Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
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

    // 🎯 FIX: Use dot.toJson() to preserve labels, order, and jumps!
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
      print("❌ Sync error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onAddDot(Offset pos) {
    setState(() {
      // 🎯 Save history snapshot
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
      print("🎯 TARGET HIT! Current Index: $_nextTargetIndex");
      setState(() {
        _nextTargetIndex++;
        _wrongDotIndices.clear();
        HapticFeedback.lightImpact();
        _rippleController.forward(from: 0.0);
      });

      if (_nextTargetIndex >= _dots.length) {
        _handleWin();
      }
      return; // 😊 Exits early on success!
    } else {
      // ❌ WRONG HIT logic
      bool hitAnyOtherDot = false;

      for (int i = 0; i < _dots.length; i++) {
        // 🎯 THE FIX: Skip the current target AND any dots he has already successfully connected!
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
    // 🛡️ SECURITY FIX: If we are in game mode, abort immediately!
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
        // Unambiguous — delete immediately, same as before.
        _deleteDotByLabel(nearby.first.label);
      } else {
        // Multiple overlapping dots — let the user choose which one.
        nearby.sort((a, b) => a.sequenceOrder.compareTo(b.sequenceOrder));
        _showEraserDisambiguationMenu(details.globalPosition, nearby);
      }
    } else if (_isRevealMode) {
      // Reveal mode — paint a background reveal circle at this position.
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
    } else {
      // Draw mode — add a new dot.
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

  // ─── Eraser helpers ──────────────────────────────────────────────────────

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
            hintText: '1 – ${_dots.length}',
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

  // ─────────────────────────────────────────────────────────────────────────

  // 🏆 1. THE WIN LOGIC
  void _handleWin() {
    print("🚀 Inside _handleWin function");

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

      // 4. 🔥 THE PERSISTENCE: Save this specific 'updated' object to Supabase
      _saveToDatabase(updated);

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
              "✨ WONDERFUL!",
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
              Center(
                child: TextButton(
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
              ),
            ],
          );
        },
      );
    });
  }

  // 💀 2. THE GAME OVER LOGIC
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
                ); // 👈 Use the saved project to restart
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

      print("✅ All progress (Stars, Index, and Eraser) saved to Supabase!");
    } catch (e) {
      print("❌ SUPABASE ERROR: $e");
    }
  }

  void _generateInitialDots(int count) {
    if (_imageWidth == null || _imageHeight == null) return;

    setState(() {
      setState(() {
        // 🎯 Save history snapshot before clearing out old layout
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

  Future<void> _generatePdf() async {
    if (_dots.isEmpty) return;
    final pdf = pw.Document();
    // ... (Keep your existing PDF logic here)
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  void _loadProject(Map<String, dynamic> projectData) {
    // If we're re-opening the project that is already loaded in this session,
    // the image bytes are still in memory — skip the network download entirely.
    final bool reuseImage =
        projectData['id'] != null &&
        projectData['id'] == _currentProjectId &&
        _selectedImageBytes != null;

    setState(() {
      _isLoading = !reuseImage;
      if (!reuseImage) _selectedImageBytes = null;
      _nextTargetIndex = 0; // 🎯 RESET
      _userPath = []; // 🎯 RESET
      _wrongDotIndices.clear(); // 🎯 RESET
      _isGameOver = false; // 🎯 RESET
      _currentProjectId = projectData['id'];

      final String? savedUrl = projectData['image_path'];
      _currentImageUrl = (savedUrl != null && savedUrl.isNotEmpty) ? savedUrl : null;

      _nameController.text = projectData['name'] ?? "Untitled Fossil";

      // 2. Sparsity & Constants
      _currentSparsity = projectData['sparsity'] ?? 20;
      _sparsity = (_currentSparsity).toDouble();

      // 3. The Dots (Diagnostic "Final Boss" Version)
      final dynamic dotsData = projectData['dots'];
      print("🔍 DEBUG: dotsData type is ${dotsData.runtimeType}");
      print("🔍 DEBUG: dotsData content: $dotsData");

      List<dynamic> rawDots = [];

      if (dotsData is String) {
        try {
          rawDots = jsonDecode(dotsData) as List<dynamic>;
          print("🔍 DEBUG: Parsed from String. Length: ${rawDots.length}");
        } catch (e) {
          print("❌ DEBUG: JSON Decode error: $e");
        }
      } else if (dotsData is List) {
        rawDots = dotsData;
        print("🔍 DEBUG: Identified as List. Length: ${rawDots.length}");
      } else {
        print(
          "❌ DEBUG: dotsData is neither String nor List. It is ${dotsData.runtimeType}",
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

      print("✅ Successfully Parsed ${_dots.length} dots from DB");

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

    if (reuseImage) return; // bytes already in memory — nothing to download

    if (_currentImageUrl != null) {
      _downloadImage(_currentImageUrl!);
    } else {
      print("⚠️ No valid image URL for project: $_currentProjectId");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadImage(String url) async {
    if (mounted) setState(() => _isLoading = true);

    try {
      // Extract the storage object path from the public URL.
      // URL pattern: .../storage/v1/object/public/images/<storagePath>
      const String bucketMarker = '/images/';
      final int idx = url.indexOf(bucketMarker);
      final String storagePath = idx != -1
          ? Uri.decodeComponent(
              url.substring(idx + bucketMarker.length).split('?').first,
            )
          : Uri.decodeComponent(url.split('/').last.split('?').first);

      // Use the Supabase storage client instead of http.get.
      // On Flutter Web, http.get is blocked by CORS for XHR requests even on
      // public buckets. The Supabase SDK uses fetch() with the correct headers.
      final Uint8List bytes = await Supabase.instance.client.storage
          .from('images')
          .download(storagePath);

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
      debugPrint('❌ Image download error: $e');
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
      // 🎯 THIS runs only after the user stops for 0.5 seconds
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
    bool isDone = false;
    int attempts = 0;
    const int maxAttempts = 30; // Wait up to 60 seconds (30 * 2s)

    while (!isDone && attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 2));
      attempts++;

      try {
        // 1. Fetch the latest status from Supabase
        final data = await Supabase.instance.client
            .from('projects')
            .select()
            .eq('id', projectId)
            .single();

        if (data['status'] == 'completed') {
          isDone = true;
          // 2. AI is done! Refresh the UI with the new dots
          _loadProject(data);
          setState(() {
            _mainStatus = "Done!";
            _subStatus = "";
          });
        } else if (data['status'] == 'error') {
          setState(() => _mainStatus = "AI Error occurred");
          break;
        }
      } catch (e) {
        print("Polling error: $e");
      }
    }
  }

  Future<void> _uploadAndProcess({
    Uint8List? droppedBytes,
    String? droppedName,
  }) async {
    // 🪵 DEBUG LOG
    print("🪵 [_uploadAndProcess] TRIGGERED!");
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
          "🪵 [_uploadAndProcess] imageToUse is NULL. Launching FilePicker native window...",
        );

        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );

        if (result == null || result.files.single.bytes == null) {
          print(
            "🪵 [_uploadAndProcess] Native FilePicker window was CANCELLED by user.",
          );
          return;
        }

        print(
          "🪵 [_uploadAndProcess] Native FilePicker picked file successfully: ${result.files.single.name}",
        );
        imageToUse = result.files.single.bytes;
        nameToUse = result.files.single.name;
      }

      // 🎯 Only reset the ID if it's a TRULY new file from the computer
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
        nameToUse ?? "fossil_${DateTime.now().millisecondsSinceEpoch}",
        _sparsity.toInt(),
        projectId: _currentProjectId,
        removeBg: _removeBg,
      );

      setState(() {
        _currentProjectId = projectId;
      });

      // 4. Polling Loop
      int attempts = 0;
      const int maxAttempts = 120; // 2 Minutes
      await Future.delayed(const Duration(seconds: 2)); // Initial grace period

      while (attempts < maxAttempts) {
        await Future.delayed(const Duration(seconds: 1));

        // Fetch latest status
        final data = await _service.getProjectStatus(projectId);
        final String currentStatus = data['status'];

        print("📡 Polling Status: $currentStatus for ID: $projectId");

        if (currentStatus == 'processing') {
          setState(() {
            _mainStatus = _removeBg
                ? "AI BACKGROUND REMOVAL"
                : "AI EDGE DETECTION";
            _subStatus = "Analyzing fossil contours...";
            _isLoading = true;
          });
        }

        // --- CASE 1: SUCCESS ---
        if (currentStatus == 'completed') {
          _loadingTimer?.cancel();

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

          print("✅ Process complete: ${_dots.length} dots rendered.");
          return;
        }

        // --- CASE 3: ERROR ---
        if (currentStatus == 'error') {
          throw Exception("The AI worker encountered an error.");
        }

        attempts++;
      }

      if (attempts >= maxAttempts) {
        throw Exception("Processing timed out.");
      }
    } catch (e) {
      _loadingTimer?.cancel();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _mainStatus = "";
          _subStatus = "";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
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
  Future<void> _exportAsPDF() async {
    if (!_isPremium) {
      AnalyticsService.paywallShown('export');
      final subscribed = await showPaywall(context);
      if (subscribed) {
        AnalyticsService.subscriptionStarted();
        await _loadEntitlement();
      }
      return;
    }
    AnalyticsService.exportAttempted();
    try {
      setState(() => _isLoading = true);

      // 1. Capture the pixels
      final imageBytes = await _screenshotController.capture(
        // Increase delay slightly for the browser to sync layers
        delay: const Duration(milliseconds: 100),
        // Force a standard pixel ratio
        pixelRatio: 1.0,
      );

      if (imageBytes != null) {
        final pdf = pw.Document();
        final image = pw.MemoryImage(imageBytes);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (pw.Context context) {
              return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
            },
          ),
        );

        // 2. Share the bytes directly with the browser's print manager
        // This is more reliable on Web than trying to save a file directly
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: 'dot2dot_puzzle.pdf',
        );
        print("✅ PDF Print Dialog Opened");
      }
    } catch (e) {
      print("❌ PDF Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

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
          // 🍔 Sidebar Toggle
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

                // 🎯 THE HINT BUTTON
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
                  color: Color(0xFFF7D060), // 🌟 Amber Gold Title Label
                  letterSpacing: 2.0,
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF4EFE98), // 🦖 Neon Green progress loader
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // 🎯 MAIN ACTION: GENERATE
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
                ), // 🦖 Neon Tyranno Green Hero button
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
              ); // ⚡ Updates the modal UI immediately!
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
              ); // ⚡ Fixes Reference toggle!
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
              ); // ⚡ Fixes Connections toggle!
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

  // 🎨 Helper for Section Headers
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
        // 🦖 DINO UPGRADE: Active icons glow Neon Green, inactive are muted ivory
        color: value
            ? const Color(0xFF4EFE98)
            : const Color(0xFFF1F7F4).withOpacity(0.4),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFFF1F7F4),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: const Color(0xFFF1F7F4).withOpacity(0.6),
              ),
            )
          : null,
      value: value,
      // 🦖 DINO UPGRADE: Clean theme track and thumb switches
      activeColor: const Color(0xFF4EFE98),
      activeTrackColor: const Color(0xFF253B30),
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
    // 🛡️ Ensure dragging an image only works when you are actually in Studio Mode
    if (_isGameMode) return _buildGameView(boxSize);

    return DropTarget(
      onDragDone: (detail) async {
        final file = detail.files.first;
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
                // 🎨 DINO UPGRADE: Earthy dark background slate for drawing
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
              ), // 👈 Re-inserting your Mini Map here
            ),
          if (_isLoading)
            Container(
              color: Colors.black12, // Subtle dimming
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        SizedBox(height: 12),
                        Text(
                          "AI is recalculating dots...",
                          style: TextStyle(fontSize: 12),
                        ),
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
      "🪵 [_buildUploadPlaceholder] Widget is building onto the screen right now.",
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
            // 🎯 SAFE CLICK TRIGGER: Only triggers when deliberately clicked!
            onTap: () {
              print(
                "🎯 [INKWELL CLICK] User explicitly clicked the placeholder card container!",
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
          // 🦖 SAFE TRACKING: Clear variables to prepare a new manual puzzle workspace layout
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
                print("🚨 [GALLERY BUTTON] 'New Puzzle' clicked!");

                // 🛑 Cancel any lingering AI polling tasks, carousels, or auto-saves safely
                print("🚨 [GALLERY BUTTON] Canceling active timers...");
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
                  "🚨 [GALLERY BUTTON] State variables successfully wiped to null.",
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
              // ✨ UPGRADED LOADING STATE: The Shimmer
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

              // ✨ ADDED: Smooth transition when data arrives
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: ListView.separated(
                  key: ValueKey(projects.length), // Important for animation
                  itemCount: projects.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final pMap = projects[index]; // This is the raw Map

                    // 🎯 CONVERT to a Project object here for the stars/logic
                    final p = Project.fromMap(pMap);

                    return GalleryItem(
                      // Now you can pass either the map or the object depending on what GalleryItem expects
                      project: pMap,
                      // ✨ Use the object for stars (if your GalleryItem supports it)
                      // or just let GalleryItem's internal code use Project.fromMap(project)
                      isActive: _currentProjectId == p.id,
                      onTap: (projectData) => _loadProject(projectData),
                      isGameMenu: _currentMenuPath == 'game',
                      onDelete: (id, fileName) {
                        final String path =
                            p.imagePath ?? ""; // Using object property!
                        _confirmDelete(context, id, path, p.name);
                      },
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
          // ✅ SUCCESS LOGIC
          _userPath.add(Offset(targetDot.x, targetDot.y));
          _nextTargetIndex++;

          if (_nextTargetIndex >= _dots.length) {
            _handleWinCondition();
            return; // 🛑 EXIT HERE so penalty logic doesn't run!
          }
        } else {
          // ❌ CHECK FOR PENALTY
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
              // 🎯 Trigger the animation!
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
        title: const Text("🦖 Oh No!"),
        content: const Text("The Dino got away! Want to try again?"),
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
        title: const Text("🦖 Roar-some Job!", textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "You've connected all the dots and revealed the prehistoric secret!",
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
      _wrongDotIndices.clear(); // 🎯 Clear red dots on Retry
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
          false; // 🎯 Exit game logic so clicks don't trigger penalties
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
                const Text("🦖", style: TextStyle(fontSize: 60)),
                const SizedBox(height: 16),
                const Text(
                  "FOSSIL RESTORED!",
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

class GalleryItem extends StatefulWidget {
  final Map<String, dynamic> project;
  final bool isActive;
  final bool isGameMenu; // 🎯 Add this line to pass context
  final Function(Map<String, dynamic>) onTap;
  final Function(String, String) onDelete;

  const GalleryItem({
    Key? key,
    required this.project,
    required this.isActive,
    required this.isGameMenu, // 🎯 Require it here
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);

  @override
  _GalleryItemState createState() => _GalleryItemState();
}

class _GalleryItemState extends State<GalleryItem> {
  bool _isHovered = false; // 🎯 Local state for this specific item

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final bool isProcessing = p['status'] == 'processing';
    // 🎯 Create a temporary Project object to access star logic
    final projectObj = Project.fromMap(widget.project);
    final String fileName =
        p['name'] ??
        (p['image_path'] != null
            ? p['image_path'].split('/').last.split('_').last
            : "Untitled");

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: () => widget.onTap(p),
        hoverColor: Colors.blue.withOpacity(0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          // 🎯 Logic:
          // 1. If it's the open project -> Light Blue
          // 2. If I'm just hovering -> Very Light Grey or subtle Blue
          // 3. Otherwise -> Pure White
          color: widget.isActive
              ? Colors.blue.withOpacity(0.15)
              : (_isHovered ? Colors.grey[50] : Colors.white),

          child: Row(
            children: [
              // Active Indicator Line
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 4,
                height: 64,
                color: widget.isActive ? Colors.blueAccent : Colors.transparent,
              ),
              Expanded(
                child: ListTile(
                  mouseCursor: SystemMouseCursors.click,
                  contentPadding: const EdgeInsets.only(left: 12, right: 8),
                  leading: _buildIcon(p, widget.isActive),
                  title: Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: widget.isActive
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: widget.isActive
                          ? Colors.blueAccent
                          : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Row(
                    children: [
                      Text(
                        isProcessing ? "AI is working..." : "Ready",
                        style: const TextStyle(fontSize: 11),
                      ),
                      // 🎯 Condition: Only show mini stars if we are actively in the game pathway!
                      if (!isProcessing && widget.isGameMenu) ...[
                        const SizedBox(width: 8),
                        // 🌟 Star 1: Easy
                        _buildMiniStar(projectObj.easyCleared, Colors.orange),
                        // 🌟 Star 2: Medium
                        _buildMiniStar(
                          projectObj.mediumCleared,
                          Colors.purpleAccent,
                        ),
                        // 🌟 Star 3: Hard
                        _buildMiniStar(
                          projectObj.hardCleared,
                          Colors.redAccent,
                        ),
                      ],
                    ],
                  ),
                  // 🎯 THE MAGIC: Delete icon only shows when hovered
                  trailing: AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.redAccent.withOpacity(0.8),
                      onPressed: () => widget.onDelete(
                        p['id'],
                        p['image_path'] ?? "Untitled",
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStar(bool isCleared, Color activeColor) {
    return Icon(
      isCleared
          ? Icons.star
          : Icons.star_border, // Solid if won, outline if not
      size: 14,
      color: isCleared ? activeColor : Colors.grey.withOpacity(0.3),
    );
  }

  Widget _buildIcon(Map<String, dynamic> p, bool active) {
    if (p['status'] == 'processing') {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      Icons.insert_drive_file_outlined,
      size: 20,
      color: active ? Colors.blueAccent : Colors.grey,
    );
  }
}

class DotPainter extends CustomPainter {
  final List<Dot> dots;
  final bool isHardMode;
  final Offset? mousePos;
  final Offset? lastErasedPos;
  final double rippleValue;
  final bool showLines;
  final bool isEraserMode;
  final bool isGameMode;
  final int nextTargetIndex;
  final double displayWidth;
  final double displayHeight;
  final double originalWidth;
  final double originalHeight;
  final bool showHint;
  final double currentZoom;
  final bool isPanMode;
  final bool isPenUp;
  final int? wrongDotIndex;
  final Set<int> wrongDotIndices;
  final bool isMediumMode;

  DotPainter({
    required this.dots,
    required this.isHardMode,
    this.mousePos,
    this.lastErasedPos,
    this.rippleValue = 0.0,
    required this.showLines,
    required this.isEraserMode,
    this.isGameMode = false,
    this.nextTargetIndex = 0, // 🎯 Default to 0 for a clean start
    required this.displayWidth,
    required this.displayHeight,
    required this.originalWidth,
    required this.originalHeight,
    required this.currentZoom,
    required this.isPanMode,
    this.showHint = false,
    required this.isPenUp,
    this.wrongDotIndex,
    required this.wrongDotIndices,
    required this.isMediumMode,
  }) : super();

  @override
  void paint(Canvas canvas, Size size) {
    if (dots.isEmpty) return;

    double scale = size.width / 1024;

    // Layer 1: Ghost/Guide Lines (Editor Mode ONLY)
    if (showLines && !isGameMode) {
      _drawGuideLines(canvas, scale);
    }

    // Layer 2: Dots & Labels (Logic for Medium/Hard inside here)
    _drawDots(canvas, scale, wrongDotIndex);

    // Layer 3: Game Progress (The Green Path & Rubber Band)
    if (isGameMode) {
      _drawGamePath(canvas, scale);
    }

    // Layer 4: Eraser Ripple
    if (rippleValue > 0 && lastErasedPos != null) {
      _drawEraserRipple(canvas);
    }

    // Layer 5: Studio Ghost Line (Editor Only)
    if (!isGameMode &&
        mousePos != null &&
        dots.isNotEmpty &&
        !isEraserMode &&
        !isPanMode &&
        !isPenUp) {
      _drawStudioGhostLine(canvas, scale);
    }
  }

  @override
  bool shouldRepaint(DotPainter old) =>
      // Reference change (new list assigned) OR length change (dot added/removed
      // to the same list via mutation — list identity stays the same).
      old.dots != dots ||
      old.dots.length != dots.length ||
      old.nextTargetIndex != nextTargetIndex ||
      old.showHint != showHint ||
      old.wrongDotIndices != wrongDotIndices ||
      old.rippleValue != rippleValue ||
      old.mousePos != mousePos ||
      old.showLines != showLines ||
      old.isEraserMode != isEraserMode ||
      old.isGameMode != isGameMode ||
      old.isPanMode != isPanMode ||
      old.lastErasedPos != lastErasedPos;

  void _drawGuideLines(Canvas canvas, double scale) {
    if (dots.length < 2) return;
    final paint = Paint()
      ..color = Colors.black
          .withOpacity(0.1) // 🎯 Faded for editor preview
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(dots[0].x * scale, dots[0].y * scale);

    for (int i = 1; i < dots.length; i++) {
      if (dots[i].isNewPath) {
        path.moveTo(dots[i].x * scale, dots[i].y * scale);
      } else {
        path.lineTo(dots[i].x * scale, dots[i].y * scale);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawDots(Canvas canvas, double scale, int? wrongIndex) {
    // ---------------------------------------------------------
    // 1. DRAW IN-GAME GUIDE LINES (Easy Mode Only)
    // ---------------------------------------------------------
    // 🎯 Only draw lines if showLines is on AND we have actually started the game
    bool shouldActuallyDraw = showLines && isGameMode && nextTargetIndex > 0;

    if (shouldActuallyDraw) {
      final linePath = Path();
      bool isFirstPoint = true;

      for (int i = 0; i < dots.length; i++) {
        if (i >= nextTargetIndex) break;
        final pos = Offset(dots[i].x * scale, dots[i].y * scale);

        if (isFirstPoint || dots[i].isNewPath) {
          linePath.moveTo(pos.dx, pos.dy);
          isFirstPoint = false;
        } else {
          linePath.lineTo(pos.dx, pos.dy);
        }
      }

      final linePaint = Paint()
        ..color = Colors.green.withOpacity(0.4)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(linePath, linePaint);
    }

    // ---------------------------------------------------------
    // 2. DRAW DOTS & LABELS
    // ---------------------------------------------------------
    for (int i = 0; i < dots.length; i++) {
      final currentDot = dots[i];
      final center = Offset(currentDot.x * scale, currentDot.y * scale);

      final bool isCompleted = isGameMode && i < nextTargetIndex;
      final bool isTarget = isGameMode && i == nextTargetIndex;

      double currentRadius = isGameMode ? 6.0 : 3.0;

      // Calculate Hover Effects
      if (mousePos != null && !isPanMode) {
        final double distance = (center - mousePos!).distance;
        if (distance < 30.0) {
          bool showHoverEffects = !isHardMode && !isMediumMode;

          if (isEraserMode) {
            canvas.drawCircle(
              center,
              14.0,
              Paint()..color = Colors.red.withOpacity(0.15),
            );
            currentRadius += (30.0 - distance) * 0.15;
          } else if (showHoverEffects) {
            if (isTarget) {
              canvas.drawCircle(
                center,
                14.0,
                Paint()..color = Colors.green.withOpacity(0.2),
              );
            }
            currentRadius += (30.0 - distance) * 0.15;
          }
        }
      }

      // Determine Color
      Color dotColor;
      if (wrongDotIndices.contains(i)) {
        dotColor = Colors.redAccent;
      } else if (isTarget) {
        bool showOrange = (!isHardMode && !isMediumMode) || showHint;
        dotColor = showOrange
            ? Colors.orange
            : Colors.blueAccent.withOpacity(isHardMode ? 0.4 : 0.15);
      } else if (isCompleted) {
        dotColor = Colors.green.withOpacity(0.5);
      } else {
        dotColor = Colors.blueAccent.withOpacity(isHardMode ? 0.4 : 0.15);
      }

      // Draw Circle
      double finalRadius = (currentRadius * scale).clamp(4.0, 10.0);
      if (wrongDotIndices.contains(i)) finalRadius *= 1.5;
      canvas.drawCircle(center, finalRadius, Paint()..color = dotColor);

      // Draw Labels
      if (!isEraserMode) {
        bool showNumber = !isGameMode || !isHardMode || (showHint && isTarget);
        bool showTargetHighlight =
            isTarget && ((!isHardMode && !isMediumMode) || showHint);

        if (showNumber) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: currentDot.label,
              style: TextStyle(
                color: isCompleted ? Colors.black26 : Colors.black87,
                fontSize: (showTargetHighlight) ? 12 : 9,
                fontWeight: (showTargetHighlight)
                    ? FontWeight.w900
                    : FontWeight.normal,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          if (showTargetHighlight) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  center.dx + 2,
                  center.dy - 14,
                  textPainter.width + 4,
                  textPainter.height,
                ),
                const Radius.circular(4),
              ),
              Paint()..color = Colors.white.withOpacity(0.8),
            );
          }
          textPainter.paint(canvas, center + const Offset(5, -12));
        }
      }
    }
  }

  void _drawGamePath(Canvas canvas, double scale) {
    if (nextTargetIndex < 1) return; // 🎯 Safety: Nothing to draw yet

    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < nextTargetIndex - 1; i++) {
      if (dots[i + 1].isNewPath) continue; // 🎯 Handle jumps in the path
      final p1 = Offset(dots[i].x * scale, dots[i].y * scale);
      final p2 = Offset(dots[i + 1].x * scale, dots[i + 1].y * scale);
      canvas.drawLine(p1, p2, linePaint);
    }

    // Rubber band
    if (nextTargetIndex < dots.length && mousePos != null) {
      final lastDot = dots[nextTargetIndex - 1];
      final startPoint = Offset(lastDot.x * scale, lastDot.y * scale);
      canvas.drawLine(
        startPoint,
        mousePos!,
        Paint()
          ..color = Colors.green.withOpacity(0.4)
          ..strokeWidth = 2.0,
      );
    }
  }

  void _drawStudioGhostLine(Canvas canvas, double scale) {
    final lastDot = dots.last;
    Offset lastDotScreenPos = Offset(lastDot.x * scale, lastDot.y * scale);
    final double distance = (lastDotScreenPos - mousePos!).distance;
    if (distance < 300.0) {
      canvas.drawLine(
        lastDotScreenPos,
        mousePos!,
        Paint()
          ..color = Colors.blueAccent.withOpacity(0.5)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawEraserRipple(Canvas canvas) {
    final ripplePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(
        (1.0 - rippleValue).clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(lastErasedPos!, rippleValue * 35, ripplePaint);
  }
}

class MaskPainter extends CustomPainter {
  final List<Offset> erasedPoints;
  final bool isGameMode;
  final double currentZoom;

  MaskPainter({
    required this.erasedPoints,
    required this.isGameMode,
    this.currentZoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isGameMode && erasedPoints.isEmpty) return;

    final double scale = size.width / 1024;
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // Solid white curtain covers the whole canvas.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // Divide the base radius by the current zoom so the hole covers a smaller
    // area of the image when zoomed in, keeping its apparent on-screen size
    // roughly constant. This makes reveal painting more precise at high zoom.
    final double holeRadius = (20.0 / currentZoom) * scale;

    final holePaint = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;

    for (final point in erasedPoints) {
      canvas.drawCircle(
        Offset(point.dx * scale, point.dy * scale),
        holeRadius,
        holePaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(MaskPainter old) =>
      old.erasedPoints != erasedPoints ||
      old.erasedPoints.length != erasedPoints.length ||
      old.isGameMode != isGameMode ||
      old.currentZoom != currentZoom;
}

/// Lightweight painter used in project-card thumbnails (editor lobby).
/// Draws connecting lines and dots at thumbnail scale — no numbers, no game state.
class ThumbnailDotPainter extends CustomPainter {
  final List<Dot> dots;

  const ThumbnailDotPainter(this.dots);

  @override
  void paint(Canvas canvas, Size size) {
    if (dots.isEmpty) return;

    final double scale = size.width / 1024;

    // Connecting lines
    if (dots.length > 1) {
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(0.75)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(dots[0].x * scale, dots[0].y * scale);
      for (int i = 1; i < dots.length; i++) {
        final pos = Offset(dots[i].x * scale, dots[i].y * scale);
        if (dots[i].isNewPath) {
          path.moveTo(pos.dx, pos.dy);
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Dots — small filled circles with a contrasting border
    final fillPaint = Paint()..color = Colors.white;
    final borderPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    for (final dot in dots) {
      final pos = Offset(dot.x * scale, dot.y * scale);
      canvas.drawCircle(pos, 2.0, fillPaint);
      canvas.drawCircle(pos, 2.0, borderPaint);
    }
  }

  @override
  bool shouldRepaint(ThumbnailDotPainter old) =>
      old.dots.length != dots.length || old.dots != dots;
}
