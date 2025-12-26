import 'package:shared_preferences/shared_preferences.dart';

class PreferencesManager {
  static const String _keyAuthToken = 'auth_token';
  static const String _keyChildHash = 'child_hash';
  static const String _keyChildName = 'child_name';
  static const String _keyParentEmail = 'parent_email';
  static const String _keyParentPassword = 'parent_password';

  final SharedPreferences _prefs;

  PreferencesManager(this._prefs);

  static Future<PreferencesManager> init() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesManager(prefs);
  }

  // Auth Token
  Future<void> setAuthToken(String token) async {
    await _prefs.setString(_keyAuthToken, token);
  }

  String? getAuthToken() {
    return _prefs.getString(_keyAuthToken);
  }

  // Parent Email
  Future<void> setParentEmail(String email) async {
    await _prefs.setString(_keyParentEmail, email);
  }

  String? getParentEmail() {
    return _prefs.getString(_keyParentEmail);
  }

  // Parent Password
  Future<void> setParentPassword(String password) async {
    await _prefs.setString(_keyParentPassword, password);
  }

  String? getParentPassword() {
    return _prefs.getString(_keyParentPassword);
  }

  // Child Hash
  Future<void> setChildHash(String hash) async {
    await _prefs.setString(_keyChildHash, hash);
  }

  String? getChildHash() {
    return _prefs.getString(_keyChildHash);
  }

  // Child Name
  Future<void> setChildName(String name) async {
    await _prefs.setString(_keyChildName, name);
  }

  String? getChildName() {
    return _prefs.getString(_keyChildName);
  }

  // Clear all (Logout)
  Future<void> clearAll() async {
    await _prefs.clear();
  }

  bool isLoggedIn() {
    final token = getAuthToken();
    return token != null && token.isNotEmpty;
  }

  bool hasSelectedChild() {
    final hash = getChildHash();
    return hash != null && hash.isNotEmpty;
  }
}
