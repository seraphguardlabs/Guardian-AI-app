import 'package:flutter/material.dart';
import '../utils/app_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:convert';
import 'package:usage_stats/usage_stats.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../utils/preferences_manager.dart';
import '../utils/app_theme.dart';
import '../services/location_service.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../services/encryption_service.dart';
import '../services/app_blocker_service.dart';
import '../services/background_monitoring_service.dart';
import '../services/location_background_service.dart';
import '../services/time_extension_service.dart';
import '../services/screen_monitoring_service.dart';
import '../services/realtime_alert_service.dart';
import '../services/chat_service.dart';
import '../models/restrictions_data.dart';
import '../models/task.dart';
import '../models/alert.dart';
import '../models/content_analysis_result.dart';
import '../widgets/app_bottom_nav.dart';
import 'my_tasks_screen.dart';
import '../services/gemma_manager.dart';
import 'log_viewer_screen.dart';

import '../widgets/time_request_dialog.dart';

class ChildScreen extends StatefulWidget {
  const ChildScreen({super.key});

  @override
  State<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends State<ChildScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const platform = MethodChannel('com.guardian_ai/screen_time');
  static const browserChannel = MethodChannel('com.guardian_ai/browser_history');
  String _screenTime = 'Unknown';
  int? _screenTimeSeconds;
  Map<String, int> _nativeAppUsageSeconds = {};
  double? _dailyLimitHours; // Global daily limit from server or default
  bool _loading = true;
  List<UsageInfo> _usageStats = [];
  Map<String, AppInfo> _apps = {};
  List<Map<String, String>> _browserHistory = [];
  Timer? _refreshTimer;
  RestrictionsData? _restrictions;
  StreamSubscription<Map<String, dynamic>>? _wsMessageSubscription;
  StreamSubscription<Map<String, dynamic>>? _timeExtResponseSubscription;
  bool _examMode = false;
  List<String> _examModeApps = [];
  List<Task> _pendingTasks = [];
  bool _loadingTasks = false;
  Position? _lastSentPosition;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final AnimationController _loadingPulseController;

  // ── Permission gate ──────────────────────────────────────────────────────
  bool _awaitingPermissions    = true;
  bool _locationGranted        = false;
  bool _usageStatsGranted      = false;
  bool _accessibilityGranted   = false;
  bool _screenCaptureGranted   = false;
  // Per-row loading spinners — one per permission
  bool _locationLoading        = false;
  bool _usageLoading           = false;
  bool _accessibilityLoading   = false;
  bool _screenCaptureLoading   = false;
  
  // AI Model status
  bool _modelInstalled = false;
  bool _isDownloadingModel = false;
  double _downloadProgress = 0.0;
  String _modelStatus = '';
  StreamSubscription? _modelStatusSub;
  StreamSubscription? _modelProgressSub;
  
  // Background AI monitoring
  StreamSubscription? _bgAlertSub;
  bool _aiMonitoringActive = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entranceFade = CurvedAnimation(parent: _entranceController, curve: Curves.easeOut);
    _loadingPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // ⚠️  Do NOT start any service or load any data until permissions pass.
    // Everything is gated through _initPermissionGate().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPermissionGate();
      _initModelStatus();
    });
  }
  
  void _initModelStatus() async {
    final installed = await GemmaManager.instance.isModelInstalled();
    setState(() {
      _modelInstalled = installed;
      _modelStatus = installed ? 'Installed' : 'Not installed';
    });
    
    // If model is already installed, start AI monitoring immediately
    if (installed && !_awaitingPermissions) {
      _startAIMonitoring();
    }
    
    _modelStatusSub = GemmaManager.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _modelStatus = status;
          if (status.contains('Failed') || status.contains('Error')) {
            _isDownloadingModel = false;
            _downloadProgress = 0.0;
          }
        });
      }
    });
    
    _modelProgressSub = GemmaManager.instance.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
           // Only update progress if we didn't just fail
          if (!_modelStatus.contains('Failed') && !_modelStatus.contains('Error')) {
            _downloadProgress = progress;
            if (progress >= 1.0) {
               _isDownloadingModel = false;
               _modelInstalled = true;
               // Model just finished downloading — check if we can proceed
               if (_locationGranted && _usageStatsGranted && _accessibilityGranted && _screenCaptureGranted) {
                 _awaitingPermissions = false;
                 _startServicesAndLoad();
               }
            }
          }
        });
      }
    });
  }

  // ── Permission gate ──────────────────────────────────────────────────────

  /// Re-check permissions whenever the app returns to foreground
  /// (e.g. user comes back from System Settings).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_awaitingPermissions) {
        _checkAllPermissions().then((_) {
          if (_locationGranted && _usageStatsGranted && _accessibilityGranted && _screenCaptureGranted && _modelInstalled) {
            if (mounted) setState(() => _awaitingPermissions = false);
            _startServicesAndLoad();
          }
        });
      }
      // Also re-check model status
      GemmaManager.instance.isModelInstalled().then((installed) {
        if (mounted) {
          setState(() => _modelInstalled = installed);
          if (installed && !_awaitingPermissions) {
            // Model was installed externally, update state
          } else if (installed && _locationGranted && _usageStatsGranted && _accessibilityGranted && _screenCaptureGranted) {
            setState(() => _awaitingPermissions = false);
            _startServicesAndLoad();
          }
        }
      });
    }
  }

  Future<void> _initPermissionGate() async {
    if (!mounted) return;
    await _checkAllPermissions();
    if (_locationGranted && _usageStatsGranted && _accessibilityGranted && _screenCaptureGranted) {
      if (_modelInstalled) {
        _startServicesAndLoad();
      }
    }
  }

  /// Silently checks current permission state (no dialogs).
  Future<void> _checkAllPermissions() async {
    // Location
    final locStatus = await Permission.locationWhenInUse.status;
    final locGranted = locStatus.isGranted || locStatus.isLimited;

    // Usage stats (PACKAGE_USAGE_STATS) — checked via UsageStats
    bool? usageGranted = await UsageStats.checkUsagePermission();

    // Accessibility service (WebsiteMonitoringService)
    bool accessGranted = false;
    try {
      final result = await platform.invokeMethod<bool>('isAccessibilityServiceEnabled');
      accessGranted = result == true;
    } catch (_) {}

    // Screen capture — check persisted preference OR running service
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    bool captureGranted = prefs.isScreenCaptureGranted();
    if (!captureGranted) {
      try {
        final result = await ScreenMonitoringService.platform.invokeMethod<bool>('isCapturing');
        captureGranted = result == true;
      } catch (_) {
        // isCapturing may not exist yet — keep previous state
      }
    }

    if (mounted) {
      setState(() {
        _locationGranted      = locGranted;
        _usageStatsGranted    = usageGranted == true;
        _accessibilityGranted = accessGranted;
        _screenCaptureGranted = captureGranted;
        _awaitingPermissions  =
            !(_locationGranted && _usageStatsGranted && _accessibilityGranted && _screenCaptureGranted)
            || !_modelInstalled;
      });
    }
  }

  // ── Individual permission handlers (each row calls its own) ────────────

  Future<void> _requestLocation() async {
    if (_locationGranted || _locationLoading) return;
    setState(() => _locationLoading = true);

    // Show the system dialog directly — no Settings redirect needed for fine location
    final status = await Permission.locationWhenInUse.request();
    final granted = status.isGranted || status.isLimited;

    // Best-effort background location request right after
    if (granted) {
      final bgStatus = await Permission.locationAlways.status;
      if (!bgStatus.isGranted) await Permission.locationAlways.request();
    }

    if (mounted) setState(() { _locationGranted = granted; _locationLoading = false; });
    _checkIfAllGranted();
  }

  Future<void> _requestUsageAccess() async {
    if (_usageStatsGranted || _usageLoading) return;
    setState(() => _usageLoading = true);

    // Opens the Usage Access system settings page directly
    await UsageStats.grantUsagePermission();
    // Re-check happens in didChangeAppLifecycleState on return
    if (mounted) setState(() => _usageLoading = false);
  }

  Future<void> _requestAccessibility() async {
    if (_accessibilityGranted || _accessibilityLoading) return;
    setState(() => _accessibilityLoading = true);

    // Opens Accessibility Settings directly
    try { await platform.invokeMethod('openAccessibilitySettings'); } catch (_) {}
    // Re-check happens in didChangeAppLifecycleState on return
    if (mounted) setState(() => _accessibilityLoading = false);
  }

  Future<void> _requestScreenCapture() async {
    if (_screenCaptureGranted || _screenCaptureLoading) return;
    setState(() => _screenCaptureLoading = true);

    try {
      // Initialize the monitoring service first if needed
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      final childHash = prefs.getChildHash() ?? '';
      final screenMonitoring = ScreenMonitoringService.instance;
      
      if (!screenMonitoring.isInitialized) {
        await screenMonitoring.initialize(
          childHash: childHash,
          childName: 'Child',
        );
      }
      
      // This triggers the Android MediaProjection permission dialog
      final result = await ScreenMonitoringService.platform.invokeMethod('requestPermission');
      final granted = result == true;
      
      // Persist the permission state so it survives app restarts
      if (granted) {
        final prefs = Provider.of<PreferencesManager>(context, listen: false);
        await prefs.setScreenCaptureGranted(true);
      }
      
      if (mounted) {
        setState(() {
          _screenCaptureGranted = granted;
          _screenCaptureLoading = false;
        });
      }
      _checkIfAllGranted();
    } on PlatformException catch (e) {
      AppLogger.log('❌ Screen capture permission error: ${e.message}');
      if (mounted) setState(() => _screenCaptureLoading = false);
    } catch (e) {
      AppLogger.log('❌ Screen capture permission error: $e');
      if (mounted) setState(() => _screenCaptureLoading = false);
    }
  }

  void _checkIfAllGranted() {
    final allPermsGranted = _locationGranted && _usageStatsGranted && _accessibilityGranted && _screenCaptureGranted;
    if (allPermsGranted) {
      // Auto-trigger model download if not yet installed
      if (!_modelInstalled && !_isDownloadingModel) {
        _autoStartModelDownload();
      }
      if (_modelInstalled) {
        if (mounted) setState(() => _awaitingPermissions = false);
        _startServicesAndLoad();
      }
    }
  }

  /// Auto-start AI model download once all permissions pass
  void _autoStartModelDownload() {
    if (_isDownloadingModel || _modelInstalled) return;
    AppLogger.log('🤖 Auto-starting AI model download...');
    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = 0.0;
    });
    GemmaManager.instance.downloadModel();
  }

  /// Called only after all permissions are confirmed.  Mirrors what initState
  /// previously did immediately (and unsafely).
  void _startServicesAndLoad() async {
    if (!mounted) return;
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    prefs.setViewMode('child');
    prefs.setLastRoute('/child');

    // Start native foreground services — safe now that permissions exist
    try {
      await BackgroundMonitoringService.start();
      AppLogger.log('✅ BackgroundMonitoringService started');
    } catch (e) {
      AppLogger.log('❌ Error starting BackgroundMonitoringService: $e');
    }
    
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
        AppLogger.log('✅ FlutterBackgroundService started');
      }
    } catch (e) {
      AppLogger.log('❌ Error starting FlutterBackgroundService: $e');
    }
    
    try {
      await LocationBackgroundService.start();
    } catch (e) {
      AppLogger.log('❌ Error starting LocationBackgroundService: $e');
    }

    // Start data loading
    _refreshData();
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 30), (_) => _refreshData());

    // Network + server calls
    _uploadChildPublicKey();
    final locationService = Provider.of<LocationService>(context, listen: false);
    locationService.startTracking();
    _initializeWebSocket();
    _fetchRestrictions();
    _fetchExamMode();
    _loadDailyLimit();
    _loadPendingTasks();
    _initializeBackgroundServices();
  }

  Future<void> _uploadChildPublicKey() async {
    AppLogger.log('🔐 Child Screen: Uploading child public key to server...');
    
    // Initialize encryption service if not already done
    if (!EncryptionService.instance.isInitialized) {
      await EncryptionService.instance.initialize();
    }
    
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash();
    
    if (childHash == null || childHash.isEmpty) {
      AppLogger.log('⚠️ Child Screen: No child hash available');
      return;
    }
    
    if (EncryptionService.instance.hasKeys && EncryptionService.instance.publicKey != null) {
      final apiService = ApiService();
      final result = await apiService.uploadChildPublicKey(
        childHash: childHash,
        publicKey: EncryptionService.instance.publicKey!,
      );
      
      if (result['success'] == true) {
        AppLogger.log('✅ Child Screen: Child public key uploaded successfully');
      } else {
        AppLogger.log('❌ Child Screen: Failed to upload child public key: ${result['error']}');
      }
    } else {
      AppLogger.log('⚠️ Child Screen: No encryption keys available');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entranceController.dispose();
    _loadingPulseController.dispose();
    _refreshTimer?.cancel();
    _wsMessageSubscription?.cancel();
    _timeExtResponseSubscription?.cancel();
    _modelStatusSub?.cancel();
    _modelProgressSub?.cancel();
    _bgAlertSub?.cancel();
    final locationService = Provider.of<LocationService>(context, listen: false);
    locationService.stopTracking();
    super.dispose();
  }

  Future<void> _refreshData() async {
    try {
      await Future.wait([
        _getScreenTime(),
        _initUsageStats(),
        _getBrowserHistory(),
        _loadPendingTasks(),
        _fetchRestrictions(),
      ]).timeout(const Duration(seconds: 15));
    } catch (e) {
      AppLogger.log('⚠️ Error or timeout in _refreshData: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
      _sendDataViaWebSocket();
      if (!_entranceController.isCompleted) _entranceController.forward();
    }
  }

  Future<void> _initializeWebSocket() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();

    if (childHash != null && childHash.isNotEmpty) {
      final wsService = Provider.of<WebSocketService>(context, listen: false);
      await wsService.connect(childHash);
      AppLogger.log('🔌 WebSocket connected for child: $childHash');

      _wsMessageSubscription = wsService.messages.listen((message) {
        if (message['type'] == 'restrictions_update') {
          AppLogger.log('🚫 Received restrictions update via WebSocket');
          _fetchRestrictions();
          AppLogger.log('🎓 Fetching exam mode after WebSocket restrictions update');
          _fetchExamMode(); // Also check exam mode when restrictions update
        }
      });

      // Connect the child-side time-extension WebSocket and listen for
      // approved / denied responses so we can re-fetch restrictions immediately.
      final timeExtService = Provider.of<TimeExtensionService>(context, listen: false);
      timeExtService.connectChildSocket(childHash: childHash);
      _timeExtResponseSubscription = timeExtService.childResponseStream.listen((data) {
        final type = data['type'] as String? ?? '';
        if (type == 'time_extension_response') {
          final d = data['data'] as Map<String, dynamic>? ?? {};
          final status = d['status'] as String? ?? '';
          if (status == 'approved') {
            AppLogger.log('⏰ Time extension approved — refreshing restrictions');
            _fetchRestrictions();
          }
        } else if (type == 'task_auto_approved') {
          AppLogger.log('🎉 Task completed & auto-approved — refreshing restrictions');
          _fetchRestrictions();
        }
      });
    } else {
      AppLogger.log('⚠️ No child hash found, skipping WebSocket connection');
    }
  }

  Future<void> _fetchRestrictions() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();

    if (childHash == null || childHash.isEmpty) {
      AppLogger.log('⚠️ No child hash, skipping restrictions fetch');
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
      AppLogger.log('✅ Restrictions updated: ${_restrictions!.restrictedApps.length} apps');

      // Fetch exam mode to get the combined restrictions
      await _fetchExamMode();

      final appBlocker = Provider.of<AppBlockerService>(context, listen: false);
      appBlocker.updateRestrictions(_getEffectiveRestrictions());
      BackgroundMonitoringService.updateRestrictions(_getEffectiveRestrictions());
    }
  }

  Future<void> _fetchExamMode() async {
    AppLogger.log('\n🎓 ===== FETCHING EXAM MODE =====');
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();
    final parentEmail = prefsManager.getParentEmail();
    final parentPassword = prefsManager.getParentPassword();

    AppLogger.log('🎓 Child hash: $childHash');
    AppLogger.log('🎓 Parent email available: ${parentEmail?.isNotEmpty ?? false}');
    AppLogger.log('🎓 Parent password available: ${parentPassword?.isNotEmpty ?? false}');

    if (childHash == null || childHash.isEmpty) {
      AppLogger.log('⚠️ No child hash, skipping exam mode fetch');
      return;
    }

    if (parentEmail == null || parentPassword == null) {
      AppLogger.log('⚠️ No parent credentials found, skipping exam mode fetch');
      return;
    }

    AppLogger.log('🎓 Calling API: GET /api/mobile/child/$childHash/exam-mode/');
    final apiService = Provider.of<ApiService>(context, listen: false);
    final result = await apiService.getExamMode(
      email: parentEmail,
      password: parentPassword,
      childHash: childHash,
    );

    AppLogger.log('🎓 API Response: $result');
    AppLogger.log('🎓 Success: ${result['success']}');
    AppLogger.log('🎓 Data: ${result['data']}');

    if (result['success'] == true && mounted) {
      final data = result['data'] as Map<String, dynamic>;
      final examModeValue = data['exam_mode'] ?? false;
      final examModeAppsList = List<String>.from(data['exam_mode_apps'] ?? []);
      
      AppLogger.log('🎓 Parsed exam_mode: $examModeValue (type: ${examModeValue.runtimeType})');
      AppLogger.log('🎓 Parsed exam_mode_apps: $examModeAppsList');
      
      setState(() {
        _examMode = examModeValue;
        _examModeApps = examModeAppsList;
      });
      
      AppLogger.log('✅ EXAM MODE STATE UPDATED:');
      AppLogger.log('   - Exam Mode Active: $_examMode');
      AppLogger.log('   - Blocked Apps Count: ${_examModeApps.length}');
      AppLogger.log('   - Blocked Apps: $_examModeApps');
    } else {
      AppLogger.log('❌ Failed to fetch exam mode or widget not mounted');
      AppLogger.log('   - Success: ${result['success']}');
      AppLogger.log('   - Mounted: $mounted');
      AppLogger.log('   - Error: ${result['error']}');
    }
    AppLogger.log('🎓 ===== EXAM MODE FETCH COMPLETE =====\n');
  }

  Map<String, double> _getEffectiveRestrictions() {
    if (_restrictions == null) return {};
    
    final effective = Map<String, double>.from(_restrictions!.restrictedApps);
    
    // If exam mode is active, set exam mode apps to 0 hours
    if (_examMode) {
      for (final packageName in _examModeApps) {
        effective[packageName] = 0.0;
        AppLogger.log('🎓 Exam mode: Blocking $packageName');
      }
    }
    
    return effective;
  }

  Future<void> _sendDataViaWebSocket() async {
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    if (!wsService.isConnected) {
      AppLogger.log('⚠️ WebSocket not connected, skipping data send');
      return;
    }

    await _sendScreenTimeData();
    await _sendLocationData();
    await _sendWebsiteData();
  }

  Future<void> _sendScreenTimeData() async {
    if (_usageStats.isEmpty && _nativeAppUsageSeconds.isEmpty) return;

    final wsService = Provider.of<WebSocketService>(context, listen: false);

    int totalSeconds = 0;
    final appWiseData = <String, Map<String, int>>{};
    final hour = DateTime.now().hour.toString().padLeft(2, '0');

    if (_nativeAppUsageSeconds.isNotEmpty) {
      for (final entry in _nativeAppUsageSeconds.entries) {
        final seconds = entry.value;
        if (seconds <= 0) continue;
        totalSeconds += seconds;
        appWiseData[entry.key] = {hour: seconds};
      }
    } else {
      for (var usage in _usageStats) {
        final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
        final seconds = millis ~/ 1000;
        if (seconds <= 0) continue;
        totalSeconds += seconds;
        final packageName = usage.packageName ?? 'unknown';
        appWiseData[packageName] = {hour: seconds};
      }
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final tzName = DateTime.now().timeZoneName;

    await wsService.sendScreenTime(
      date: dateStr,
      totalScreenTime: totalSeconds,
      appWiseData: appWiseData,
      timezoneOffsetMinutes: tzOffsetMinutes,
      timezoneName: tzName,
    );

    AppLogger.log('📱 Sent screen time: ${totalSeconds}s, ${appWiseData.length} apps');
  }

  Future<void> _sendLocationData() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    final currentPosition = locationService.currentPosition;
    if (currentPosition != null) {
      // Check if we have moved at least 5 meters since last update
      if (_lastSentPosition != null) {
        double distance = Geolocator.distanceBetween(
          _lastSentPosition!.latitude,
          _lastSentPosition!.longitude,
          currentPosition.latitude,
          currentPosition.longitude,
        );

        if (distance < 5.0) {
          AppLogger.log('📍 Location update skipped: Only moved ${distance.toStringAsFixed(2)}m');
          return;
        }
      }

      await wsService.sendLocation(
        timestamp: DateTime.now().toUtc().toIso8601String(),
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
      );

      _lastSentPosition = currentPosition;
      AppLogger.log('📍 Sent location: ${currentPosition.latitude}, ${currentPosition.longitude}');
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

    AppLogger.log('🌐 Sent ${logs.length} website visits');
  }

  Future<void> _getScreenTime() async {
    String screenTime = 'Unknown';
    int? totalSeconds;
    Map<String, int> perAppSeconds = {};

    try {
      final dynamic details = await platform.invokeMethod('getScreenTimeDetails');
      if (details is Map) {
        final dynamic total = details['totalSeconds'];
        if (total is num) {
          totalSeconds = total.toInt();
        }
        final dynamic perApp = details['perAppSeconds'];
        if (perApp is Map) {
          perAppSeconds = perApp.map((key, value) {
            final pkg = key.toString();
            final seconds = (value is num) ? value.toInt() : 0;
            return MapEntry(pkg, seconds);
          });
        }
      }
    } on PlatformException catch (_) {
      // Fall back to legacy method below.
    } catch (_) {
      // Fall back to legacy method below.
    }

    if (totalSeconds != null) {
      screenTime = '${_formatDurationFromSeconds(totalSeconds)} today';
    } else {
      try {
        final String result = await platform.invokeMethod('getScreenTime');
        screenTime = result;
      } on PlatformException catch (e) {
        screenTime = "Failed to get screen time: '${e.message}'.";
      }
    }

    if (!mounted) return;

    setState(() {
      _screenTime = screenTime;
      _screenTimeSeconds = totalSeconds;
      _nativeAppUsageSeconds = perAppSeconds;
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
      AppLogger.log('🧒 Child screen daily limit hours: $_dailyLimitHours');
    });
    // After loading the daily limit, check enforcement with the latest screen time
    _checkAndApplyDailyLimitEnforcement();
  }

  Future<void> _loadPendingTasks() async {
    AppLogger.log('📋 Child Screen: Loading pending tasks...');
    setState(() => _loadingTasks = true);

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash() ?? '';

    AppLogger.log('📋 ========== CHILD_SCREEN LOAD TASKS ==========');
    AppLogger.log('📋 Child Hash: ${childHash.isEmpty ? "EMPTY" : childHash}');

    if (childHash.isEmpty) {
      AppLogger.log('📋 ❌ CANNOT LOAD TASKS: Child Hash is empty');
      setState(() => _loadingTasks = false);
      return;
    }

    AppLogger.log('📋 ✅ Child Hash OK, calling API...');
    final apiService = ApiService();
    final result = await apiService.getMyTasks(
      childHash: childHash,
      completed: 'false', // Only get pending tasks
    );

    AppLogger.log('📋 API Result success: ${result['success']}');
    AppLogger.log('📋 API Result: $result');

    if (!mounted) {
      AppLogger.log('📋 ⚠️ Widget not mounted, cannot update state');
      return;
    }

    if (result['success'] == true) {
      List<Task> tasks = result['tasks'] as List<Task>;
      AppLogger.log('📋 ✅ Received ${tasks.length} tasks from API');
      AppLogger.log('📋 Tasks: ${tasks.map((t) => t.id).toList()}');
      

      // Decrypt task titles and descriptions
      final encryptionService = EncryptionService.instance;
      AppLogger.log('📋 Starting decryption...');
      List<Task> decryptedTasks = tasks.map((task) {
        String? decryptedTitle;
        String? decryptedDescription;
        
        try {
          if (task.title.isNotEmpty) {
            decryptedTitle = encryptionService.decryptWithPrivateKey(task.title);
          }
        } catch (e) {
          AppLogger.log('⚠️ Decryption failed for title (Task ${task.id}): $e');
          decryptedTitle = task.title; // Fallback to raw title
        }
        
        try {
          if (task.description.isNotEmpty) {
            decryptedDescription = encryptionService.decryptWithPrivateKey(task.description);
          }
        } catch (e) {
          AppLogger.log('⚠️ Decryption failed for description (Task ${task.id}): $e');
          decryptedDescription = task.description; // Fallback to raw description
        }
        
        AppLogger.log('📋 Task ${task.id}: decrypted=${decryptedTitle != task.title}');
        
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
      }).toList();
      
      AppLogger.log('📋 ✅ Successfully loaded ${decryptedTasks.length} pending tasks');
      setState(() {
        _pendingTasks = decryptedTasks;
        _loadingTasks = false;
      });
      AppLogger.log('📋 State updated: _pendingTasks.length = ${_pendingTasks.length}');
    } else {
      AppLogger.log('📋 ❌ Failed to load tasks: ${result['error']}');
      setState(() => _loadingTasks = false);
    }
  }

  Future<void> _initializeBackgroundServices() async {
    AppLogger.log('🤖 Child Screen: Initializing Monitoring Services...');
    if (!mounted) return;
    
    try {
      // Initialize ScreenMonitoringService
      AppLogger.log('  📸 Initializing ScreenMonitoringService...');
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      final childHash = prefs.getChildHash() ?? '';
      final childName = 'Child'; 
      
      final screenMonitoring = ScreenMonitoringService.instance;
      final monitoringInitialized = await screenMonitoring.initialize(
        childHash: childHash,
        childName: childName,
      );
      
      if (!monitoringInitialized) {
        AppLogger.log('❌ ScreenMonitoringService initialization failed');
        return;
      }
      // Initialize RealtimeAlertService with a database
      await _initializeAlertService(childHash, childName);

      // If model is already installed, start monitoring now
      if (_modelInstalled) {
        _startAIMonitoring();
      } else {
        AppLogger.log('⏳ AI model not installed yet — monitoring will start after download');
      }
      
      AppLogger.log('✅ Monitoring Services initialized');
    } catch (e, stackTrace) {
      AppLogger.log('❌ Error initializing Services: $e');
      AppLogger.log('Stack trace: $stackTrace');
    }
  }
  
  /// Initialize the RealtimeAlertService with SQLite database
  Future<void> _initializeAlertService(String childHash, String childName) async {
    try {
      final dbPath = await getDatabasesPath();
      final db = await openDatabase(
        '$dbPath/alerts.db',
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS alerts (
              id TEXT PRIMARY KEY,
              timestamp TEXT NOT NULL,
              risk_score INTEGER NOT NULL,
              summary TEXT NOT NULL,
              severity TEXT NOT NULL,
              content_type TEXT NOT NULL,
              detected_content TEXT,
              child_hash TEXT NOT NULL,
              child_name TEXT NOT NULL,
              created_at TEXT NOT NULL,
              source TEXT NOT NULL
            )
          ''');
        },
      );
      
      final wsService = Provider.of<WebSocketService>(context, listen: false);
      await RealtimeAlertService.instance.initialize(db, wsService);
      RealtimeAlertService.instance.setCurrentChild(childHash, childName);
      AppLogger.log('✅ RealtimeAlertService initialized');
    } catch (e) {
      AppLogger.log('⚠️ RealtimeAlertService init failed: $e');
    }
  }

  /// Start AI monitoring: screen capture service + background service + alert listener
  Future<void> _startAIMonitoring() async {
    if (_aiMonitoringActive) return;
    if (!_modelInstalled) return;
    
    AppLogger.log('🧠 Starting AI monitoring pipeline...');
    
    try {
      // 1. Now that AI is ready, actually start the native ScreenCaptureService.
      //    Permission was already granted earlier and stored; this triggers the service.
      try {
        final captureStarted = await ScreenMonitoringService.platform.invokeMethod('startCapture');
        AppLogger.log('  📸 Native screen capture service started: $captureStarted');
      } catch (e) {
        AppLogger.log('  ⚠️ Could not start native capture service: $e');
      }

      // 2. Mark Flutter-side monitoring as active
      final screenMonitoring = ScreenMonitoringService.instance;
      if (screenMonitoring.isInitialized && !screenMonitoring.isMonitoring) {
        AppLogger.log('  📸 Activating Flutter screen monitoring handler...');
        final started = await screenMonitoring.startMonitoring(skipPermissionRequest: true);
        if (started) {
          AppLogger.log('  ✅ Screen monitoring active');
        } else {
          AppLogger.log('  ⚠️ Screen monitoring not started');
        }
      }
      
      // 2. Start the Flutter background service (runs the AI loop in a background isolate)
      final bgService = FlutterBackgroundService();
      final isRunning = await bgService.isRunning();
      if (!isRunning) {
        AppLogger.log('  🔄 Starting background AI service...');
        await bgService.startService();
        AppLogger.log('  ✅ Background AI service started');
      }
      
      // 3. Listen for alertGenerated events from the background service
      _bgAlertSub?.cancel();
      _bgAlertSub = bgService.on('alertGenerated').listen((event) {
        if (event == null || !mounted) return;
        AppLogger.log('📡 Received alertGenerated from background service');
        _handleBackgroundAlert(event);
      });
      
      // 4. Start on-demand screenshot analysis timer (every 30 seconds)
      // This is much better than continuous 5s polling - AI gets time to process
      // and we're not wasting battery on continuous screening
      if (_refreshTimer != null) _refreshTimer!.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        AppLogger.log('🔄 Requesting on-demand screenshot analysis...');
        screenMonitoring.requestScreenshotAnalysis();
      });
      AppLogger.log('  ⏱️ On-demand screenshot analysis scheduled every 30 seconds');
      
      if (mounted) setState(() => _aiMonitoringActive = true);
      AppLogger.log('🧠 AI monitoring pipeline active');
    } catch (e) {
      AppLogger.log('❌ Error starting AI monitoring: $e');
    }
  }

  /// Handle an alert event from the background service isolate
  void _handleBackgroundAlert(Map<String, dynamic> event) async {
    try {
      final result = ContentAnalysisResult.fromJson(event);
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      final childHash = prefs.getChildHash() ?? '';
      
      final alert = Alert(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        riskScore: result.riskScore,
        summary: result.summary,
        severity: Alert.determineSeverity(result.riskScore),
        contentType: ContentType.IMAGE,
        detectedContent: result.categories.entries
            .where((e) => e.value > 0.5)
            .map((e) => '${e.key}: ${(e.value * 100).toInt()}%')
            .join(', '),
        childHash: childHash,
        childName: 'Child',
      );
      
      // Save to local DB + emit to stream
      await RealtimeAlertService.instance.addAlert(alert);
      
      // Sync to server
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        await RealtimeAlertService.instance.syncAlertToServer(
          alert, apiService, 'Child',
        );
      } catch (_) {}
      
      AppLogger.log('✅ Background alert processed and stored: ${alert.id}');
    } catch (e) {
      AppLogger.log('❌ Error handling background alert: $e');
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
  /// a separate flag is set so the monitoring services block non-essential apps.
  /// Per-app restrictions are NEVER overwritten — they stay intact so that
  /// individual apps are only blocked when THEIR OWN limit runs out.
  void _checkAndApplyDailyLimitEnforcement() {
    if (!mounted) return;

    // Require both a valid screen time value and a positive daily limit
    if (_screenTime == null || _dailyLimitHours == null || _dailyLimitHours! <= 0) {
      return;
    }

    double? usedHours;
    if (_screenTimeSeconds != null) {
      usedHours = _screenTimeSeconds! / 3600.0;
    } else {
      usedHours = _parseScreenTimeHours(_screenTime);
    }
    if (usedHours == null) return;

    final limitHours = _dailyLimitHours!;
    final hasExceeded = usedHours >= limitHours;

    final appBlocker = Provider.of<AppBlockerService>(context, listen: false);

    // Always keep per-app restrictions intact (server + exam mode)
    final baseRestrictions = _getEffectiveRestrictions();
    appBlocker.updateRestrictions(baseRestrictions);
    BackgroundMonitoringService.updateRestrictions(baseRestrictions);

    // Set the daily-limit-exceeded flag SEPARATELY.
    // The monitoring services will use this flag to block all non-essential
    // apps, independently from the per-app limits.
    appBlocker.setDailyLimitExceeded(hasExceeded);
    BackgroundMonitoringService.updateDailyLimitExceeded(hasExceeded);

    if (hasExceeded) {
      AppLogger.log('⏰ Daily limit exceeded (used=${usedHours.toStringAsFixed(2)}h / limit=${limitHours.toStringAsFixed(2)}h).');
    } else {
      AppLogger.log('✅ Daily limit not exceeded (used=${usedHours.toStringAsFixed(2)}h / limit=${limitHours.toStringAsFixed(2)}h).');
    }
  }

  Future<void> _initUsageStats() async {
    try {
      // Permission is guaranteed by the permission gate before this is called.
      // Just return early if somehow still not granted (do NOT open settings here).
      bool? isPermissionGranted = await UsageStats.checkUsagePermission();
      if (isPermissionGranted != true) return;

      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);

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
        });
      }
    } catch (e) {
      AppLogger.log('Error fetching usage stats: $e');
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

  List<MapEntry<String, int>> get _displayUsageEntries {
    if (_nativeAppUsageSeconds.isNotEmpty) {
      final entries = _nativeAppUsageSeconds.entries
          .where((entry) => entry.value > 0)
          .toList();
      entries.sort((a, b) => b.value.compareTo(a.value));
      return entries;
    }

    final entries = <MapEntry<String, int>>[];
    for (var usage in _usageStats) {
      final packageName = usage.packageName ?? 'unknown';
      final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
      final seconds = millis ~/ 1000;
      if (seconds > 0) {
        entries.add(MapEntry(packageName, seconds));
      }
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  String get _totalUsageTime {
    if (_screenTimeSeconds != null) {
      return _formatDurationFromSeconds(_screenTimeSeconds!);
    }
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

  List<MapEntry<String, int>> get _browserUsageEntries {
    final entries = _displayUsageEntries.where((entry) {
      final app = _apps[entry.key];
      if (app == null) return false;
      return _isBrowserApp(entry.key, app.name);
    }).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  String get _totalBrowserTime {
    if (_browserUsageEntries.isEmpty) return '0m';
    int totalSeconds = 0;
    for (var entry in _browserUsageEntries) {
      totalSeconds += entry.value;
    }
    return _formatDurationFromSeconds(totalSeconds);
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
      AppLogger.log('Error fetching browser history: $e');
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
    final dailyLimitHours = _dailyLimitHours ?? 8.0;

    try {
      double totalHours = 0.0;
      if (_screenTimeSeconds != null) {
        totalHours = _screenTimeSeconds! / 3600.0;
      } else {
        // Fallback to the formatted string (e.g., "2h 15m" or "45m")
        final timeStr = _totalUsageTime;
        final hoursMatch = RegExp(r'(\d+)h').firstMatch(timeStr);
        if (hoursMatch != null) {
          totalHours += double.parse(hoursMatch.group(1)!);
        }
        final minutesMatch = RegExp(r'(\d+)m').firstMatch(timeStr);
        if (minutesMatch != null) {
          totalHours += double.parse(minutesMatch.group(1)!) / 60;
        }
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
    if (_restrictions == null) return false;
    
    for (var usage in _usageStats) {
      final packageName = usage.packageName ?? '';
      final hasLimit = _restrictions!.restrictedApps.containsKey(packageName);
      if (!hasLimit) continue;
      final limitHours = _restrictions!.restrictedApps[packageName];
      if (limitHours == null) continue;

      double usedHours;
      if (_nativeAppUsageSeconds.isNotEmpty && _nativeAppUsageSeconds.containsKey(packageName)) {
        usedHours = _nativeAppUsageSeconds[packageName]! / 3600.0;
      } else {
        final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
        usedHours = millis / 1000 / 3600;
      }

      if (usedHours >= limitHours) {
        return true;
      }
    }
    return false;
  }

  String _formatDurationFromSeconds(int seconds) {
    if (seconds <= 0) return '0m';
    final duration = Duration(seconds: seconds);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    return '${duration.inMinutes}m';
  }

  void _handleBottomNavTap(int index) {
    if (index == 2) {
      // Already on dashboard, do nothing
      return;
    }

    if (index == 0) {
      _showGuardianChatBottomSheet();
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

  Future<void> _showGuardianChatBottomSheet() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash() ?? '';

    if (childHash.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Child profile is not configured yet'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final chatService = Provider.of<ChatService>(context, listen: false);
    final guardianId = await chatService.ensureGuardianIdForChild(childHash);

    if (guardianId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No guardian is linked for chat yet'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    await chatService.openChildChat(childHash: childHash, guardianId: guardianId);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildGuardianChatBottomSheet(guardianId: guardianId),
    );

    if (!mounted) return;
    await chatService.disconnect();
    chatService.clearChat();
  }

  Widget _buildGuardianChatBottomSheet({required int guardianId}) {
    final TextEditingController messageController = TextEditingController();
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash() ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF317AF7), Color(0xFF5B4A9F)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Guardian Chat',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Consumer<ChatService>(
                          builder: (context, chatService, child) {
                            return Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: chatService.isConnected
                                        ? Colors.greenAccent
                                        : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  chatService.isConnected
                                      ? 'E2E Encrypted • Connected'
                                      : 'E2E Encrypted • Offline',
                                  style: TextStyle(
                                    color: chatService.isConnected
                                        ? Colors.greenAccent.withOpacity(0.8)
                                        : Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<ChatService>(
                builder: (context, chatService, child) {
                  if (chatService.isLoading && chatService.messages.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF317AF7)),
                    );
                  }

                  if (chatService.messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.lock_outline, size: 64, color: Colors.white24),
                          SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.white60, fontSize: 16),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Start an encrypted chat with your guardian',
                            style: TextStyle(color: Colors.white38, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: chatService.messages.length,
                    itemBuilder: (context, index) {
                      final message =
                          chatService.messages[chatService.messages.length - 1 - index];
                      final isFromChild = !message.isFromParent;
                      final displayText = message.messageDecrypted ?? '[Encrypted]';

                      return Align(
                        alignment:
                            isFromChild ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72,
                          ),
                          decoration: BoxDecoration(
                            gradient: isFromChild
                                ? const LinearGradient(
                                    colors: [Color(0xFF317AF7), Color(0xFF5B4A9F)],
                                  )
                                : null,
                            color: isFromChild ? null : const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatChatTime(message.timestamp),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.62),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: messageController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: AppTheme.surfaceDark,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF317AF7), Color(0xFF5B4A9F)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: () async {
                          final message = messageController.text.trim();
                          if (message.isEmpty || childHash.isEmpty) {
                            return;
                          }

                          messageController.clear();

                          final chatService =
                              Provider.of<ChatService>(context, listen: false);
                          final success = await chatService.sendMessageAsChild(
                            childHash: childHash,
                            guardianId: guardianId,
                            message: message,
                          );

                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to send encrypted message'),
                                backgroundColor: AppTheme.error,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatChatTime(DateTime timestamp) {
    return DateFormat('HH:mm').format(timestamp.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.log('🎓 BUILD: Exam Mode = $_examMode, Apps = ${_examModeApps.length}');
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
                IconButton(
                  icon: const Icon(Icons.bug_report, color: Colors.white70, size: 22),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LogViewerScreen()),
                    );
                  },
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
                          PulsingDot(
                            color: locationService.isTracking ? Colors.green : Colors.grey,
                            size: 8,
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
      drawer: _buildChildDrawer(context, childName),
      body: _awaitingPermissions
          ? _buildPermissionSetup()
          : Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/mountain.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: _loading
            ? _buildLoadingState()
            : FadeTransition(
                opacity: _entranceFade,
                child: RefreshIndicator(
                color: const Color(0xFF317AF7),
                onRefresh: _refreshData,
                child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 110, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    
                    // Task Loading Status (only on initial load, not background refreshes)
                    if (_loadingTasks && _pendingTasks.isEmpty) ...[
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
                    if (_displayUsageEntries.isNotEmpty) ...[
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
                              '${_displayUsageEntries.length}',
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
                    if (_browserUsageEntries.isNotEmpty) ...[
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
                            itemCount: _browserUsageEntries.length,
                            itemBuilder: (context, index) {
                              final entry = _browserUsageEntries[index];
                              final app = _apps[entry.key];
                              
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
                                      _formatDurationFromSeconds(entry.value),
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
                                        'Browser history will appear here once available',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
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
                    _displayUsageEntries.isEmpty
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
                                int totalSecondsAll = 0;
                                for (var entry in _displayUsageEntries) {
                                  totalSecondsAll += entry.value;
                                }

                                return _displayUsageEntries.take(10).map((entry) {
                                final app = _apps[entry.key];
                                if (app == null) return const SizedBox.shrink();

                                // Check if this app has a time limit
                                final packageName = entry.key;
                                final hasLimit = _restrictions?.restrictedApps.containsKey(packageName) ?? false;
                                final limitHours = hasLimit ? _restrictions!.restrictedApps[packageName] : null;
                                
                                // Check if blocked by exam mode
                                final isBlockedByExamMode = _examMode && _examModeApps.contains(packageName);
                                final effectiveLimit = isBlockedByExamMode ? 0.0 : limitHours;
                                
                                // Calculate time used
                                final seconds = entry.value;
                                final usedHours = seconds / 3600;
                                final usedMinutes = (seconds / 60).round();
                                
                                // Check if limit is exceeded
                                final isExceeded = (hasLimit && effectiveLimit != null && usedHours >= effectiveLimit) || isBlockedByExamMode;
                                
                                // Calculate percentage of total app usage time
                                final totalSeconds = totalSecondsAll == 0 ? 1 : totalSecondsAll;
                                final percentage = ((seconds / totalSeconds) * 100).clamp(0, 100).toInt();
                                
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
                              if (_displayUsageEntries.length > 10)
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
        ),
    );
  }
  
  void _showRequestTimeDialog(BuildContext context, {String? packageName, String? appName}) {
    final timeExtService = context.read<TimeExtensionService>();
    final prefsManager = context.read<PreferencesManager>();
    
    showDialog(
      context: context,
      builder: (dialogContext) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: timeExtService),
          Provider.value(value: prefsManager),
        ],
        child: TimeRequestDialog(
          packageName: packageName,
          appName: appName,
        ),
      ),
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

  // ───────────────── Permission setup screen ─────────────────
  
  void _showRestrictedHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Restricted Setting', style: TextStyle(color: Colors.white)),
        content: const Text(
          'On Android 13+, accessibility services are restricted for sideloaded apps. '
          'To enable it:\n\n'
          '1. Open device Settings > Apps > Guardian AI\n'
          '2. Tap the 3 dots (top right) and "Allow restricted settings"\n'
          '3. Return here and enable the service.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got It', style: TextStyle(color: Color(0xFF317AF7))),
          ),
        ],
      ),
    );
  }

  void _startModelDownload() {
    if (_isDownloadingModel || _modelInstalled) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Download AI Model', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Guardian AI requires the Gemma model (approx 2.9GB) to monitor screen activity for safety. '
          'Please ensure you are on Wi-Fi.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _isDownloadingModel = true;
                _downloadProgress = 0.0;
              });
              GemmaManager.instance.downloadModel();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF317AF7)),
            child: const Text('Start Download'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionSetup() {
    final allPermsGranted = _locationGranted && _usageStatsGranted && _accessibilityGranted && _screenCaptureGranted;
    final allReady = allPermsGranted && _modelInstalled;
    
    // Count granted items (4 permissions + 1 model)
    int grantedCount = 0;
    if (_locationGranted) grantedCount++;
    if (_usageStatsGranted) grantedCount++;
    if (_accessibilityGranted) grantedCount++;
    if (_screenCaptureGranted) grantedCount++;
    if (_modelInstalled) grantedCount++;
    const totalSteps = 5;
    
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF050608), Color(0xFF0A1628), Color(0xFF0D1B3E)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // ── Header with animated shield ──
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow ring
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: allReady 
                              ? Colors.greenAccent.withOpacity(0.3) 
                              : const Color(0xFF317AF7).withOpacity(0.15),
                          width: 2,
                        ),
                      ),
                    ),
                    // Shield icon container
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: allReady 
                              ? [const Color(0xFF00C853), const Color(0xFF1B5E20)]
                              : [const Color(0xFF317AF7), const Color(0xFF0D47A1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (allReady ? Colors.greenAccent : const Color(0xFF317AF7)).withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        allReady ? Icons.verified_user_rounded : Icons.shield_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // ── Title & subtitle ──
              Text(
                allReady ? 'All Set!' : 'Setup Guardian AI',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                allReady
                    ? 'Your device is protected. Tap Continue to start.'
                    : 'Complete each step below to activate monitoring.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              
              // ── Progress indicator ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1624).withOpacity(0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1B2433), width: 0.5),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$grantedCount of $totalSteps completed',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${(grantedCount / totalSteps * 100).toInt()}%',
                          style: TextStyle(
                            color: allReady ? Colors.greenAccent : const Color(0xFF317AF7),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: grantedCount / totalSteps,
                        backgroundColor: const Color(0xFF1B2433),
                        color: allReady ? Colors.greenAccent : const Color(0xFF317AF7),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // ── Section: Permissions ──
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF317AF7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'PERMISSIONS',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              
              // ── Permission rows ──
              _buildPermRow(
                stepNumber: 1,
                icon: Icons.location_on_rounded,
                title: 'Location Access',
                subtitle: 'Required for safety zones & geofencing',
                granted: _locationGranted,
                loading: _locationLoading,
                onTap: _requestLocation,
              ),
              const SizedBox(height: 10),
              _buildPermRow(
                stepNumber: 2,
                icon: Icons.bar_chart_rounded,
                title: 'Usage Access',
                subtitle: 'Opens Settings — enable app usage tracking',
                granted: _usageStatsGranted,
                loading: _usageLoading,
                onTap: _requestUsageAccess,
              ),
              const SizedBox(height: 10),
              _buildPermRow(
                stepNumber: 3,
                icon: Icons.accessibility_new_rounded,
                title: 'Accessibility Service',
                subtitle: 'Opens Settings — enable browser monitoring',
                granted: _accessibilityGranted,
                loading: _accessibilityLoading,
                onTap: _requestAccessibility,
              ),
              if (!_accessibilityGranted)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 56),
                  child: GestureDetector(
                    onTap: _showRestrictedHelp,
                    child: Row(
                      children: [
                        Icon(Icons.help_outline_rounded, color: const Color(0xFF317AF7).withOpacity(0.8), size: 14),
                        const SizedBox(width: 4),
                        const Text(
                          '"Restricted setting" error?',
                          style: TextStyle(
                            color: Color(0xFF317AF7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              _buildPermRow(
                stepNumber: 4,
                icon: Icons.screenshot_monitor_rounded,
                title: 'Screen Recording',
                subtitle: 'Required for AI content safety monitoring',
                granted: _screenCaptureGranted,
                loading: _screenCaptureLoading,
                onTap: _requestScreenCapture,
              ),
              const SizedBox(height: 24),
              
              // ── Section: AI Model ──
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: _modelInstalled ? Colors.greenAccent : const Color(0xFF317AF7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'AI MODEL',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              
              _buildPermRow(
                stepNumber: 5,
                icon: Icons.psychology_rounded,
                title: 'AI Safety Model',
                subtitle: _isDownloadingModel
                    ? 'Downloading... ${(_downloadProgress * 100).toStringAsFixed(1)}%'
                    : (_modelInstalled
                        ? 'Model Ready'
                        : (_modelStatus.contains('Failed') || _modelStatus.contains('Error')
                            ? 'Download failed — tap to retry'
                            : 'Tap to download (~2.9 GB, Wi-Fi recommended)')),
                granted: _modelInstalled,
                loading: _isDownloadingModel,
                onTap: _startModelDownload,
              ),
              if (_isDownloadingModel)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 56, right: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: Colors.white10,
                      color: const Color(0xFF317AF7),
                      minHeight: 6,
                    ),
                  ),
                ),
              const SizedBox(height: 32),
              
              // ── Continue / Re-check button ──
              SizedBox(
                height: 56,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: allReady
                        ? const LinearGradient(
                            colors: [Color(0xFF00C853), Color(0xFF00E676)],
                          )
                        : null,
                    boxShadow: allReady
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: ElevatedButton(
                    onPressed: allReady
                        ? () {
                            setState(() => _awaitingPermissions = false);
                            _startServicesAndLoad();
                          }
                        : () async {
                            await _checkAllPermissions();
                            _checkIfAllGranted();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: allReady
                          ? Colors.transparent
                          : const Color(0xFF317AF7),
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          allReady ? 'Continue' : 'Re-check Permissions',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (allReady) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (!allPermsGranted && !allReady)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _modelInstalled
                        ? 'Grant all permissions above to continue'
                        : allPermsGranted
                            ? 'Download the AI model to continue'
                            : 'Grant all permissions and download the AI model',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermRow({
    required int stepNumber,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: granted ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: const Color(0xFF317AF7).withOpacity(0.1),
        highlightColor: const Color(0xFF317AF7).withOpacity(0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: granted
                ? Colors.greenAccent.withOpacity(0.05)
                : const Color(0xFF0F1624),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: granted
                  ? Colors.greenAccent.withOpacity(0.4)
                  : loading
                      ? const Color(0xFF317AF7).withOpacity(0.5)
                      : const Color(0xFF1B2433),
              width: granted || loading ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Step number badge
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: granted
                      ? LinearGradient(
                          colors: [Colors.greenAccent.withOpacity(0.2), Colors.greenAccent.withOpacity(0.08)],
                        )
                      : LinearGradient(
                          colors: [const Color(0xFF317AF7).withOpacity(0.18), const Color(0xFF317AF7).withOpacity(0.06)],
                        ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: granted
                    ? const Icon(Icons.check_rounded, color: Colors.greenAccent, size: 22)
                    : Icon(icon, color: const Color(0xFF317AF7), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (granted)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      granted ? 'Permission granted' : subtitle,
                      style: TextStyle(
                        color: granted ? Colors.greenAccent.withOpacity(0.6) : Colors.white.withOpacity(0.4),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFF317AF7).withOpacity(0.8),
                        ),
                      ),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        granted
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_ios_rounded,
                        key: ValueKey(granted),
                        color: granted ? Colors.greenAccent : Colors.white24,
                        size: granted ? 24 : 14,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────── Skeleton / loading state ─────────────────

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 110, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Screen time card placeholder
          _buildSkeletonCard(
            height: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonLine(width: 160, height: 14),
                const SizedBox(height: 20),
                _buildSkeletonLine(width: 120, height: 40),
                const SizedBox(height: 16),
                _buildSkeletonLine(width: double.infinity, height: 8),
                const SizedBox(height: 10),
                _buildSkeletonLine(width: 220, height: 10),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Pending tasks placeholder
          _buildSkeletonCard(
            height: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonLine(width: 140, height: 12),
                const SizedBox(height: 14),
                _buildSkeletonLine(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: 200, height: 10),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // App usage placeholder
          _buildSkeletonCard(
            height: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonLine(width: 120, height: 12),
                const SizedBox(height: 14),
                _buildSkeletonLine(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: 180, height: 10),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Browser / activity card placeholder
          _buildSkeletonCard(
            height: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonLine(width: 140, height: 12),
                const SizedBox(height: 14),
                _buildSkeletonLine(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: 240, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: 200, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard({required double height, required Widget child}) {
    return AnimatedBuilder(
      animation: _loadingPulseController,
      builder: (context, _) {
        final t = _loadingPulseController.value;
        return Container(
          height: height,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + t * 2, 0),
              end: Alignment(1.0 + t * 2, 0),
              colors: const [
                Color(0xFF0F1624),
                Color(0xFF1B263B),
                Color(0xFF0F1624),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1B2433)),
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildSkeletonLine({required double width, required double height}) {
    return ShimmerBox(
      width: width == double.infinity
          ? MediaQuery.of(context).size.width - 80
          : width,
      height: height,
      borderRadius: 8,
    );
  }

  // ───────────────── Drawer helpers ─────────────────

  Widget _buildChildDrawer(BuildContext context, String childName) {
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D1B3E), Color(0xFF0A0A0F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A3C8B), Color(0xFF0D1B3E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF317AF7), Color(0xFF5B4A9F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF317AF7).withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.person_rounded, color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      childName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        PulsingDot(color: Colors.greenAccent, size: 7),
                        const SizedBox(width: 6),
                        const Text(
                          'Active session',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Menu ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _drawerSectionLabel('ACTIVITIES'),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 50),
                      child: _buildChildDrawerItem(
                        context,
                        icon: Icons.chat_bubble_outline,
                        label: 'Guardian Chat',
                        onTap: () {
                          Navigator.pop(context);
                          _showGuardianChatBottomSheet();
                        },
                      ),
                    ),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 80),
                      child: _buildChildDrawerItem(
                        context,
                        icon: Icons.task_alt_outlined,
                        label: 'My Tasks',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MyTasksScreen()),
                          );
                        },
                      ),
                    ),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 150),
                      child: _buildChildDrawerItem(
                        context,
                        icon: Icons.sync_rounded,
                        label: 'Refresh Data',
                        onTap: () {
                          Navigator.pop(context);
                          _refreshData();
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Divider(color: Colors.white10, height: 1),
                    ),
                    _drawerSectionLabel('ACCOUNT'),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 220),
                      child: _buildChildDrawerItem(
                        context,
                        icon: Icons.logout_rounded,
                        label: 'Logout',
                        isDestructive: true,
                        onTap: () async {
                          Navigator.pop(context);
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              title: const Text('Logout',
                                  style: TextStyle(color: Colors.white)),
                              content: const Text(
                                  'Are you sure you want to logout?',
                                  style: TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel',
                                      style: TextStyle(color: Colors.white70)),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF317AF7),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Logout',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && mounted) {
                            final prefsManager = context.read<PreferencesManager>();
                            await LocationBackgroundService.stop(); // stop tracking on logout
                            await prefsManager.clearAll();
                            if (mounted) {
                              Navigator.pushReplacementNamed(context, '/login');
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ── Footer ──
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A3C8B).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.shield_rounded,
                          color: Color(0xFF317AF7), size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Guardian AI',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text('v1.0  •  Child Mode',
                            style:
                                TextStyle(color: Colors.white30, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white30,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
    );
  }

  Widget _buildChildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    final color = isDestructive ? const Color(0xFFF97373) : Colors.white;
    final iconBg = isDestructive
        ? const Color(0xFF3A1A1A)
        : const Color(0xFF1C2A50);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: TapBounce(
        onTap: onTap ?? () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!isDestructive)
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
