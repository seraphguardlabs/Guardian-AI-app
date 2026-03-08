import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';

class AppBlockerService extends ChangeNotifier {
  static const platform = MethodChannel('com.example.guardian_ai/app_blocker');
  
  Timer? _monitoringTimer;
  Map<String, double> _restrictedApps = {}; // packageName -> allowed hours
  Map<String, int> _appUsage = {}; // packageName -> seconds used today
  bool _isMonitoring = false;
  bool _dailyLimitExceeded = false;
  
  /// Packages that should never be blocked (essentials)
  static const Set<String> whitelistedPackages = {
    'com.example.guardian_ai',
  };

  /// Keywords that identify essential system apps (phone, messages, camera)
  static const List<String> _essentialKeywords = [
    'dialer', 'phone', 'telecom',
    'mms', 'sms', 'messag',
    'camera',
  ];
  
  Map<String, double> get restrictedApps => Map.unmodifiable(_restrictedApps);
  Map<String, int> get appUsage => Map.unmodifiable(_appUsage);
  bool get isMonitoring => _isMonitoring;
  bool get dailyLimitExceeded => _dailyLimitExceeded;
  
  /// Check if a package is an essential app that should never be blocked
  static bool isEssentialPackage(String packageName) {
    if (whitelistedPackages.contains(packageName)) return true;
    final lower = packageName.toLowerCase();
    return _essentialKeywords.any((kw) => lower.contains(kw));
  }

  /// Update restricted apps from server (per-app limits only)
  void updateRestrictions(Map<String, dynamic> restrictedApps) {
    _restrictedApps.clear();
    
    restrictedApps.forEach((packageName, allowedHours) {
      final hours = (allowedHours is int) 
          ? allowedHours.toDouble() 
          : (allowedHours is double) 
              ? allowedHours 
              : double.tryParse(allowedHours.toString()) ?? 0.0;
      
      _restrictedApps[packageName] = hours;
      debugPrint('🚫 Restriction set: $packageName -> ${hours}h allowed');
    });
    
    debugPrint('📋 Total restricted apps: ${_restrictedApps.length}');
    notifyListeners();
    
    // Start monitoring if we have restrictions
    if (_restrictedApps.isNotEmpty && !_isMonitoring) {
      startMonitoring();
    }
  }

  /// Set daily limit exceeded flag (separate from per-app restrictions)
  void setDailyLimitExceeded(bool exceeded) {
    if (_dailyLimitExceeded != exceeded) {
      _dailyLimitExceeded = exceeded;
      debugPrint('⏰ Daily limit exceeded flag: $exceeded');
      notifyListeners();
    }
  }
  
  /// Start monitoring app usage
  void startMonitoring() {
    if (_isMonitoring) {
      debugPrint('⚠️ App Blocker: Already monitoring');
      return;
    }
    
    debugPrint('🎯 App Blocker: Starting monitoring');
    _isMonitoring = true;
    
    // Update usage stats immediately
    _updateUsageStats();
    
    // Check every 5 seconds for foreground app
    _monitoringTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkForegroundApp();
    });
    
    notifyListeners();
  }
  
  /// Stop monitoring
  void stopMonitoring() {
    debugPrint('🛑 App Blocker: Stopping monitoring');
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _isMonitoring = false;
    notifyListeners();
  }
  
  /// Update usage statistics for today
  Future<void> _updateUsageStats() async {
    try {
      // Check if usage permission is granted
      bool? isPermissionGranted = await UsageStats.checkUsagePermission();
      
      if (isPermissionGranted != true) {
        debugPrint('⚠️ App Blocker: Usage permission not granted');
        return;
      }
      
      // Get usage stats for today
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      
      final stats = await UsageStats.queryUsageStats(
        startOfDay,
        now,
      );
      
      _appUsage.clear();
      
      for (var stat in stats) {
        final packageName = stat.packageName ?? '';
        final usageTime = int.parse(stat.totalTimeInForeground ?? '0') ~/ 1000; // Convert to seconds
        
        if (usageTime > 0 && packageName.isNotEmpty) {
          _appUsage[packageName] = usageTime;
        }
      }
      
      debugPrint('📊 App Blocker: Updated usage stats for ${_appUsage.length} apps');
      
    } catch (e) {
      debugPrint('❌ App Blocker: Error updating usage stats: $e');
    }
  }
  
  /// Check if foreground app should be blocked
  Future<void> _checkForegroundApp() async {
    try {
      // Update usage stats periodically
      await _updateUsageStats();
      
      // Get current foreground app (this requires platform-specific implementation)
      final foregroundApp = await _getForegroundApp();
      
      if (foregroundApp == null || foregroundApp.isEmpty) {
        return;
      }
      
      // Never block essential apps (Guardian AI, phone, messages, camera)
      if (isEssentialPackage(foregroundApp)) {
        return;
      }

      // ── Per-app limit check ──
      // Only block this specific app if IT has exceeded ITS own limit.
      if (_restrictedApps.containsKey(foregroundApp)) {
        final allowedHours = _restrictedApps[foregroundApp]!;
        final usedSeconds = _appUsage[foregroundApp] ?? 0;
        final usedHours = usedSeconds / 3600.0;
        
        debugPrint('📱 Checking: $foregroundApp | Allowed: ${allowedHours}h | Used: ${usedHours.toStringAsFixed(2)}h');
        
        if (allowedHours == 0) {
          // 0 hours = fully blocked (no usage allowed at all)
          debugPrint('⛔ BLOCKING: $foregroundApp — fully blocked (0h allowed)');
          await _blockApp(foregroundApp);
          return;
        }
        
        if (usedHours >= allowedHours) {
          debugPrint('⛔ BLOCKING: $foregroundApp exceeded its per-app time limit! (${usedHours.toStringAsFixed(2)}h >= ${allowedHours}h)');
          await _blockApp(foregroundApp);
          return;
        }
        
        // App is in restriction list but has NOT exceeded its limit — allow it
        debugPrint('✅ ALLOWING: $foregroundApp — within per-app limit (${usedHours.toStringAsFixed(2)}h / ${allowedHours}h)');
        return;
      }

      // ── Daily limit check ──
      // Only applies to apps NOT in the per-app restriction list.
      // Apps with per-app limits are handled above.
      if (_dailyLimitExceeded) {
        debugPrint('⛔ BLOCKING: $foregroundApp — daily screen-time limit exceeded!');
        await _blockApp(foregroundApp);
        return;
      }
      
    } catch (e) {
      debugPrint('❌ App Blocker: Error checking foreground app: $e');
    }
  }
  
  /// Get foreground app package name (platform-specific)
  Future<String?> _getForegroundApp() async {
    try {
      // This requires a platform channel implementation
      final result = await platform.invokeMethod<String>('getForegroundApp');
      return result;
    } catch (e) {
      // Fallback: use usage stats to get most recent app
      try {
        final now = DateTime.now();
        final fiveSecondsAgo = now.subtract(const Duration(seconds: 5));
        
        final stats = await UsageStats.queryUsageStats(
          fiveSecondsAgo,
          now,
        );
        
        if (stats.isNotEmpty) {
          // Get the app with most recent usage
          stats.sort((a, b) {
            final aTime = int.tryParse(a.lastTimeUsed ?? '0') ?? 0;
            final bTime = int.tryParse(b.lastTimeUsed ?? '0') ?? 0;
            return bTime.compareTo(aTime);
          });
          
          return stats.first.packageName;
        }
      } catch (e) {
        debugPrint('❌ App Blocker: Fallback getForegroundApp failed: $e');
      }
      
      return null;
    }
  }
  
  /// Block an app by sending user to home screen
  Future<void> _blockApp(String packageName) async {
    try {
      // Method 1: Try platform channel to kill app and go home
      try {
        await platform.invokeMethod('blockApp', {'package': packageName});
        debugPrint('✅ App blocked via platform channel: $packageName');
        return;
      } catch (e) {
        debugPrint('⚠️ Platform channel block failed, using fallback: $e');
      }
      
      // Method 2: Fallback - just go to home screen
      await platform.invokeMethod('goToHomeScreen');
      debugPrint('✅ Sent to home screen (fallback)');
      
    } catch (e) {
      debugPrint('❌ App Blocker: Failed to block app: $e');
    }
  }
  
  /// Check if a specific app is currently blocked
  bool isAppBlocked(String packageName) {
    if (!_restrictedApps.containsKey(packageName)) {
      return false;
    }
    
    final allowedHours = _restrictedApps[packageName]!;
    
    // 0 hours = fully blocked
    if (allowedHours == 0) return true;
    
    final usedSeconds = _appUsage[packageName] ?? 0;
    final usedHours = usedSeconds / 3600.0;
    
    return usedHours >= allowedHours;
  }
  
  /// Get time remaining for an app (in seconds)
  int getTimeRemaining(String packageName) {
    if (!_restrictedApps.containsKey(packageName)) {
      return -1; // Not restricted
    }
    
    final allowedHours = _restrictedApps[packageName]!;
    final usedSeconds = _appUsage[packageName] ?? 0;
    final allowedSeconds = (allowedHours * 3600).toInt();
    
    final remaining = allowedSeconds - usedSeconds;
    return remaining > 0 ? remaining : 0;
  }
  
  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
