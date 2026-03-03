import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rcs/core/services/rb_service.dart';

class SessionService {
  static const _keyIsLoggedIn = 'is_logged_in';
  static const _keyRobots = 'connected_robots';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  static bool getLoginState() =>
      _prefs?.getBool(_keyIsLoggedIn) ?? false;

  static Future<void> saveLoginState(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_keyIsLoggedIn, value);
  }

  // ── Robots ─────────────────────────────────────────────────────────────────

  static List<RobotInfo> getRobots() {
    final raw = _prefs?.getStringList(_keyRobots) ?? [];
    return raw.map((e) {
      try {
        return RobotInfo.fromJson(
            jsonDecode(e) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<RobotInfo>().toList();
  }

  static Future<void> saveRobots(List<RobotInfo> robots) async {
    _prefs ??= await SharedPreferences.getInstance();
    // Uses RobotInfo.toJson() which now includes config
    final encoded = robots.map((r) => jsonEncode(r.toJson())).toList();
    await _prefs!.setStringList(_keyRobots, encoded);
  }

  // ── Clear ──────────────────────────────────────────────────────────────────

  static Future<void> clearSession() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_keyIsLoggedIn);
    await _prefs!.remove(_keyRobots);
  }
}