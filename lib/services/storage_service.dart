import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/collection_model.dart';

class StorageService {
  static const String _storageKey = 'scanner_pro_v2';

  /// Save state to SharedPreferences
  static Future<void> saveAppState(AppStateData state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, state.toJsonString());
  }

  /// Load state from SharedPreferences
  static Future<AppStateData?> loadAppState() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString(_storageKey);
    if (dataStr == null || dataStr.isEmpty) return null;
    try {
      return AppStateData.fromJsonString(dataStr);
    } catch (e) {
      debugPrint("Error loading storage: $e");
      return null;
    }
  }
}
