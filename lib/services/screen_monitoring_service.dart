import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'realtime_alert_service.dart';
import 'api_service.dart';
import 'api_service.dart';
import '../models/alert.dart';
import 'package:uuid/uuid.dart';
import '../config.dart';
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
  
  // Analysis queue
  final List<Map<String, dynamic>> _analysisQueue = [];
  bool _isProcessingQueue = false;
  
  // Statistics
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
  
  /// Start continuous screen monitoring
  Future<bool> startMonitoring() async {
    if (!_isInitialized) {
      AppLogger.log('❌ ScreenMonitoringService not initialized');
      return false;
    }
    
    if (_isMonitoring) {
      AppLogger.log('⚠️  ScreenMonitoringService already monitoring');
      return false;
    }
    
    try {
      AppLogger.log('🚀 Starting screen monitoring...');
      
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
      _analysisQueue.clear();
      AppLogger.log('✅ Screen monitoring stopped');
    } catch (e) {
      AppLogger.log('❌ Error stopping screen monitoring: $e');
    }
  }
  
  /// Handle method calls from native code
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onScreenshotCaptured':
        final args = call.arguments as Map;
        final path = args['path'] as String;
        final timestamp = args['timestamp'] as int;
        final foregroundApp = args['foregroundApp'] as String?;
        
        AppLogger.log('📸 Screenshot received: $path');
        
        // Add to analysis queue
        _analysisQueue.add({
          'path': path,
          'timestamp': timestamp,
          'foregroundApp': foregroundApp,
        });
        
        // Process queue if not already processing
        if (!_isProcessingQueue) {
          _processAnalysisQueue();
        }
        break;
        
      default:
        AppLogger.log('⚠️  Unknown method: ${call.method}');
    }
  }
  
  /// Process the analysis queue
  Future<void> _processAnalysisQueue() async {
    if (_isProcessingQueue) return;
    
    _isProcessingQueue = true;
    
    while (_analysisQueue.isNotEmpty) {
      final item = _analysisQueue.removeAt(0);
      await _analyzeScreenshot(
        item['path'],
        item['timestamp'],
        item['foregroundApp'],
      );
    }
    
    _isProcessingQueue = false;
  }
  
  /// Analyze a screenshot with the vision model (DISABLED)
  Future<void> _analyzeScreenshot(
    String path,
    int timestamp,
    String? foregroundApp,
  ) async {
    try {
      AppLogger.log('🔍 Screenshot captured: $path');
      
      // AI Integration Removed:
      // Simply delete the file to save space since we aren't analyzing it.
      
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          AppLogger.log('  🗑️  Screenshot deleted (Analysis disabled)');
        }
      } catch (e) {
        AppLogger.log('  ⚠️  Failed to delete screenshot file: $e');
      }
      
    } catch (e, stackTrace) {
      AppLogger.logError('Error handling screenshot', e, stackTrace);
    }
  }
  
  /// Generate an alert (DISABLED)
  Future<void> _generateAlert({
    required String path,
    required int riskScore,
    required Map<String, double> scores,
    String? foregroundApp,
    String extractedText = '',
    bool isTextAlert = false,
  }) async {
     // Alert generation removed
  }

  String _generateAlertSummary(int riskScore, Map<String, double> scores, String? foregroundApp, bool isTextAlert) {
    return 'Analysis Disabled';
  }

  
  /// Get monitoring statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isMonitoring': _isMonitoring,
      'framesAnalyzed': _framesAnalyzed,
      'alertsGenerated': _alertsGenerated,
      'lastAnalysisTime': _lastAnalysisTime?.toIso8601String(),
      'queueSize': _analysisQueue.length,
    };
  }
  
  /// Reset statistics
  void resetStatistics() {
    _framesAnalyzed = 0;
    _alertsGenerated = 0;
    _lastAnalysisTime = null;
  }

  // Helper function for string length
  int min(int a, int b) => a < b ? a : b;
}
