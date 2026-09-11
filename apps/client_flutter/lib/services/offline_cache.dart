import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class OfflineCache {
  static const String _projectsKey = 'cached_projects';

  // ── Project list (SharedPreferences — works on web + mobile) ─────────────────

  static Future<void> saveProjects(List<Map<String, dynamic>> projects) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Strip image bytes before serialising — only keep JSON-safe fields.
      await prefs.setString(_projectsKey, jsonEncode(projects));
    } catch (e) {
      debugPrint('OfflineCache.saveProjects: $e');
    }
  }

  static Future<List<Map<String, dynamic>>?> loadProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_projectsKey);
      if (raw == null) return null;
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('OfflineCache.loadProjects: $e');
      return null;
    }
  }

  // ── Image bytes (file cache — mobile/desktop only, skipped on web) ────────────

  static Future<File?> _imageFile(String projectId) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/puzzle_img_$projectId.bin');
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveImage(String projectId, Uint8List bytes) async {
    final file = await _imageFile(projectId);
    if (file == null) return;
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('OfflineCache.saveImage: $e');
    }
  }

  static Future<Uint8List?> loadImage(String projectId) async {
    final file = await _imageFile(projectId);
    if (file == null) return null;
    try {
      if (await file.exists()) return await file.readAsBytes();
    } catch (e) {
      debugPrint('OfflineCache.loadImage: $e');
    }
    return null;
  }
}
