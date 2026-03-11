import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// PreferencesManager - Centralized local storage management
/// 
/// Handles all SharedPreferences operations for the app including:
/// - Parent authentication credentials
/// - Child profile data
/// - Encryption keys (RSA public/private)
/// - View mode and navigation state
/// 
/// Usage:
/// ```dart
/// final prefs = await PreferencesManager.init();
/// await prefs.setParentEmail('parent@example.com');
/// final email = prefs.getParentEmail();
/// ```
/// 
/// Security Note: Passwords are stored in plain text in SharedPreferences.
/// For production, consider using flutter_secure_storage for sensitive data.
class PreferencesManager {
  // Storage keys - centralized for consistency
  static const String _keyAuthToken = 'auth_token';
  static const String _keyChildHash = 'child_hash';
  static const String _keyChildName = 'child_name';
  static const String _keyChildPassword = 'child_password';
  static const String _keyParentEmail = 'parent_email';
  static const String _keyParentPassword = 'parent_password';
  static const String _keyIsParentLoggedIn = 'is_parent_logged_in';
  static const String _keyPublicKey = 'public_key';
  static const String _keyPrivateKey = 'private_key';
  static const String _keyGuardianId = 'guardian_id';
  static const String _keyViewMode = 'view_mode'; // 'parent' or 'child'
  static const String _keyLastRoute = 'last_route';
  static const String _keyTaskMetadata = 'task_metadata'; // Stores unencrypted task titles/descriptions
  static const String _keyLocallyDoneRewardTasks = 'locally_done_reward_tasks'; // Child-side: reward task IDs child considers done
  static const String _keyScreenCaptureGranted = 'screen_capture_granted';

  final SharedPreferences _prefs;

  PreferencesManager(this._prefs);

  /// Initialize PreferencesManager - call once at app startup
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

  // Child Password
  Future<void> setChildPassword(String password) async {
    await _prefs.setString(_keyChildPassword, password);
  }

  String? getChildPassword() {
    return _prefs.getString(_keyChildPassword);
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

  // Guardian ID
  Future<void> setGuardianId(int guardianId) async {
    await _prefs.setInt(_keyGuardianId, guardianId);
  }

  int? getGuardianId() {
    return _prefs.getInt(_keyGuardianId);
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

  // Screen Capture Permission
  Future<void> setScreenCaptureGranted(bool granted) async {
    await _prefs.setBool(_keyScreenCaptureGranted, granted);
  }

  bool isScreenCaptureGranted() {
    return _prefs.getBool(_keyScreenCaptureGranted) ?? false;
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

  // Task Metadata (store unencrypted task info for parent view)
  /// Save unencrypted task metadata (title, description) by task ID
  /// Format: { "taskId": { "title": "...", "description": "..." } }
  Future<void> saveTaskMetadata(int taskId, String title, String description) async {
    final metadata = getTaskMetadata();
    metadata[taskId.toString()] = {
      'title': title,
      'description': description,
    };
    await _prefs.setString(_keyTaskMetadata, jsonEncode(metadata));
  }

  /// Get all task metadata
  Map<String, dynamic> getTaskMetadata() {
    final jsonString = _prefs.getString(_keyTaskMetadata);
    if (jsonString == null || jsonString.isEmpty) {
      return {};
    }
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  /// Get task metadata by task ID
  Map<String, dynamic>? getTaskMetadataById(int taskId) {
    final metadata = getTaskMetadata();
    final taskData = metadata[taskId.toString()];
    if (taskData is Map<String, dynamic>) {
      return taskData;
    }
    return null;
  }

  /// Remove task metadata (when task is deleted)
  Future<void> removeTaskMetadata(int taskId) async {
    final metadata = getTaskMetadata();
    metadata.remove(taskId.toString());
    await _prefs.setString(_keyTaskMetadata, jsonEncode(metadata));
  }

  // ── Locally-done reward tasks (child side) ──────────────────────────────
  // When the child clicks "I'm Done" on a reward task we do NOT call the
  // backend complete endpoint (which would auto-approve the time extension).
  // Instead we store the task ID locally so the UI can reflect "done – waiting
  // for parent" while leaving the actual approval to the parent.

  /// Mark a reward task as locally done (child side only).
  Future<void> markRewardTaskLocallyDone(int taskId) async {
    final ids = getLocallyDoneRewardTasks();
    ids.add(taskId);
    await _prefs.setStringList(
      _keyLocallyDoneRewardTasks,
      ids.map((e) => e.toString()).toList(),
    );
  }

  /// Check whether a reward task has been locally marked as done.
  bool isRewardTaskLocallyDone(int taskId) {
    return getLocallyDoneRewardTasks().contains(taskId);
  }

  /// Get all locally-done reward task IDs.
  Set<int> getLocallyDoneRewardTasks() {
    final raw = _prefs.getStringList(_keyLocallyDoneRewardTasks) ?? [];
    return raw.map((s) => int.tryParse(s)).whereType<int>().toSet();
  }

  /// Remove a reward task from the local "done" set (e.g. parent denied it).
  Future<void> clearRewardTaskLocallyDone(int taskId) async {
    final ids = getLocallyDoneRewardTasks();
    ids.remove(taskId);
    await _prefs.setStringList(
      _keyLocallyDoneRewardTasks,
      ids.map((e) => e.toString()).toList(),
    );
  }
}
