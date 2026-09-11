import 'package:flutter/foundation.dart';
import '../models/dot_model.dart';
import '../models/project_model.dart';
import '../services/supabase_service.dart';
import '../services/offline_cache.dart';

class ProjectController extends ChangeNotifier {
  final SupabaseService _service;

  ProjectController(this._service);

  // ── State ─────────────────────────────────────────────────────────────────────

  String? currentProjectId;
  Project? currentProject;
  List<Project> savedProjects = [];
  String? currentFileName;
  bool isSyncing = false;
  bool isLoading = false;
  bool isPremium = false;
  bool isOffline = false;
  Future<List<Map<String, dynamic>>>? galleryFuture;

  // ── Project list ─────────────────────────────────────────────────────────────

  /// Full row including calibrated dot sets. Call before starting a game so
  /// difficulty-specific dot sets are available via [Project.dotsForLevel].
  Future<Project?> loadProjectDetail(String id) async {
    final map = await _service.getProjectDetail(id);
    if (map == null) return null;
    return Project.fromMap(map);
  }

  Future<void> refreshProjects() async {
    isLoading = true;
    notifyListeners();
    try {
      final data = await _service.getAllProjects();
      savedProjects = data.map((m) => Project.fromMap(m)).toList();
      isOffline = false;
      OfflineCache.saveProjects(data); // fire-and-forget; errors are swallowed inside
    } catch (e) {
      debugPrint('refreshProjects: network error — trying offline cache: $e');
      final cached = await OfflineCache.loadProjects();
      if (cached != null) {
        savedProjects = cached.map((m) => Project.fromMap(m)).toList();
      }
      isOffline = true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void refreshGallery() {
    galleryFuture = _fetchWithOfflineFallback();
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _fetchWithOfflineFallback() async {
    try {
      final data = await _service.getAllProjects();
      isOffline = false;
      notifyListeners();
      OfflineCache.saveProjects(data);
      return data;
    } catch (e) {
      debugPrint('refreshGallery: network error — using cache: $e');
      isOffline = true;
      notifyListeners();
      return await OfflineCache.loadProjects() ?? [];
    }
  }

  // ── Persistence ──────────────────────────────────────────────────────────────

  Future<void> saveProgress(
    String projectId, {
    required int lastIndex,
    required String difficulty,
  }) async {
    try {
      await _service.saveProgress(
        projectId,
        lastIndex: lastIndex,
        difficulty: difficulty,
      );
    } catch (e) {
      debugPrint('saveProgress error: $e');
    }
  }

  Future<void> saveCurrentProject(List<Dot> dots) async {
    if (currentProjectId == null || isSyncing) return;
    try {
      await _service.saveDots(currentProjectId!, dots);
    } catch (e) {
      debugPrint('saveCurrentProject error: $e');
    }
  }

  Future<void> saveToDatabase(Project project) async {
    try {
      await _service.saveProject(project);
      final idx = savedProjects.indexWhere((p) => p.id == project.id);
      if (idx != -1) savedProjects[idx] = project;
      currentProject = project;
      notifyListeners();
    } catch (e) {
      debugPrint('saveToDatabase error: $e');
    }
  }

  Future<void> autoSave(List<Dot> dots) async {
    if (currentProject == null) return;
    isSyncing = true;
    notifyListeners();
    await _service.saveDots(currentProject!.id, dots);
    await Future.delayed(const Duration(milliseconds: 500));
    isSyncing = false;
    notifyListeners();
  }

  void updateLocalProject(Project updated) {
    currentProject = updated;
    final idx = savedProjects.indexWhere((p) => p.id == updated.id);
    if (idx != -1) savedProjects[idx] = updated;
    notifyListeners();
  }

  void clear() {
    currentProjectId = null;
    currentProject = null;
    currentFileName = null;
    notifyListeners();
  }
}
