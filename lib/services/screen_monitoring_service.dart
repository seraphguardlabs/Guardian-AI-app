import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'vision_analysis_service.dart';
import 'realtime_alert_service.dart';
import 'api_service.dart';
import 'ocr_service.dart';
import 'text_threat_detection_service.dart';
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
  late VisionAnalysisService _visionService;
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
      
      // Initialize vision service
      _visionService = VisionAnalysisService.instance;
      await _visionService.initialize();
      
      // Initialize OCR and Text Threat services
      OCRService.instance.initialize();
      await TextThreatDetectionService.instance.initialize();
      
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
  
  /// Analyze a screenshot with the vision model
  Future<void> _analyzeScreenshot(
    String path,
    int timestamp,
    String? foregroundApp,
  ) async {
    try {
      final startTime = DateTime.now();
      debugPrint('🔍 Analyzing screenshot: $path');
      
      // Analyze with vision model
      final scores = await _visionService.analyzeScreenshot(path);
      
      _framesAnalyzed++;
      _lastAnalysisTime = DateTime.now();
      
      final analysisTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('  Analysis completed in ${analysisTime}ms');
      debugPrint('  Scores: $scores');
      
      // Check if explicit content detected
      final explicitScore = scores['explicit'] ?? 0.0;
      final violenceScore = scores['violence'] ?? 0.0;
      final suggestiveScore = scores['suggestive'] ?? 0.0;
      
      // Calculate visual risk score (0-100)
      int visualRiskScore = ((explicitScore * 0.5 + violenceScore * 0.3 + suggestiveScore * 0.2) * 100).toInt();
      
      // --- NEW: Text Analysis Integration ---
      int textRiskScore = 0;
      String extractedText = '';
      
      try {
        extractedText = await OCRService.instance.extractText(path);
        if (extractedText.isNotEmpty) {
          final threatScore = await TextThreatDetectionService.instance.analyzeChatMessage(extractedText);
          textRiskScore = (threatScore * 100).toInt();
          debugPrint('  📝 Extracted Text (len=${extractedText.length}): "${extractedText.replaceAll('\n', ' ').substring(0, min(50, extractedText.length))}..."');
          debugPrint('  📝 Text Threat Score: $textRiskScore%');
        }
      } catch (e) {
        debugPrint('  ⚠️ Text analysis failed: $e');
      }
      
      // Combine scores: Take the maximum of visual and text risk
      final riskScore = (visualRiskScore > textRiskScore) ? visualRiskScore : textRiskScore;
      
      // Generate alert if risk score is high (>60%)
      if (riskScore >= 60) {
        await _generateAlert(
          path: path,
          riskScore: riskScore,
          scores: scores,
          foregroundApp: foregroundApp,
          extractedText: extractedText,
          isTextAlert: textRiskScore > visualRiskScore,
        );
      }
      
      // Conditional cleanup of screenshot file based on risk threshold
      try {
        final file = File(path);
        if (await file.exists()) {
          // Delete only if risk is below configured threshold
          if (riskScore < Config.screenshotDeletionRiskThreshold) {
            await file.delete();
            debugPrint('  🗑️  Low-risk screenshot deleted: $path');
          } else {
            debugPrint('  📁  High-risk screenshot retained for alert: $path');
          }
        }
      } catch (e) {
        debugPrint('  ⚠️  Failed to handle screenshot file: $e');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ Error analyzing screenshot: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
  
  /// Generate an alert for detected inappropriate content
  Future<void> _generateAlert({
    required String path,
    required int riskScore,
    required Map<String, double> scores,
    String? foregroundApp,
    String extractedText = '',
    bool isTextAlert = false,
  }) async {
    try {
      debugPrint('🚨 Generating alert for high-risk content (score: $riskScore)');
      
      final alert = Alert(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        riskScore: riskScore,
        summary: _generateAlertSummary(riskScore, scores, foregroundApp, isTextAlert),
        severity: Alert.determineSeverity(riskScore),
        contentType: isTextAlert ? ContentType.TEXT : ContentType.IMAGE,
        detectedContent: isTextAlert 
            ? 'Suspicious text detected: "${extractedText.length > 100 ? extractedText.substring(0, 100) + '...' : extractedText}"'
            : 'Screenshot analysis detected inappropriate content',
        childHash: _currentChildHash ?? '',
        childName: _currentChildName ?? 'Unknown',
      );
      
      _alertsGenerated++;
      
      // Send alert to parent via WebSocket
      final apiService = ApiService();
      await _alertService.syncAlertToServer(
        alert,
        apiService,
        _currentChildName ?? 'Unknown',
      );
      
      debugPrint('✅ Alert generated and sent: ${alert.id}');
      
    } catch (e) {
      debugPrint('❌ Error generating alert: $e');
    }
  }
  
  /// Generate alert summary from scores
  String _generateAlertSummary(
    int riskScore,
    Map<String, double> scores,
    String? foregroundApp,
    bool isTextAlert,
  ) {
    if (isTextAlert) {
        final severity = Alert.determineSeverity(riskScore);
        final severityStr = severity.toString().split('.').last.toUpperCase();
        String appInfo = foregroundApp != null ? ' in $foregroundApp' : '';
        return '[$severityStr] Predatory text detected$appInfo (Risk: $riskScore%)';
    }
    final severity = Alert.determineSeverity(riskScore);
    final severityStr = severity.toString().split('.').last.toUpperCase();
    
    final explicitScore = ((scores['explicit'] ?? 0.0) * 100).toInt();
    final violenceScore = ((scores['violence'] ?? 0.0) * 100).toInt();
    final suggestiveScore = ((scores['suggestive'] ?? 0.0) * 100).toInt();
    
    String content = '';
    if (explicitScore > 60) content = 'explicit content';
    else if (violenceScore > 60) content = 'violent content';
    else if (suggestiveScore > 60) content = 'suggestive content';
    else content = 'inappropriate content';
    
    String appInfo = foregroundApp != null ? ' in $foregroundApp' : '';
    
    return '[$severityStr] Detected $content$appInfo (Risk: $riskScore%)';
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
