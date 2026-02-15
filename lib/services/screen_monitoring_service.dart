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
      debugPrint('✅ ScreenMonitoringService already initialized');
      return true;
    }
    
    try {
      debugPrint('🔄 Initializing ScreenMonitoringService...');
      
      _currentChildHash = childHash;
      _currentChildName = childName;
      
      // Initialize alert service
      _alertService = RealtimeAlertService();
      
      // Set up method channel handler for screenshots
      platform.setMethodCallHandler(_handleMethodCall);
      
      _isInitialized = true;
      debugPrint('✅ ScreenMonitoringService initialized successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ ScreenMonitoringService initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }
  
  /// Start continuous screen monitoring
  Future<bool> startMonitoring() async {
    if (!_isInitialized) {
      debugPrint('❌ ScreenMonitoringService not initialized');
      return false;
    }
    
    if (_isMonitoring) {
      debugPrint('⚠️  ScreenMonitoringService already monitoring');
      return false;
    }
    
    try {
      debugPrint('🚀 Starting screen monitoring...');
      
      // Request screen capture permission from Android
      final result = await platform.invokeMethod('requestPermission');
      
      if (result == true) {
        _isMonitoring = true;
        debugPrint('✅ Screen monitoring started successfully');
        return true;
      } else {
        debugPrint('❌ Screen capture permission denied');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error starting screen monitoring: $e');
      return false;
    }
  }
  
  /// Stop screen monitoring
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) {
      debugPrint('⚠️  ScreenMonitoringService not monitoring');
      return;
    }
    
    try {
      debugPrint('🛑 Stopping screen monitoring...');
      await platform.invokeMethod('stopCapture');
      _isMonitoring = false;
      _analysisQueue.clear();
      debugPrint('✅ Screen monitoring stopped');
    } catch (e) {
      debugPrint('❌ Error stopping screen monitoring: $e');
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
        
        debugPrint('📸 Screenshot received: $path');
        
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
        debugPrint('⚠️  Unknown method: ${call.method}');
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
      debugPrint('🔍 Screenshot captured: $path');
      
      // AI Integration Removed:
      // Simply delete the file to save space since we aren't analyzing it.
      
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('  🗑️  Screenshot deleted (Analysis disabled)');
        }
      } catch (e) {
        debugPrint('  ⚠️  Failed to delete screenshot file: $e');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ Error handling screenshot: $e');
      debugPrint('Stack trace: $stackTrace');
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
