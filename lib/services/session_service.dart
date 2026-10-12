import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class SessionService {
  static const String _key = 'session_data';

  static Future<void> save(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Sign-in token and app header for APIs that need the signed-in employee
  /// (employee list, profile, company events).
  static Future<Map<String, String>> authHeaders() async {
    final token = (await load())?['access_token'];
    return {
      ...AuthService.appHeaders,
      if (token is String) 'Authorization': 'Bearer $token',
    };
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
