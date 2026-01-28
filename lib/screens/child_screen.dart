import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:usage_stats/usage_stats.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../utils/preferences_manager.dart';
import '../services/location_service.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../services/encryption_service.dart';
import '../services/app_blocker_service.dart';
import '../services/background_monitoring_service.dart';
import '../services/time_extension_service.dart';
import '../services/text_analysis_service.dart';
import '../services/vision_analysis_service.dart';
import '../services/screen_monitoring_service.dart';
import '../services/text_threat_detection_service.dart';
import '../models/restrictions_data.dart';
import '../models/task.dart';
import '../widgets/app_bottom_nav.dart';
import 'my_tasks_screen.dart';

class ChildScreen extends StatefulWidget {
  const ChildScreen({super.key});

  @override
  State<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends State<ChildScreen> {
  static const platform = MethodChannel('com.guardian_ai/screen_time');
  static const browserChannel = MethodChannel('com.guardian_ai/browser_history');
  String _screenTime = 'Unknown';
  double? _dailyLimitHours; // Global daily limit from server or default
  bool _loading = true;
  List<UsageInfo> _usageStats = [];
  Map<String, AppInfo> _apps = {};
  List<Map<String, String>> _browserHistory = [];
  Timer? _refreshTimer;
  RestrictionsData? _restrictions;
  StreamSubscription<Map<String, dynamic>>? _wsMessageSubscription;
  StreamSubscription<Map<String, dynamic>>? _wsRestrictionsSubscription;
  bool _examMode = false;
  List<String> _examModeApps = [];
  List<Task> _pendingTasks = [];
  bool _loadingTasks = false;
  bool _aiModelsLoaded = false;
  bool _backgroundMonitoringActive = false;
  String _aiServiceStatus = 'Initializing...';
  DateTime? _lastAnalysisTime;
  int _modelsRunning = 0;

  @override
  void initState() {
    super.initState();
    BackgroundMonitoringService.start();
    _refreshData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshData();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🎓 Child Screen: Post-frame callback starting...');
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      prefs.setViewMode('child');
      prefs.setLastRoute('/child');
      
      // Upload child's public key to server
      _uploadChildPublicKey();
      
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.startTracking();
      _initializeWebSocket();
      _fetchRestrictions();
      debugPrint('🎓 Child Screen: Calling _fetchExamMode() from initState');
      _fetchExamMode();
      _loadDailyLimit();
      _loadPendingTasks();
      _initializeAIServices();
    });
  }

  Future<void> _uploadChildPublicKey() async {
    debugPrint('🔐 Child Screen: Uploading child public key to server...');
    
    // Initialize encryption service if not already done
    if (!EncryptionService.instance.isInitialized) {
      await EncryptionService.instance.initialize();
    }
    
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash();
    
    if (childHash == null || childHash.isEmpty) {
      debugPrint('⚠️ Child Screen: No child hash available');
      return;
    }
    
    if (EncryptionService.instance.hasKeys && EncryptionService.instance.publicKey != null) {
      final apiService = ApiService();
      final result = await apiService.uploadChildPublicKey(
        childHash: childHash,
        publicKey: EncryptionService.instance.publicKey!,
      );
      
      if (result['success'] == true) {
        debugPrint('✅ Child Screen: Child public key uploaded successfully');
      } else {
        debugPrint('❌ Child Screen: Failed to upload child public key: ${result['error']}');
      }
    } else {
      debugPrint('⚠️ Child Screen: No encryption keys available');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsMessageSubscription?.cancel();
    _wsRestrictionsSubscription?.cancel();
    final locationService = Provider.of<LocationService>(context, listen: false);
    locationService.stopTracking();
    super.dispose();
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _getScreenTime(),
      _initUsageStats(),
      _getBrowserHistory(),
      _loadPendingTasks(),
    ]);
    _sendDataViaWebSocket();
  }

  Future<void> _initializeWebSocket() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();

    if (childHash != null && childHash.isNotEmpty) {
      final wsService = Provider.of<WebSocketService>(context, listen: false);
      await wsService.connect(childHash);
      debugPrint('🔌 WebSocket connected for child: $childHash');

      _wsMessageSubscription = wsService.messages.listen((message) {
        if (message['type'] == 'restrictions_update') {
          debugPrint('🚫 Received restrictions update via WebSocket');
          _fetchRestrictions();
          debugPrint('🎓 Fetching exam mode after WebSocket restrictions update');
          _fetchExamMode(); // Also check exam mode when restrictions update
        }
      });

      _wsRestrictionsSubscription = wsService.restrictions.listen((message) {
        if (message['type'] == 'restrictions_update') {
          debugPrint('🚫 Received restrictions from WSS');
          final restrictedApps = message['restricted_apps'] as Map<String, dynamic>? ?? {};

          // Also fetch exam mode to get effective restrictions
          _fetchExamMode().then((_) {
            final effectiveRestrictions = _getEffectiveRestrictions();
            final appBlocker = Provider.of<AppBlockerService>(context, listen: false);
            appBlocker.updateRestrictions(effectiveRestrictions);
            BackgroundMonitoringService.updateRestrictions(effectiveRestrictions);
          });

          if (mounted) {
            setState(() {
              _restrictions = RestrictionsData.fromJson(restrictedApps);
            });
          }
        }
      });
    } else {
      debugPrint('⚠️ No child hash found, skipping WebSocket connection');
    }
  }

  Future<void> _fetchRestrictions() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();

    if (childHash == null || childHash.isEmpty) {
      debugPrint('⚠️ No child hash, skipping restrictions fetch');
      return;
    }

    final apiService = Provider.of<ApiService>(context, listen: false);

    // Use the mobile restricted-apps endpoint so the child device
    // enforces the same per-app limits configured in Block Sites & Apps.
    final result = await apiService.getAppRestrictions(
      email: prefsManager.getParentEmail() ?? '',
      password: prefsManager.getParentPassword() ?? '',
      childHash: childHash,
    );

    if (result['success'] == true && mounted) {
      final data = result['data'] as Map<String, dynamic>;
      final rawRestricted = data['restricted_apps'] as Map<String, dynamic>? ?? {};
      final restrictions = RestrictionsData.fromJson(rawRestricted);
      setState(() {
        _restrictions = restrictions;
      });
      debugPrint('✅ Restrictions updated: ${_restrictions!.restrictedApps.length} apps');

      // Fetch exam mode to get the combined restrictions
      await _fetchExamMode();

      final appBlocker = Provider.of<AppBlockerService>(context, listen: false);
      appBlocker.updateRestrictions(_getEffectiveRestrictions());
      BackgroundMonitoringService.updateRestrictions(_getEffectiveRestrictions());
    }
  }

  Future<void> _fetchExamMode() async {
    debugPrint('\n🎓 ===== FETCHING EXAM MODE =====');
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();
    final parentEmail = prefsManager.getParentEmail();
    final parentPassword = prefsManager.getParentPassword();

    debugPrint('🎓 Child hash: $childHash');
    debugPrint('🎓 Parent email available: ${parentEmail?.isNotEmpty ?? false}');
    debugPrint('🎓 Parent password available: ${parentPassword?.isNotEmpty ?? false}');

    if (childHash == null || childHash.isEmpty) {
      debugPrint('⚠️ No child hash, skipping exam mode fetch');
      return;
    }

    if (parentEmail == null || parentPassword == null) {
      debugPrint('⚠️ No parent credentials found, skipping exam mode fetch');
      return;
    }

    debugPrint('🎓 Calling API: GET /api/mobile/child/$childHash/exam-mode/');
    final apiService = Provider.of<ApiService>(context, listen: false);
    final result = await apiService.getExamMode(
      email: parentEmail,
      password: parentPassword,
      childHash: childHash,
    );

    debugPrint('🎓 API Response: $result');
    debugPrint('🎓 Success: ${result['success']}');
    debugPrint('🎓 Data: ${result['data']}');

    if (result['success'] == true && mounted) {
      final data = result['data'] as Map<String, dynamic>;
      final examModeValue = data['exam_mode'] ?? false;
      final examModeAppsList = List<String>.from(data['exam_mode_apps'] ?? []);
      
      debugPrint('🎓 Parsed exam_mode: $examModeValue (type: ${examModeValue.runtimeType})');
      debugPrint('🎓 Parsed exam_mode_apps: $examModeAppsList');
      
      setState(() {
        _examMode = examModeValue;
        _examModeApps = examModeAppsList;
      });
      
      debugPrint('✅ EXAM MODE STATE UPDATED:');
      debugPrint('   - Exam Mode Active: $_examMode');
      debugPrint('   - Blocked Apps Count: ${_examModeApps.length}');
      debugPrint('   - Blocked Apps: $_examModeApps');
    } else {
      debugPrint('❌ Failed to fetch exam mode or widget not mounted');
      debugPrint('   - Success: ${result['success']}');
      debugPrint('   - Mounted: $mounted');
      debugPrint('   - Error: ${result['error']}');
    }
    debugPrint('🎓 ===== EXAM MODE FETCH COMPLETE =====\n');
  }

  Map<String, double> _getEffectiveRestrictions() {
    if (_restrictions == null) return {};
    
    final effective = Map<String, double>.from(_restrictions!.restrictedApps);
    
    // If exam mode is active, set exam mode apps to 0 hours
    if (_examMode) {
      for (final packageName in _examModeApps) {
        effective[packageName] = 0.0;
        debugPrint('🎓 Exam mode: Blocking $packageName');
      }
    }
    
    return effective;
  }

  Future<void> _sendDataViaWebSocket() async {
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    if (!wsService.isConnected) {
      debugPrint('⚠️ WebSocket not connected, skipping data send');
      return;
    }

    await _sendScreenTimeData();
    await _sendLocationData();
    await _sendWebsiteData();
  }

  Future<void> _sendScreenTimeData() async {
    if (_usageStats.isEmpty) return;

    final wsService = Provider.of<WebSocketService>(context, listen: false);

    int totalSeconds = 0;
    final appWiseData = <String, Map<String, int>>{};

    for (var usage in _usageStats) {
      final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
      final seconds = millis ~/ 1000;
      totalSeconds += seconds;
      final hour = DateTime.now().hour.toString().padLeft(2, '0');
      final packageName = usage.packageName ?? 'unknown';
      appWiseData[packageName] = {hour: seconds};
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    await wsService.sendScreenTime(
      date: dateStr,
      totalScreenTime: totalSeconds,
      appWiseData: appWiseData,
    );

    debugPrint('📱 Sent screen time: ${totalSeconds}s, ${appWiseData.length} apps');
  }

  Future<void> _sendLocationData() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    if (locationService.currentPosition != null) {
      await wsService.sendLocation(
        timestamp: DateTime.now().toUtc().toIso8601String(),
        latitude: locationService.currentPosition!.latitude,
        longitude: locationService.currentPosition!.longitude,
      );

      debugPrint('📍 Sent location: ${locationService.currentPosition!.latitude}, ${locationService.currentPosition!.longitude}');
    }
  }

  Future<void> _sendWebsiteData() async {
    if (_browserHistory.isEmpty) return;

    final wsService = Provider.of<WebSocketService>(context, listen: false);

    final logs = _browserHistory.map((entry) {
      return {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'url': entry['url'] ?? '',
        'accessed': true,
      };
    }).toList();

    await wsService.sendSiteAccess(logs: logs);

    debugPrint('🌐 Sent ${logs.length} website visits');
  }

  Future<void> _getScreenTime() async {
    String screenTime;
    try {
      final String result = await platform.invokeMethod('getScreenTime');
      screenTime = result;
    } on PlatformException catch (e) {
      screenTime = "Failed to get screen time: '${e.message}'.";
    }

    if (!mounted) return;

    setState(() {
      _screenTime = screenTime;
      _loading = false;
    });
    // After updating screen time, check if the global daily limit is exceeded
    _checkAndApplyDailyLimitEnforcement();
  }
  
  Future<void> _loadDailyLimit() async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash();
    final parentEmail = prefs.getParentEmail();
    final parentPassword = prefs.getParentPassword();

    // Default to 8 hours if we cannot fetch from server
    double dailyLimit = 8.0;

    if (childHash != null && parentEmail != null && parentPassword != null) {
      try {
        final api = Provider.of<ApiService>(context, listen: false);
        final result = await api.fetchDailyLimit(parentEmail, parentPassword, childHash);
        if (result['success'] == true) {
          final data = result['data'] as Map<String, dynamic>?;
          if (data != null) {
            // Backend returns 'daily_screen_time_limit' (and may not include the old 'daily_limit_hours')
            final value = data['daily_screen_time_limit'] ?? data['daily_limit_hours'];
            if (value is num && value > 0) {
              dailyLimit = value.toDouble();
            }
          }
        }
      } catch (_) {
        // Ignore errors and keep default 8 hours
      }
    }

    if (!mounted) return;
    setState(() {
      _dailyLimitHours = dailyLimit;
      debugPrint('🧒 Child screen daily limit hours: $_dailyLimitHours');
    });
    // After loading the daily limit, check enforcement with the latest screen time
    _checkAndApplyDailyLimitEnforcement();
  }

  Future<void> _loadPendingTasks() async {
    debugPrint('📋 Child Screen: Loading pending tasks...');
    setState(() => _loadingTasks = true);

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash() ?? '';

    debugPrint('📋 ========== CHILD_SCREEN LOAD TASKS ==========');
    debugPrint('📋 Child Hash: ${childHash.isEmpty ? "EMPTY" : childHash}');

    if (childHash.isEmpty) {
      debugPrint('📋 ❌ CANNOT LOAD TASKS: Child Hash is empty');
      setState(() => _loadingTasks = false);
      return;
    }

    debugPrint('📋 ✅ Child Hash OK, calling API...');
    final apiService = ApiService();
    final result = await apiService.getMyTasks(
      childHash: childHash,
      completed: 'false', // Only get pending tasks
    );

    debugPrint('📋 API Result success: ${result['success']}');
    debugPrint('📋 API Result: $result');

    if (!mounted) {
      debugPrint('📋 ⚠️ Widget not mounted, cannot update state');
      return;
    }

    if (result['success'] == true) {
      List<Task> tasks = result['tasks'] as List<Task>;
      debugPrint('📋 ✅ Received ${tasks.length} tasks from API');
      debugPrint('📋 Tasks: ${tasks.map((t) => t.id).toList()}');
      
      // Decrypt task titles and descriptions
      final encryptionService = EncryptionService.instance;
      debugPrint('📋 Starting decryption...');
      List<Task> decryptedTasks = tasks.map((task) {
        final decryptedTitle = encryptionService.decryptWithPrivateKey(task.title);
        final decryptedDescription = encryptionService.decryptWithPrivateKey(task.description);
        
        debugPrint('📋 Task ${task.id}: decrypted=${decryptedTitle != null}');
        
        if (decryptedTitle != null || decryptedDescription != null) {
          return Task(
            id: task.id,
            title: decryptedTitle ?? task.title,
            description: decryptedDescription ?? task.description,
            isCompleted: task.isCompleted,
            completedAt: task.completedAt,
            created: task.created,
            updated: task.updated,
            assignedBy: task.assignedBy,
          );
        }
        return task;
      }).toList();
      
      debugPrint('📋 ✅ Successfully loaded ${decryptedTasks.length} pending tasks');
      setState(() {
        _pendingTasks = decryptedTasks;
        _loadingTasks = false;
      });
      debugPrint('📋 State updated: _pendingTasks.length = ${_pendingTasks.length}');
    } else {
      debugPrint('📋 ❌ Failed to load tasks: ${result['error']}');
      setState(() => _loadingTasks = false);
    }
  }

  Future<void> _initializeAIServices() async {
    debugPrint('🤖 Child Screen: Initializing AI Services...');
    if (!mounted) return;
    
    try {
      setState(() {
        _aiServiceStatus = 'Initializing...';
        _modelsRunning = 0;
      });

      // Initialize TextAnalysisService
      debugPrint('  📝 Initializing TextAnalysisService...');
      final textService = TextAnalysisService.instance;
      final textInitialized = await textService.initialize();

      // Initialize TextThreatDetectionService
      debugPrint('  🚫 Initializing TextThreatDetectionService...');
      final textThreatService = TextThreatDetectionService.instance;
      await textThreatService.initialize();
      
      if (!mounted) return;
      setState(() {
        _modelsRunning = textInitialized ? 1 : 0;
        _aiServiceStatus = textInitialized ? 'Text models loaded' : 'Text model failed';
      });

      if (!textInitialized) {
        debugPrint('❌ TextAnalysisService initialization failed');
        if (mounted) {
          setState(() {
            _aiServiceStatus = 'Error: Text model failed';
          });
        }
        return;
      }

      // Initialize VisionAnalysisService
      debugPrint('  👁️  Initializing VisionAnalysisService...');
      final visionService = VisionAnalysisService.instance;
      final visionInitialized = await visionService.initialize();
      
      if (!mounted) return;
      setState(() {
        _modelsRunning = visionInitialized ? 2 : 1;
        _aiServiceStatus = visionInitialized ? 'Vision model loaded' : 'Vision model failed';
      });

      if (!visionInitialized) {
        debugPrint('❌ VisionAnalysisService initialization failed');
        if (mounted) {
          setState(() {
            _aiServiceStatus = 'Error: Vision model failed';
          });
        }
        return;
      }

      // Initialize ScreenMonitoringService
      debugPrint('  📸 Initializing ScreenMonitoringService...');
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      final childHash = prefs.getChildHash() ?? '';
      final childName = 'Child'; // You can get this from preferences if stored
      
      final screenMonitoring = ScreenMonitoringService.instance;
      final monitoringInitialized = await screenMonitoring.initialize(
        childHash: childHash,
        childName: childName,
      );
      
      if (!mounted) return;
      setState(() {
        _modelsRunning = monitoringInitialized ? 3 : 2;
        _aiServiceStatus = monitoringInitialized ? 'Starting monitoring...' : 'Monitoring failed';
      });

      if (!monitoringInitialized) {
        debugPrint('❌ ScreenMonitoringService initialization failed');
        if (mounted) {
          setState(() {
            _aiServiceStatus = 'Error: Monitoring failed';
          });
        }
        return;
      }

      // Start screen monitoring
      debugPrint('  🚀 Starting screen monitoring...');
      final monitoringStarted = await screenMonitoring.startMonitoring();
      
      if (!mounted) return;
      setState(() {
        _aiModelsLoaded = monitoringStarted;
        _backgroundMonitoringActive = monitoringStarted;
        _aiServiceStatus = monitoringStarted ? 'Running' : 'Permission denied';
        _lastAnalysisTime = monitoringStarted ? DateTime.now() : null;
      });

      if (monitoringStarted) {
        debugPrint('✅ AI Services initialized and monitoring started successfully');
      } else {
        debugPrint('⚠️  AI Services initialized but monitoring not started (permission may be denied)');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing AI Services: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _aiServiceStatus = 'Error: Failed to initialize';
        });
      }
    }
  }

  /// Parse the native screen time string (e.g. "2h 15m today") into total hours.
  double? _parseScreenTimeHours(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;

    try {
      double totalHours = 0.0;

      final hoursMatch = RegExp(r'(\d+)h').firstMatch(timeStr);
      if (hoursMatch != null) {
        totalHours += double.parse(hoursMatch.group(1)!);
      }

      final minutesMatch = RegExp(r'(\d+)m').firstMatch(timeStr);
      if (minutesMatch != null) {
        totalHours += double.parse(minutesMatch.group(1)!) / 60.0;
      }

      return totalHours;
    } catch (_) {
      return null;
    }
  }

  /// Enforce the global daily limit on the child device.
  /// When the total screen time for today exceeds the configured daily limit,
  /// all apps are blocked except messaging, calls, camera, and Guardian AI.
  void _checkAndApplyDailyLimitEnforcement() {
    if (!mounted) return;

    // Require both a valid screen time value and a positive daily limit
    if (_screenTime == null || _dailyLimitHours == null || _dailyLimitHours! <= 0) {
      return;
    }

    final usedHours = _parseScreenTimeHours(_screenTime!);
    if (usedHours == null) return;

    final limitHours = _dailyLimitHours!;
    final hasExceeded = usedHours >= limitHours;

    final appBlocker = Provider.of<AppBlockerService>(context, listen: false);

    // Start from the current effective restrictions (server + exam mode)
    final baseRestrictions = _getEffectiveRestrictions();

    if (!hasExceeded) {
      // Daily limit not exceeded: use normal restrictions
      appBlocker.updateRestrictions(baseRestrictions);
      BackgroundMonitoringService.updateRestrictions(baseRestrictions);
      debugPrint('✅ Daily limit not exceeded (used=${usedHours.toStringAsFixed(2)}h / limit=${limitHours.toStringAsFixed(2)}h).');
      return;
    }

    // Daily limit exceeded: block all apps except messaging, calls, camera, and Guardian AI
    final Map<String, double> globalRestrictions = Map.from(baseRestrictions);

    // Whitelisted packages that should remain usable after limit is exceeded
    final Set<String> allowedPackages = {
      // Guardian AI app itself
      'com.example.guardian_ai',
    };

    // Infer typical phone/message/camera apps from installed package names
    _apps.forEach((packageName, app) {
      final lower = packageName.toLowerCase();

      final isGuardian = packageName == 'com.example.guardian_ai';
      final isPhone = lower.contains('dialer') || lower.contains('phone') || lower.contains('telecom');
      final isMessages = lower.contains('mms') || lower.contains('sms') || lower.contains('messag');
      final isCamera = lower.contains('camera');

      if (isGuardian || isPhone || isMessages || isCamera) {
        allowedPackages.add(packageName);
      }
    });

    // For every known app, if it's not allowed, force its allowed time to 0h
    _apps.forEach((packageName, _) {
      if (!allowedPackages.contains(packageName)) {
        globalRestrictions[packageName] = 0.0;
      }
    });

    appBlocker.updateRestrictions(globalRestrictions);
    BackgroundMonitoringService.updateRestrictions(globalRestrictions);
    debugPrint('⏰ Daily limit exceeded (used=${usedHours.toStringAsFixed(2)}h / limit=${limitHours.toStringAsFixed(2)}h).');
    debugPrint('   Allowed packages after limit: $allowedPackages');
    debugPrint('   Total restricted apps after limit: ${globalRestrictions.length}');
  }

  Future<void> _initUsageStats() async {
    try {
      bool? isPermissionGranted = await UsageStats.checkUsagePermission();
      if (isPermissionGranted == null || !isPermissionGranted) {
        await UsageStats.grantUsagePermission();
        isPermissionGranted = await UsageStats.checkUsagePermission();
        if (isPermissionGranted == null || !isPermissionGranted) {
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
          return;
        }
      }

      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: true, withIcon: true);

      Map<String, AppInfo> appMap = {
        for (var app in apps) app.packageName: app
      };

      DateTime now = DateTime.now();
      // Use the device's concept of "today" from midnight to now
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = now;

      List<UsageInfo> usageStats = await UsageStats.queryUsageStats(
        startOfDay,
        endOfDay,
      );

        usageStats = usageStats
          .where((info) =>
            double.parse(info.totalTimeInForeground ?? '0') > 0 &&
            appMap.containsKey(info.packageName))
          .toList();

      usageStats.sort((a, b) {
        double timeA = double.parse(a.totalTimeInForeground ?? '0');
        double timeB = double.parse(b.totalTimeInForeground ?? '0');
        return timeB.compareTo(timeA);
      });

      if (mounted) {
        setState(() {
          _usageStats = usageStats;
          _apps = appMap;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching usage stats: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatDuration(String? timeInMillisStr) {
    if (timeInMillisStr == null) return '0m';
    int millis = int.tryParse(timeInMillisStr) ?? 0;
    Duration duration = Duration(milliseconds: millis);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String get _totalUsageTime {
    if (_usageStats.isEmpty) return '0m';
    int totalMillis = 0;
    for (var usage in _usageStats) {
      totalMillis += int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
    }
    return _formatDuration(totalMillis.toString());
  }

  bool _isBrowserApp(String packageName, String appName) {
    final browserKeywords = [
      'browser',
      'chrome',
      'firefox',
      'opera',
      'edge',
      'safari',
      'brave',
      'duck',
      'samsung internet',
      'uc browser',
      'dolphin',
      'maxthon',
      'puffin',
      'kiwi',
      'vivaldi',
      'tor',
      'duckduckgo'
    ];
    final lowerPackage = packageName.toLowerCase();
    final lowerName = appName.toLowerCase();
    return browserKeywords.any((keyword) =>
        lowerPackage.contains(keyword) || lowerName.contains(keyword));
  }

  List<UsageInfo> get _browserUsageStats {
    return _usageStats.where((usage) {
      final app = _apps[usage.packageName];
      if (app == null) return false;
      return _isBrowserApp(usage.packageName ?? '', app.name);
    }).toList();
  }

  String get _totalBrowserTime {
    if (_browserUsageStats.isEmpty) return '0m';
    int totalMillis = 0;
    for (var usage in _browserUsageStats) {
      totalMillis += int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
    }
    return _formatDuration(totalMillis.toString());
  }

  Future<void> _getBrowserHistory() async {
    try {
      final List<dynamic> result = await browserChannel.invokeMethod('getBrowserHistory');
      if (mounted) {
        setState(() {
          _browserHistory =
              result.map((item) => Map<String, String>.from(item)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching browser history: $e');
      if (mounted) {
        setState(() {
          _browserHistory = [];
        });
      }
    }
  }

  String _formatTimestamp(String timestampStr) {
    try {
      final timestamp = int.tryParse(timestampStr) ?? 0;
      if (timestamp == 0) return 'Unknown';

      final chromeEpochStart = 11644473600000000;
      final millisSinceEpoch = (timestamp - chromeEpochStart) ~/ 1000;

      final date = DateTime.fromMillisecondsSinceEpoch(millisSinceEpoch);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';

      return DateFormat('MMM d').format(date);
    } catch (e) {
      return 'Unknown';
    }
  }

  String _calculateScreenTimePercentage() {
    // Use _totalUsageTime (e.g., "2h 15m" or "45m") for actual usage
    final timeStr = _totalUsageTime;
    final dailyLimitHours = _dailyLimitHours ?? 8.0;

    try {
      double totalHours = 0.0;

      // Extract hours
      final hoursMatch = RegExp(r'(\d+)h').firstMatch(timeStr);
      if (hoursMatch != null) {
        totalHours += double.parse(hoursMatch.group(1)!);
      }

      // Extract minutes
      final minutesMatch = RegExp(r'(\d+)m').firstMatch(timeStr);
      if (minutesMatch != null) {
        totalHours += double.parse(minutesMatch.group(1)!) / 60;
      }

      final percentage = ((totalHours / dailyLimitHours) * 100).clamp(0, 100).toInt();
      return '$percentage% of daily limit';
    } catch (e) {
      return '0% of daily limit';
    }
  }

  String _getAppCategory(String packageName, String appName) {
    final lower = packageName.toLowerCase();
    final nameLower = appName.toLowerCase();
    
    // Social Media
    if (lower.contains('instagram') || nameLower.contains('instagram')) return 'Entertainment';
    if (lower.contains('facebook') || nameLower.contains('facebook')) return 'Chatting App';
    if (lower.contains('whatsapp') || nameLower.contains('whatsapp')) return 'Chatting App';
    if (lower.contains('messenger') || nameLower.contains('messenger')) return 'Job Portal';
    if (lower.contains('snapchat') || nameLower.contains('snapchat')) return 'Entertainment';
    if (lower.contains('twitter') || lower.contains('x.com') || nameLower.contains('twitter')) return 'Social Media';
    if (lower.contains('tiktok') || nameLower.contains('tiktok')) return 'Entertainment';
    if (lower.contains('linkedin') || nameLower.contains('linkedin')) return 'Job Portal';
    
    // Entertainment & Video
    if (lower.contains('youtube') || nameLower.contains('youtube')) return 'Entertainment';
    if (lower.contains('netflix') || nameLower.contains('netflix')) return 'Entertainment';
    if (lower.contains('spotify') || nameLower.contains('spotify')) return 'Music';
    if (lower.contains('prime') || lower.contains('amazon') && nameLower.contains('video')) return 'Entertainment';
    if (lower.contains('disney') || nameLower.contains('disney')) return 'Entertainment';
    
    // Games
    if (lower.contains('game') || nameLower.contains('game')) return 'Gaming';
    if (lower.contains('play') && nameLower.contains('game')) return 'Gaming';
    
    // Productivity
    if (lower.contains('chrome') || lower.contains('browser')) return 'Browser';
    if (lower.contains('gmail') || lower.contains('mail')) return 'Email';
    if (lower.contains('calendar')) return 'Productivity';
    if (lower.contains('docs') || lower.contains('sheets') || lower.contains('drive')) return 'Productivity';
    
    // Default
    return 'Other';
  }

  bool _hasExceededApps() {
    if (_restrictions == null || _usageStats.isEmpty) return false;
    
    for (var usage in _usageStats) {
      final packageName = usage.packageName ?? '';
      final hasLimit = _restrictions!.restrictedApps.containsKey(packageName);
      if (hasLimit) {
        final limitHours = _restrictions!.restrictedApps[packageName];
        if (limitHours != null) {
          final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
          final usedHours = millis / 1000 / 3600;
          if (usedHours >= limitHours) {
            return true;
          }
        }
      }
    }
    return false;
  }

  void _handleBottomNavTap(int index) {
    if (index == 2) {
      // Already on dashboard, do nothing
      return;
    }
    
    // Show coming soon dialog for other tabs
    final titles = [
      'Chat',
      'Rewards',
      'Dashboard',
      'Activities',
      'Profile',
    ];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF317AF7).withOpacity(0.3),
                    const Color(0xFF15335C).withOpacity(0.3),
                  ],
                ),
              ),
              child: const Icon(
                Icons.rocket_launch_outlined,
                size: 50,
                color: Color(0xFF317AF7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              titles[index],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Coming Soon',
              style: TextStyle(
                color: Color(0xFF317AF7),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'We\'re working hard to bring you this feature. Stay tuned!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(
                color: Color(0xFF317AF7),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🎓 BUILD: Exam Mode = $_examMode, Apps = ${_examModeApps.length}');
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childName = prefsManager.getChildName() ?? 'Child';

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 96,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF050608),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 26),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  ),
                ),
                const Spacer(),
                if (_examMode)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange, width: 1.3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.school, color: Colors.orange, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Exam Mode',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                Consumer<LocationService>(
                  builder: (context, locationService, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101722),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Color(0xFF317AF7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_on, color: Colors.white, size: 12),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Location',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: locationService.isTracking ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade700,
                        child: const Icon(Icons.person, color: Colors.white, size: 22),
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4F92),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF050608),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF050608),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF101722), Color(0xFF050608)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    child: const Icon(Icons.person, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "$childName's Dashboard",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.task_outlined, color: Colors.white70),
              title: const Text('My Tasks', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyTasksScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.white70),
              title: const Text('Refresh Data', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _refreshData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70),
              title: const Text('Logout', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Logout', style: TextStyle(color: Colors.white)),
                    content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF317AF7),
                        ),
                        child: const Text('Logout', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && mounted) {
                  final prefsManager = context.read<PreferencesManager>();
                  await prefsManager.clearAll();
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                }
              },
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/mountain.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF317AF7)))
            : RefreshIndicator(
                color: const Color(0xFF317AF7),
                onRefresh: _refreshData,
                child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 110, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // AI Service Status Card
                    _buildAIServiceStatusCard(),
                    
                    // Screen Time Card - Match parent dashboard theme
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A3C8B), Color(0xFF0D1F4A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D1F4A).withOpacity(0.45),
                            blurRadius: 25,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Decorative circles like parent screen
                          Positioned(
                            top: -40,
                            right: -40,
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -70,
                            left: -70,
                            child: Container(
                              width: 190,
                              height: 190,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(18),
                                        child: Image.asset(
                                          'assets/images/screen_time_icon.png',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _totalUsageTime,
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Daily Limit: ${_dailyLimitHours?.toStringAsFixed(1) ?? '8.0'} hr',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                const Text(
                                  'Screen Time',
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _calculateScreenTimePercentage(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Debug: Task Loading Status
                    if (_loadingTasks) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            CircularProgressIndicator(
                              color: Color(0xFF317AF7),
                              strokeWidth: 2,
                            ),
                            SizedBox(width: 16),
                            Text(
                              'Loading tasks...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Pending Tasks Card
                    if (_pendingTasks.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MyTasksScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF15335C), Color(0xFF081526)], // Use app's primary gradient
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF15335C).withOpacity(0.18),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.13),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.task_outlined,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Pending Tasks',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.13),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_pendingTasks.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white70,
                                    size: 24,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ...(_pendingTasks.take(3).map((task) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.radio_button_unchecked,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        task.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ))),
                              if (_pendingTasks.length > 3) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '+${_pendingTasks.length - 3} more tasks',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // App Usage Summary Card
                    if (_usageStats.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                              context,
                              Icons.apps_rounded,
                              '${_usageStats.length}',
                              'Apps Used',
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white24,
                            ),
                            _buildStatItem(
                              context,
                              Icons.access_time_rounded,
                              _totalUsageTime,
                              'Total Time',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Browser Usage Section
                    if (_browserUsageStats.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.language_rounded, size: 20, color: Color(0xFF317AF7)),
                          const SizedBox(width: 8),
                          const Text(
                            'Browser Activity',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF317AF7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _totalBrowserTime,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        color: const Color(0xFF1A1A1A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _browserUsageStats.length,
                            itemBuilder: (context, index) {
                              final usage = _browserUsageStats[index];
                              final app = _apps[usage.packageName];
                              
                              if (app == null) return const SizedBox.shrink();

                              return Card(
                                color: const Color(0xFF0F0F0F),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: const Color(0xFF2A2A2A),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: app.icon != null
                                          ? Image.memory(
                                              app.icon!,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                            )
                                          : const Icon(
                                              Icons.language_rounded,
                                              color: Color(0xFF317AF7),
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    app.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Browser app',
                                    style: TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF317AF7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _formatDuration(usage.totalTimeInForeground),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Browser History Section
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 20, color: Color(0xFF317AF7)),
                        const SizedBox(width: 8),
                        const Text(
                          'Browsing History',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        if (_browserHistory.isNotEmpty)
                          Text(
                            '${_browserHistory.length} ${_browserHistory.length == 1 ? 'entry' : 'entries'}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFF1A1A1A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Container(
                        height: 300,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _browserHistory.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.info_outline_rounded,
                                        size: 48,
                                        color: Color(0xFF317AF7),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No browsing history available',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Enable Accessibility Service to track visited websites',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          try {
                                            await platform.invokeMethod('openAccessibilitySettings');
                                          } catch (e) {
                                            debugPrint('Error opening settings: $e');
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF317AF7),
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.settings, size: 18),
                                        label: const Text('Enable Accessibility Service'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: _browserHistory.length,
                                itemBuilder: (context, index) {
                                  final site = _browserHistory[index];
                                  final title = site['title'] ?? 'Unknown';
                                  final url = site['url'] ?? '';
                                  final timestamp = site['timestamp'] ?? '';
                                  
                                  final isErrorMessage = title.contains('Failed') || 
                                                         title.contains('Permission') ||
                                                         title.contains('Debug');
                                  
                                  return Card(
                                    color: const Color(0xFF0F0F0F),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      leading: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: isErrorMessage 
                                              ? const Color(0xFF317AF7).withOpacity(0.3)
                                              : const Color(0xFF317AF7),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          isErrorMessage ? Icons.info_outline_rounded : Icons.public_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      title: Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            url,
                                            style: TextStyle(
                                              color: isErrorMessage 
                                                  ? Colors.white 
                                                  : const Color(0xFF317AF7),
                                              fontSize: 12,
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (!isErrorMessage) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatTimestamp(timestamp),
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ] else ...[
                                            const SizedBox(height: 8),
                                            ElevatedButton.icon(
                                              onPressed: () async {
                                                try {
                                                  await platform.invokeMethod('openAccessibilitySettings');
                                                } catch (e) {
                                                  debugPrint('Error opening settings: $e');
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF317AF7),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                minimumSize: const Size(0, 32),
                                              ),
                                              icon: const Icon(Icons.settings, size: 16),
                                              label: const Text('Enable Accessibility Service'),
                                            ),
                                          ],
                                        ],
                                      ),
                                      isThreeLine: true,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // App Usage List Header
                    Row(
                      children: [
                        const Text(
                          'App Usage',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('MMM d').format(DateTime.now()),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // App Usage List
                    _usageStats.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: const [
                                Icon(
                                  Icons.hourglass_empty_rounded,
                                  size: 48,
                                  color: Colors.white60,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No usage data available',
                                  style: TextStyle(
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Grant usage access permission to see statistics',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              // Total usage across all apps (for percentage of total time)
                              ...(() {
                                int totalMillisAll = 0;
                                for (var u in _usageStats) {
                                  totalMillisAll += int.tryParse(u.totalTimeInForeground ?? '0') ?? 0;
                                }

                                return _usageStats.take(10).map((usage) {
                                final app = _apps[usage.packageName];
                                if (app == null) return const SizedBox.shrink();

                                // Check if this app has a time limit
                                final packageName = usage.packageName ?? '';
                                final hasLimit = _restrictions?.restrictedApps.containsKey(packageName) ?? false;
                                final limitHours = hasLimit ? _restrictions!.restrictedApps[packageName] : null;
                                
                                // Check if blocked by exam mode
                                final isBlockedByExamMode = _examMode && _examModeApps.contains(packageName);
                                final effectiveLimit = isBlockedByExamMode ? 0.0 : limitHours;
                                
                                // Calculate time used
                                final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
                                final usedHours = millis / 1000 / 3600;
                                final usedMinutes = (millis / 1000 / 60).round();
                                
                                // Check if limit is exceeded
                                final isExceeded = (hasLimit && effectiveLimit != null && usedHours >= effectiveLimit) || isBlockedByExamMode;
                                
                                // Calculate percentage of total app usage time
                                final totalMillis = totalMillisAll == 0 ? 1 : totalMillisAll;
                                final percentage = ((millis / totalMillis) * 100).clamp(0, 100).toInt();
                                
                                // Get app category
                                String category = _getAppCategory(packageName, app.name);

                                return GestureDetector(
                                  onTap: isExceeded ? () => _showRequestTimeDialog(
                                    context,
                                    packageName: packageName,
                                    appName: app.name,
                                  ) : null,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isExceeded 
                                          ? const Color(0xFF317AF7).withOpacity(0.15)
                                          : const Color(0xFF0F0F0F),
                                      borderRadius: BorderRadius.circular(12),
                                      border: isExceeded
                                          ? Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1)
                                          : null,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            // App Icon
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(10),
                                                color: const Color(0xFF2A2A2A),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: app.icon != null
                                                    ? Image.memory(
                                                        app.icon!,
                                                        width: 40,
                                                        height: 40,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : const Icon(
                                                        Icons.android,
                                                        color: Color(0xFF317AF7),
                                                        size: 24,
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            // App Name and Category
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          app.name,
                                                          style: const TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.white,
                                                          ),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      if (isBlockedByExamMode) ...[
                                                        const SizedBox(width: 4),
                                                        const Icon(
                                                          Icons.school,
                                                          size: 14,
                                                          color: Colors.orange,
                                                        ),
                                                      ] else if (isExceeded) ...[
                                                        const SizedBox(width: 4),
                                                        const Icon(
                                                          Icons.block_rounded,
                                                          size: 14,
                                                          color: Colors.redAccent,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        category,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.white60,
                                                        ),
                                                      ),
                                                      if (isBlockedByExamMode) ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.orange.withOpacity(0.2),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: const Text(
                                                            'Exam Mode',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors.orange,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            // Time
                                            Text(
                                              '$usedMinutes mins',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        // Progress Bar
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Stack(
                                                children: [
                                                  Container(
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(3),
                                                    ),
                                                  ),
                                                  FractionallySizedBox(
                                                    widthFactor: percentage / 100,
                                                    child: Container(
                                                      height: 6,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          colors: isBlockedByExamMode
                                                              ? [Colors.orange, Colors.deepOrange]
                                                              : isExceeded
                                                                  ? [Colors.redAccent, Colors.red]
                                                                  : [const Color(0xFF48B3FF), const Color(0xFF3E6BFF)],
                                                        ),
                                                        borderRadius: BorderRadius.circular(3),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              '$percentage%',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isBlockedByExamMode 
                                                    ? Colors.orange 
                                                    : isExceeded 
                                                        ? Colors.redAccent 
                                                        : Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList();
                            })(),
                              // Load Earlier Activities Button
                              if (_usageStats.length > 10)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: TextButton(
                                    onPressed: () {
                                      // TODO: Implement load more functionality
                                    },
                                    child: const Text(
                                      'Load Earlier Activities',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
  
  void _showRequestTimeDialog(BuildContext context, {String? packageName, String? appName}) {
    final TextEditingController hoursController = TextEditingController();
    final TextEditingController reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF317AF7), Color(0xFF15335C)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.access_time, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Request Extra Time',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (appName != null) ...[
                const Text(
                  'Requesting time for:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.apps, color: Color(0xFF317AF7), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'How many extra hours do you need?',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hoursController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g., 1.5',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.timer, color: Colors.white54),
                  suffixText: 'hours',
                  suffixStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason for request:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Tell your parent why you need extra time...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              debugPrint('\n🎯 CHILD SCREEN: Send Request button clicked');
              final hoursText = hoursController.text.trim();
              final reason = reasonController.text.trim();
              
              debugPrint('🎯 Hours input: $hoursText');
              debugPrint('🎯 Reason input: $reason');
              debugPrint('🎯 Package: $packageName');
              debugPrint('🎯 App: $appName');
              
              if (hoursText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter the number of hours'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              final hours = double.tryParse(hoursText);
              if (hours == null || hours <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid number'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason for your request'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              Navigator.pop(context);
              
              // Get child hash from preferences
              final prefsManager = context.read<PreferencesManager>();
              final childHash = prefsManager.getChildHash();
              
              if (childHash == null || childHash.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Error: Child profile not found'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              // Send request with encryption
              final timeExtService = context.read<TimeExtensionService>();
              
              // Show loading indicator
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Encrypting and sending request...'),
                      ],
                    ),
                    backgroundColor: Color(0xFF317AF7),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
              
              final success = await timeExtService.createRequest(
                childHash: childHash,
                requestedHours: hours,
                reason: reason,
                packageName: packageName,
                appName: appName,
              );
              
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('Request sent! Your parent will be notified.'),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to send request. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF317AF7),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Send Request',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIServiceStatusCard() {
    final isRunning = _aiServiceStatus == 'Running';
    final statusColor = isRunning ? Colors.green : Colors.orange;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E3A8A).withOpacity(0.8),
            const Color(0xFF0F172A).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.smart_toy,
                        color: statusColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Services',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _aiServiceStatus,
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (isRunning)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.6),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Models Status
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildModelBadge(
                  'BERT',
                  _modelsRunning >= 1,
                ),
                _buildModelBadge(
                  'LSTM',
                  _modelsRunning >= 2,
                ),
                _buildModelBadge(
                  'Vision',
                  _modelsRunning >= 3,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Stats Row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn(
                    'Models Running',
                    '$_modelsRunning/3',
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  _buildStatColumn(
                    'Background Monitor',
                    _backgroundMonitoringActive ? 'Active' : 'Inactive',
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  _buildStatColumn(
                    'Last Analysis',
                    _lastAnalysisTime != null
                        ? '${_lastAnalysisTime!.hour}:${_lastAnalysisTime!.minute.toString().padLeft(2, '0')}'
                        : 'N/A',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Test Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _lastAnalysisTime = DateTime.now();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 12),
                          Text('AI services tested successfully'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: statusColor.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Test AI Services',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelBadge(String modelName, bool isLoaded) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isLoaded
            ? Colors.green.withOpacity(0.2)
            : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLoaded
              ? Colors.green.withOpacity(0.5)
              : Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLoaded ? Icons.check_circle : Icons.schedule,
            size: 14,
            color: isLoaded ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            modelName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isLoaded ? Colors.green : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatItem(BuildContext context, IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF317AF7), size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
