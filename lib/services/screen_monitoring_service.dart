import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'realtime_alert_service.dart';
import 'gemma_content_analyzer.dart';
import 'gemma_manager.dart';
import '../models/alert.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';

/// Service to manage on-demand screen monitoring
/// Requests screenshots from native only when AI is ready and not processing
class ScreenMonitoringService {
  static final ScreenMonitoringService _instance = ScreenMonitoringService._internal();
  
  factory ScreenMonitoringService() => _instance;
  
  ScreenMonitoringService._internal();
  
  static ScreenMonitoringService get instance => _instance;
  
  static const platform = MethodChannel('com.example.guardian_ai/screen_capture');
  
  bool _isMonitoring = false;
  bool _isInitialized = false;
  bool _isRequestingScreenshot = false;
  int _screenshotRequests = 0;
  
  // Services
  late RealtimeAlertService _alertService;

  // Getters
  bool get isMonitoring => _isMonitoring;
  bool get isInitialized => _isInitialized;
  int get screenshotRequests => _screenshotRequests;
  
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
      return true;
    }
    
    try {
      AppLogger.log('🚀 Starting screen monitoring (on-demand mode)...');
      
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

  /// Request a screenshot to be analyzed (on-demand)
  /// Call this when the AI is ready and not busy
  Future<void> requestScreenshotAnalysis() async {
    if (!_isMonitoring) {
      AppLogger.log('⚠️  Screen monitoring not active');
      return;
    }

    if (_isRequestingScreenshot) {
      AppLogger.log('⏳ Already requesting screenshot, skipping');
      return;
    }

    _isRequestingScreenshot = true;
    try {
      _screenshotRequests++;
      AppLogger.log('📸 Requesting screenshot analysis #$_screenshotRequests');
      
      // Notify background service to analyze next screenshot
      final service = FlutterBackgroundService();
      service.invoke('requestAnalysis');
    } catch (e) {
      AppLogger.log('❌ Error requesting screenshot: $e');
    } finally {
      _isRequestingScreenshot = false;
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
      'screenshotRequests': _screenshotRequests,
    };
  }
  
  /// Reset statistics
  void resetStatistics() {
    _screenshotRequests = 0;
  }
}
