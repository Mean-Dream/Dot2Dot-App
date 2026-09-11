import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';

class AuthController extends ChangeNotifier {
  final SupabaseService _service;

  AuthController(this._service);

  bool isDeleting = false;
  String? error;

  String? get currentUserEmail => _service.currentUserEmail;

  Future<bool> deleteAccount() async {
    isDeleting = true;
    error = null;
    notifyListeners();
    try {
      await _service.deleteAccount();
      return true;
    } catch (e) {
      error = e.toString();
      debugPrint('deleteAccount error: $e');
      return false;
    } finally {
      isDeleting = false;
      notifyListeners();
    }
  }
}
