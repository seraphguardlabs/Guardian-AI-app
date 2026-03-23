import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'realtime_alert_service.dart';
import 'gemma_content_analyzer.dart';
import 'gemma_manager.dart';
import '../models/alert.dart';
import '../models/content_analysis_result.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';

/// Service to manage continuous screen monitoring
/// Receives screenshots from native Android code and analyzes them with vision models
class ScreenMonitoringService {
  static final ScreenMonitoringService _instance =
      ScreenMonitoringService._internal();

  factory ScreenMonitoringService() => _instance;

  ScreenMonitoringService._internal();

  static ScreenMonitoringService get instance => _instance;

  static const platform = MethodChannel(
    'com.example.guardian_ai/screen_capture',
  );

  static const _eventChannel = EventChannel(
    'com.example.guardian_ai/screen_frames',
  );

  StreamSubscription? _frameSubscription;

  bool _isMonitoring = false;
  bool _isInitialized = false;

  // Analysis queue
  final List<Map<String, dynamic>> _analysisQueue = [];
  bool _isProcessingQueue = false;

  // Latest analysis result stream
  final _analysisResultController = StreamController<ContentAnalysisResult>.broadcast();
  Stream<ContentAnalysisResult> get analysisResults => _analysisResultController.stream;

  // Statistics
  int _framesAnalyzed = 0;
  int _alertsGenerated = 0;
  DateTime? _lastAnalysisTime;

  // Child context
  String? _currentChildHash;
  String? _currentChildName;

  // Services
  late RealtimeAlertService _alertService;

  // AI analysis
  InferenceModel? _model;
  GemmaContentAnalyzer? _analyzer;

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
      AppLogger.logError(
        'ScreenMonitoringService initialization failed',
        e,
        stackTrace,
      );
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
        _startFrameStreaming();
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
      await _frameSubscription?.cancel();
      _frameSubscription = null;
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

        // Safety: If queue is too long, discard older frames (analysis is falling behind)
        if (_analysisQueue.length > 5) {
          AppLogger.log('⚠️ Analysis queue full, discarding oldest frame');
          final old = _analysisQueue.removeAt(0);
          try {
            File(old['path']).delete();
          } catch (_) {}
        }

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

  void _startFrameStreaming() {
    AppLogger.log('📡 Starting real-time frame streaming listener...');
    _frameSubscription?.cancel();
    _frameSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Uint8List) {
          _handleFrameReceived(event);
        }
      },
      onError: (err) {
        AppLogger.log('❌ Frame Stream Error: $err');
      },
    );
  }

  void _handleFrameReceived(Uint8List frames) {
    // Add to analysis queue (reuse existing processing logic)
    _analysisQueue.add({
      'bytes': frames,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'foregroundApp': 'Real-time Stream',
    });

    if (!_isProcessingQueue) {
      _processAnalysisQueue();
    }
  }

  /// Process the analysis queue
  Future<void> _processAnalysisQueue() async {
    if (_isProcessingQueue) return;

    _isProcessingQueue = true;

    while (_analysisQueue.isNotEmpty) {
      final item = _analysisQueue.removeAt(0);
      if (item.containsKey('bytes')) {
        await _analyzeFrameBytes(
          item['bytes'] as Uint8List,
          item['timestamp'] as int,
          item['foregroundApp'] as String?,
        );
      } else {
        await _analyzeScreenshot(
          item['path'] as String,
          item['timestamp'] as int,
          item['foregroundApp'] as String?,
        );
      }
    }

    _isProcessingQueue = false;
  }

  /// Analyze raw frame bytes (Real-time Stream)
  Future<void> _analyzeFrameBytes(
    Uint8List imageBytes,
    int timestamp,
    String? foregroundApp,
  ) async {
    final startTime = DateTime.now();
    try {
      AppLogger.log('🧠 Analyzing real-time frame bytes...');
      if (!await _ensureAnalyzerReady()) return;

      final result = await _analyzer!.analyzeImage(
        imageBytes,
        appContext: foregroundApp,
      );

      _processAnalysisResult(result, foregroundApp, startTime);
    } catch (e, st) {
      AppLogger.logError('Error analysing frame bytes', e, st);
    }
  }

  void _processAnalysisResult(
    ContentAnalysisResult result,
    String? foregroundApp,
    DateTime startTime,
  ) {
    final duration = DateTime.now().difference(startTime).inMilliseconds;
    AppLogger.log('✅ [AI] Analysis complete ($duration ms)');

    _framesAnalyzed++;
    _lastAnalysisTime = DateTime.now();

    AppLogger.log(
      '📊 Result: risk=${result.riskScore}, cats=${result.categories}',
    );

    // Emit to stream for UI updates
    _analysisResultController.add(result);

    final explicit = result.categories['explicit'] ?? 0.0;
    final violence = result.categories['violence'] ?? 0.0;
    final predatory = result.categories['predatory'] ?? 0.0;
    final suggestive = result.categories['suggestive'] ?? 0.0;

    final bool hasCategoryThreshold =
        explicit > 0.1 || violence > 0.1 || predatory > 0.1 || suggestive > 0.1;

    if (result.riskScore >= 70 || hasCategoryThreshold) {
      int effectiveRiskScore = result.riskScore;
      if (hasCategoryThreshold && result.riskScore < 70) {
        final scores = [explicit, violence, predatory, suggestive];
        double maxScore = scores.first;
        for (var score in scores) {
          if (score > maxScore) maxScore = score;
        }
        effectiveRiskScore = (maxScore * 100).toInt().clamp(70, 100);
      }

      AppLogger.log('🚨 RISK DETECTED – generating alert');
      _generateAlert(
        riskScore: effectiveRiskScore,
        scores: result.categories,
        summary: result.summary,
        foregroundApp: foregroundApp,
      );
    }
  }

  /// Ensure the Gemma model is loaded for analysis.
  Future<bool> _ensureAnalyzerReady() async {
    if (_analyzer != null) return true;
    try {
      final installed = await GemmaManager.instance.isModelInstalled();
      if (!installed) {
        AppLogger.log('⚠️ ScreenMonitoring: Gemma model not installed yet');
        return false;
      }
      if (!FlutterGemma.hasActiveModel()) {
        AppLogger.log('⚠️ ScreenMonitoring: No active model, skipping');
        return false;
      }
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        supportImage: true,
      );
      _analyzer = GemmaContentAnalyzer(_model!);
      AppLogger.log('✅ ScreenMonitoring: Gemma analyzer ready');
      return true;
    } catch (e) {
      AppLogger.log('❌ ScreenMonitoring: Failed to init analyzer: $e');
      return false;
    }
  }

  /// Analyze a screenshot with the Gemma vision model
  Future<void> _analyzeScreenshot(
    String path,
    int timestamp,
    String? foregroundApp,
  ) async {
    final startTime = DateTime.now();
    try {
      AppLogger.log(
        '🔍 [AI] [START] Analyzing frame (Queue: ${_analysisQueue.length + 1})',
      );

      final file = File(path);
      if (!await file.exists()) {
        AppLogger.log('⚠️ [AI] Screenshot file missing: $path');
        return;
      }

      final imageBytes = await file.readAsBytes();

      // Delete immediately after reading (zero-cache privacy policy)
      try {
        await file.delete();
      } catch (_) {}

      if (!await _ensureAnalyzerReady()) {
        AppLogger.log('⏭️ [AI] Skipping – model/analyzer not ready');
        return;
      }

      final result = await _analyzer!.analyzeImage(
        imageBytes,
        appContext: foregroundApp,
      );

      _processAnalysisResult(result, foregroundApp, startTime);
    } catch (e, stackTrace) {
      AppLogger.logError('Error analysing screenshot', e, stackTrace);
    }
  }

  /// Create an Alert and push it into RealtimeAlertService
  Future<void> _generateAlert({
    required int riskScore,
    required Map<String, double> scores,
    required String summary,
    String? foregroundApp,
  }) async {
    try {
      final alert = Alert(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        riskScore: riskScore,
        summary: _generateAlertSummary(riskScore, scores, foregroundApp),
        severity: Alert.determineSeverity(riskScore),
        contentType: ContentType.IMAGE,
        detectedContent: summary,
        childHash: _currentChildHash ?? '',
        childName: _currentChildName ?? 'Child',
        sourceApp: foregroundApp,
      );

      await _alertService.addAlert(alert);
      _alertsGenerated++;
      AppLogger.log('✅ Alert generated: ${alert.severity} – ${alert.id}');
    } catch (e, stackTrace) {
      AppLogger.logError('Error generating alert', e, stackTrace);
    }
  }

  String _generateAlertSummary(
    int riskScore,
    Map<String, double> scores,
    String? foregroundApp,
  ) {
    final topCategory = scores.entries.where((e) => e.value > 0.3).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final cats = topCategory.isNotEmpty
        ? topCategory.map((e) => e.key).join(', ')
        : 'general';
    final app = foregroundApp != null ? ' in $foregroundApp' : '';
    return 'Risk $riskScore%: $cats content detected$app';
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
