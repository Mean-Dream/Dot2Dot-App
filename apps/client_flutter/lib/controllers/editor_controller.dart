import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../models/dot_model.dart';
import '../models/undo_state.dart';

class EditorController extends ChangeNotifier {
  // ── Canvas content ────────────────────────────────────────────────────────────

  List<Dot> dots = [];
  List<Offset> erasedPoints = [];

  // ── Image ─────────────────────────────────────────────────────────────────────

  Uint8List? selectedImageBytes;
  double? imageWidth;
  double? imageHeight;
  String? currentImageUrl;

  // ── Tool state ────────────────────────────────────────────────────────────────

  bool isEraserMode = false;
  bool isRevealMode = false;
  bool isPanMode = false;
  bool isInsertMode = false;
  int? insertAnchorIndex; // list index of the dot to insert after
  bool startNewPath = false;
  bool hasUnsavedChanges = false;
  bool showOriginal = false;
  double bgOpacity = 0.3;
  bool removeBg = false;

  // ── AI generation settings ────────────────────────────────────────────────────

  double sparsity = 20.0;
  int currentSparsity = 20;

  // ── Undo / Redo ───────────────────────────────────────────────────────────────

  List<ProjectState> undoStack = [];
  List<ProjectState> redoStack = [];

  // ── History ───────────────────────────────────────────────────────────────────

  void saveSnapshot() {
    undoStack.add(ProjectState(
      dots: List<Dot>.from(dots),
      erasedPoints: List<Offset>.from(erasedPoints),
    ));
    redoStack.clear();
    if (undoStack.length > 50) undoStack.removeAt(0);
    // No notifyListeners — snapshot is silent; caller notifies after the edit.
  }

  /// Returns true if an undo was applied.
  bool undo() {
    if (undoStack.isEmpty) return false;
    redoStack.add(ProjectState(
      dots: List<Dot>.from(dots),
      erasedPoints: List<Offset>.from(erasedPoints),
    ));
    final prev = undoStack.removeLast();
    dots = prev.dots;
    erasedPoints = prev.erasedPoints;
    hasUnsavedChanges = true;
    notifyListeners();
    return true;
  }

  /// Returns true if a redo was applied.
  bool redo() {
    if (redoStack.isEmpty) return false;
    undoStack.add(ProjectState(
      dots: List<Dot>.from(dots),
      erasedPoints: List<Offset>.from(erasedPoints),
    ));
    final next = redoStack.removeLast();
    dots = next.dots;
    erasedPoints = next.erasedPoints;
    hasUnsavedChanges = true;
    notifyListeners();
    return true;
  }

  // ── Dot management ───────────────────────────────────────────────────────────

  void addDot(Dot dot) {
    dots.add(dot);
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void removeDotAt(int index) {
    dots.removeAt(index);
    resequence();
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void resequence() {
    for (int i = 0; i < dots.length; i++) {
      dots[i] = dots[i].copyWith(sequenceOrder: i + 1, label: (i + 1).toString());
    }
    // Caller must call notifyListeners if not already done.
  }

  // ── State resets ─────────────────────────────────────────────────────────────

  /// Clears all canvas content and image data for a fresh puzzle.
  void clearContent() {
    dots = [];
    erasedPoints = [];
    selectedImageBytes = null;
    currentImageUrl = null;
    undoStack = [];
    redoStack = [];
    hasUnsavedChanges = false;
    notifyListeners();
  }

  /// Resets all tool toggles to their defaults.
  void resetTools() {
    isEraserMode = false;
    isRevealMode = false;
    isPanMode = false;
    isInsertMode = false;
    insertAnchorIndex = null;
    startNewPath = false;
    notifyListeners();
  }

  /// Inserts a dot after [anchorIndex] and resequences.
  void insertDotAfter(int anchorIndex, Dot dot) {
    final int insertPos = anchorIndex + 1;
    dots.insert(insertPos, dot);
    resequence();
    insertAnchorIndex = insertPos; // auto-advance anchor
    hasUnsavedChanges = true;
    notifyListeners();
  }

  void setSparsity(double val) {
    sparsity = val;
    currentSparsity = val.toInt();
    notifyListeners();
  }

  void setBgOpacity(double val) {
    bgOpacity = val;
    notifyListeners();
  }
}
