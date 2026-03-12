import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'realtime_alert_service.dart';
import 'gemma_content_analyzer.dart';
import 'gemma_manager.dart';
import '../models/alert.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';

/// Service to manage continuous screen monitoring
/// Receives screenshots from native Android code and analyzes them with vision models
class ScreenMonitoringService {
  static final ScreenMonitoringService _instance = ScreenMonitoringService._internal();
  
  factory ScreenMonitoringService() => _instance;
  
  ScreenMonitoringService._internal();
  
  static ScreenMonitoringService get instance => _instance;
  
  static const platform = MethodChannel('com.example.guardian_ai/screen_capture');
  
  bool _isMonitoring = false;
  bool _isInitialized = false;
  
  // Statistics (now updated via events or handled by BG service)
  int _framesAnalyzed = 0;
  int _alertsGenerated = 0;
  DateTime? _lastAnalysisTime;
  
  // Child context
  String? _currentChildHash;
  String? _currentChildName;
  
  // Services
  late RealtimeAlertService _alertService;

  // Getters
  bool get isMonitoring => _isMonitoring;
  bool get isInitialized => _isInitialized;
  int get framesAnalyzed => _framesAnalyzed;
  int get alertsGenerated => _alertsGenerated;
  DateTime? get lastAnalysisTime => _lastAnalysisTime;
  
  /// Initialize the screen monitoring service
  Future<bool> initialize({
    required String childHash,
    required String childName,
  }) async {
    if (_isInitialized) {
      AppLogger.log('✅ ScreenMonitoringService already initialized');
      return true;
    }
    
    try {
      AppLogger.log('🔄 Initializing ScreenMonitoringService...');
      
      _currentChildHash = childHash;
      _currentChildName = childName;
      
      // Initialize alert service
      _alertService = RealtimeAlertService();
      
      // Set up method channel handler for screenshots
      platform.setMethodCallHandler(_handleMethodCall);
      
      _isInitialized = true;
      AppLogger.log('✅ ScreenMonitoringService initialized successfully');
      return true;
    } catch (e, stackTrace) {
      AppLogger.logError('ScreenMonitoringService initialization failed', e, stackTrace);
      return false;
    }
  }
  
  /// Start continuous screen monitoring.
  /// If [skipPermissionRequest] is true, assumes permission was already granted
  /// (e.g. from the permission setup page) and just marks as monitoring.
  Future<bool> startMonitoring({bool skipPermissionRequest = false}) async {
    if (!_isInitialized) {
      AppLogger.log('❌ ScreenMonitoringService not initialized');
      return false;
    }
    
    if (_isMonitoring) {
      AppLogger.log('⚠️  ScreenMonitoringService already monitoring');
      return true; // Already running, not an error
    }
    
    try {
      AppLogger.log('🚀 Starting screen monitoring...');
      
      if (skipPermissionRequest) {
        _isMonitoring = true;
        AppLogger.log('✅ Screen monitoring started (permission pre-granted)');
        return true;
      }
      
      // Request screen capture permission from Android
      final result = await platform.invokeMethod('requestPermission');
      
      if (result == true) {
        _isMonitoring = true;
        AppLogger.log('✅ Screen monitoring started successfully');
        return true;
      } else {
        AppLogger.log('❌ Screen capture permission denied');
        return false;
      }
    } on PlatformException catch (e) {
      AppLogger.log('❌ Platform error starting screen monitoring: ${e.message}');
      return false;
    } catch (e) {
      AppLogger.log('❌ Error starting screen monitoring: $e');
      return false;
    }
  }
  
  /// Stop screen monitoring
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) {
      AppLogger.log('⚠️  ScreenMonitoringService not monitoring');
      return;
    }
    
    try {
      AppLogger.log('🛑 Stopping screen monitoring...');
      await platform.invokeMethod('stopCapture');
      _isMonitoring = false;
      AppLogger.log('✅ Screen monitoring stopped');
    } catch (e) {
      AppLogger.log('❌ Error stopping screen monitoring: $e');
    }
  }
  
  /// Handle method calls from native code
  Future<void> _handleMethodCall(MethodCall call) async {
    try {
    switch (call.method) {
      case 'onScreenshotCaptured':
        final args = call.arguments as Map?;
        if (args == null) return;
        final path = args['path'] as String?;
        final timestamp = args['timestamp'] as int?;
        
        if (path == null || timestamp == null) return;
        AppLogger.log('📸 UI: Screenshot received (path: $path). Background service will handle analysis.');
        
        // No longer analyzing in the UI isolate to save VRAM and keep UI smooth.
        // We just return success to clear the native back-pressure flag.
        return;
        
      default:
        AppLogger.log('⚠️  Unknown method: ${call.method}');
    }
    } catch (e, stackTrace) {
      AppLogger.logError('Error handling method call ${call.method}', e, stackTrace);
    }
  }
  
  /// Get monitoring statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isMonitoring': _isMonitoring,
      'framesAnalyzed': _framesAnalyzed,
      'alertsGenerated': _alertsGenerated,
      'lastAnalysisTime': _lastAnalysisTime?.toIso8601String(),
    };
  }
  
  /// Update statistics from background service events
  void updateStats(int frames, int alerts, DateTime lastTime) {
    _framesAnalyzed = frames;
    _alertsGenerated = alerts;
    _lastAnalysisTime = lastTime;
  }
  
  /// Reset statistics
  void resetStatistics() {
    _framesAnalyzed = 0;
    _alertsGenerated = 0;
    _lastAnalysisTime = null;
  }
}
