import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PreferencesManager {
  static const String _keyAuthToken = 'auth_token';
  static const String _keyChildHash = 'child_hash';
  static const String _keyChildName = 'child_name';
  static const String _keyParentEmail = 'parent_email';
  static const String _keyParentPassword = 'parent_password';
  static const String _keyIsParentLoggedIn = 'is_parent_logged_in';
  static const String _keyPublicKey = 'public_key';
  static const String _keyPrivateKey = 'private_key';
  static const String _keyViewMode = 'view_mode'; // 'parent' or 'child'
  static const String _keyLastRoute = 'last_route';

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

  // Parent Logged In Status
  Future<void> setParentLoggedIn(bool isLoggedIn) async {
    await _prefs.setBool(_keyIsParentLoggedIn, isLoggedIn);
  }

  bool isParentLoggedIn() {
    return _prefs.getBool(_keyIsParentLoggedIn) ?? false;
  }

  // Public Key
  Future<void> setPublicKey(String publicKey) async {
    await _prefs.setString(_keyPublicKey, publicKey);
  }

  String? getPublicKey() {
    return _prefs.getString(_keyPublicKey);
  }

  // Private Key
  Future<void> setPrivateKey(String privateKey) async {
    await _prefs.setString(_keyPrivateKey, privateKey);
  }

  String? getPrivateKey() {
    return _prefs.getString(_keyPrivateKey);
  }

  // View Mode (parent or child)
  Future<void> setViewMode(String mode) async {
    await _prefs.setString(_keyViewMode, mode);
  }

  String? getViewMode() {
    return _prefs.getString(_keyViewMode);
  }

  // Last Route
  Future<void> setLastRoute(String route) async {
    await _prefs.setString(_keyLastRoute, route);
  }

  String? getLastRoute() {
    return _prefs.getString(_keyLastRoute);
  }

  // Clear all (Logout)
  Future<void> clearAll() async {
    await _prefs.clear();
  }

  bool isLoggedIn() {
    // Check if parent is logged in
    return isParentLoggedIn() && 
           getParentEmail() != null && 
           getParentPassword() != null;
  }

  bool hasSelectedChild() {
    final hash = getChildHash();
    return hash != null && hash.isNotEmpty;
  }
}
