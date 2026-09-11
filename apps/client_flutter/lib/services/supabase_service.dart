import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config.dart';
import '../models/dot_model.dart';
import 'dart:ui';
import '../models/project_model.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  bool get isAuthenticated => _supabase.auth.currentUser != null;
  String? get currentUserEmail => _supabase.auth.currentUser?.email;

  String get _uploadUrl => '${AppConfig.apiBaseUrl}/upload';

  /// 1. Uploads image to Node API and returns the new Project ID
  Future<String> uploadImage(
    Uint8List bytes,
    String fileName,
    int sparsity, {
    String? projectId,
    bool removeBg = false,
    List<Offset> erasedPoints = const [], // 🎯 Add this parameter
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    // 1. Convert image to Base64
    String base64Image = base64Encode(bytes);

    // 🎯 Convert Offset list to a JSON-friendly list of lists [[x, y], [x, y]]
    final erasedJson = erasedPoints.map((p) => [p.dx, p.dy]).toList();

    try {
      final response = await http.post(
        Uri.parse(_uploadUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image': base64Image,
          'name': fileName,
          'sparsity': sparsity,
          'removeBg': removeBg,
          'userId': user.id,
          'projectId': projectId,
          'erased_points': erasedJson, // 🎯 SEND THESE TO NODE
        }),
      );

      print("📥 Node Response Code: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['projectId'];
      } else {
        throw Exception("Node API error: ${response.body}");
      }
    } catch (e) {
      print("❌ Flutter failed to reach Node: $e");
      throw e;
    }
  }

  /// 2. Fetches dots for a specific project
  Future<List<Dot>> getDots(String projectId) async {
    print("🔍 Fetching from DB for Project ID: $projectId");

    try {
      final response = await _supabase
          .from('projects')
          .select('dots, status')
          .eq('id', projectId)
          .single();

      print(
        "📊 DB Response - Status: ${response['status']}, Has Dots: ${response['dots'] != null}",
      );

      if (response['status'] == 'completed' && response['dots'] != null) {
        final List<dynamic> dotsData = response['dots'];
        print("🔢 Raw dots count from DB: ${dotsData.length}");

        return dotsData.asMap().entries.map<Dot>((entry) {
          final d = entry.value;
          // New format: {x, y, sequence_order, label, is_new_path}
          if (d is Map) return Dot.fromJson(Map<String, dynamic>.from(d));
          // Legacy format: [x, y]
          final int order = entry.key + 1;
          return Dot(
            x: (d[0] as num).toDouble(),
            y: (d[1] as num).toDouble(),
            sequenceOrder: order,
            label: order.toString(),
          );
        }).toList();
      }
    } catch (e) {
      print("❌ Error in getDots: $e");
    }

    return [];
  }

  /// 🎯 Save only the dots (used for auto-save during editing)
  Future<void> saveDots(String projectId, List<Dot> dots) async {
    // 🎯 FIX: Use d.toJson() to keep the labels and sequence!
    final dotsJson = dots.map((d) => d.toJson()).toList();

    await _supabase
        .from('projects')
        .update({'dots': dotsJson})
        .eq('id', projectId);
  }

  /// 🎯 Save the whole project state (used when exiting)
  /// This saves the dots AND where the player is in the game
  Future<void> saveProject(
    Project project, {
    int? nextIndex,
    int? totalDots,
  }) async {
    final updates = {
      'name': project.name,
      'difficulty': project.difficulty,
      if (nextIndex != null) 'last_index': nextIndex,
      if (totalDots != null) 'dot_count': totalDots,
    };

    await _supabase.from('projects').update(updates).eq('id', project.id);
  }

  Future<Map<String, dynamic>> getProjectStatus(String projectId) async {
    try {
      // 1. Fetch the data
      final response = await _supabase
          .from('projects')
          .select('status, dots')
          .eq('id', projectId)
          .maybeSingle();

      if (response == null) {
        print("🔍 Supabase: Project not found yet...");
        return {'status': 'pending'};
      }

      final String status = response['status'] ?? 'processing';
      final List? rawDots = response['dots'] as List?;

      print(
        "🔍 Supabase Status: $status | Dots found: ${rawDots?.length ?? 0}",
      );

      List<Dot> parsedDots = [];
      if (status == 'completed' && rawDots != null) {
        parsedDots = rawDots.asMap().entries.map((entry) {
          final d = entry.value;
          // New format: {x, y, sequence_order, label, is_new_path}
          if (d is Map) return Dot.fromJson(Map<String, dynamic>.from(d));
          // Legacy format: [x, y]
          return Dot.fromIndexedList(entry.key, d);
        }).toList();
      }

      return {'status': status, 'dots': parsedDots};
    } catch (e) {
      print("❌ Supabase Service Error: $e");
      return {'status': 'error'};
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> deleteAccount() async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('${AppConfig.apiBaseUrl}/account'),
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );

    if (response.statusCode != 200) {
      throw Exception('Deletion failed: ${response.body}');
    }

    await _supabase.auth.signOut();
  }

  Future<void> updateProjectStats(
    String projectId, {
    int? dotCount,
    String? difficulty,
  }) async {
    await _supabase
        .from('projects')
        .update({
          if (dotCount != null) 'dot_count': dotCount,
          if (difficulty != null) 'difficulty': difficulty,
        })
        .eq('id', projectId);
  }

  // Columns needed for the project list / gallery.  Excludes the three heavy
  // difficulty dot-set columns (up to 200 entries × 5 fields each per column)
  // which are only needed when a game actually starts.
  static const _listColumns =
      'id, user_id, name, image_path, dot_count, sparsity, status, difficulty, '
      'last_index, remove_bg, easy_cleared, medium_cleared, hard_cleared, '
      'created_at, dots, erased_points, is_public';

  Future<List<Map<String, dynamic>>> getAllProjects() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    // User's own projects (including any they've marked public)
    final userProjects = await _supabase
        .from('projects')
        .select(_listColumns)
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    // Featured projects from other accounts
    final featuredProjects = await _supabase
        .from('projects')
        .select(_listColumns)
        .eq('is_public', true)
        .neq('user_id', user.id)
        .order('created_at', ascending: false);

    return [
      ...List<Map<String, dynamic>>.from(userProjects),
      ...List<Map<String, dynamic>>.from(featuredProjects),
    ];
  }

  /// Full row including calibrated dot sets — call only when starting a game.
  Future<Map<String, dynamic>?> getProjectDetail(String id) async {
    try {
      return await _supabase
          .from('projects')
          .select()
          .eq('id', id)
          .single();
    } catch (e) {
      debugPrint('getProjectDetail error: $e');
      return null;
    }
  }

  Future<Uint8List> downloadImage(String path) async {
    return await _supabase.storage.from('images').download(path);
  }

  Future<void> saveProgress(
    String projectId, {
    required int lastIndex,
    required String difficulty,
  }) async {
    await _supabase
        .from('projects')
        .update({'last_index': lastIndex, 'difficulty': difficulty})
        .eq('id', projectId);
  }

  Future<void> deleteProject(String id, String imagePath) async {
    // 1. Delete the image from Storage (if it exists)
    try {
      await _supabase.storage.from('images').remove([imagePath]);
    } catch (e) {
      print(
        "Storage deletion warning: $e",
      ); // Don't stop if image is already gone
    }

    // 2. Delete the row from the database
    await _supabase.from('projects').delete().eq('id', id);
  }
}
