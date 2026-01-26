import 'dart:async';
import 'dart:developer' as developer;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/alert.dart';
import 'text_analysis_service.dart';

/// Service that executes text analysis models in the background
/// Runs on a 30-second timer interval only when in 'child' view mode
/// Analyzes recent messages and creates alerts from model scores
class BackgroundModelExecutor {
  static final BackgroundModelExecutor _instance =
      BackgroundModelExecutor._internal();

  factory BackgroundModelExecutor() {
    return _instance;
  }

  BackgroundModelExecutor._internal();

  // Singleton instance
  static BackgroundModelExecutor get instance => _instance;

  // Configuration
  static const int executionIntervalSeconds = 30;
  static const int maxRecentMessages = 10;

  // Internal state
  Timer? _executionTimer;
  Database? _database;
  bool _isRunning = false;
  bool _isInitialized = false;
  String? _currentChildHash;
  String? _currentChildName;
  int _executionCount = 0;
  DateTime? _lastExecutionTime;

  // Alert stream controller
  final StreamController<Alert> _alertController =
      StreamController<Alert>.broadcast();

  /// Stream of newly detected alerts
  Stream<Alert> get alertStream => _alertController.stream;

  /// Whether the executor is currently running
  bool get isRunning => _isRunning;

  /// Number of executions performed
  int get executionCount => _executionCount;

  /// Last execution timestamp
  DateTime? get lastExecutionTime => _lastExecutionTime;

  /// Initialize the background model executor with database
  /// Must be called before starting the executor
  Future<bool> initialize(Database db) async {
    if (_isInitialized) {
      _log('✅ BackgroundModelExecutor already initialized');
      return true;
    }

    try {
      _log('🔄 Initializing BackgroundModelExecutor...');
      _database = db;

      // Create alerts table if it doesn't exist
      await _createAlertsTable();

      _isInitialized = true;
      _log('✅ BackgroundModelExecutor initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _log('❌ BackgroundModelExecutor initialization failed: $e');
      _log('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Create alerts table in database
  Future<void> _createAlertsTable() async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      await _database!.execute('''
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
          created_at TEXT NOT NULL
        )
      ''');
      _log('✅ Alerts table created or already exists');
    } catch (e) {
      if (e.toString().contains('already exists')) {
        _log('✅ Alerts table already exists');
      } else {
        rethrow;
      }
    }
  }

  /// Start background execution with child context
  /// Only runs if [preferredViewMode] is 'child' (to be checked externally)
  /// Returns true if started successfully
  Future<bool> start({
    required String childHash,
    required String childName,
    required bool isChildViewMode,
  }) async {
    if (!_isInitialized) {
      _log('❌ BackgroundModelExecutor not initialized');
      return false;
    }

    if (_isRunning) {
      _log('⚠️  BackgroundModelExecutor already running');
      return false;
    }

    if (!isChildViewMode) {
      _log('⚠️  BackgroundModelExecutor only runs in child view mode');
      return false;
    }

    try {
      _log('🚀 Starting BackgroundModelExecutor...');
      _log('   Child Hash: $childHash');
      _log('   Child Name: $childName');
      _log('   Interval: ${executionIntervalSeconds}s');

      _currentChildHash = childHash;
      _currentChildName = childName;
      _isRunning = true;

      // Execute immediately on start
      await _executeAnalysis();

      // Set up recurring execution
      _executionTimer = Timer.periodic(
        Duration(seconds: executionIntervalSeconds),
        (_) => _executeAnalysis(),
      );

      _log('✅ BackgroundModelExecutor started successfully');
      return true;
    } catch (e, stackTrace) {
      _log('❌ Failed to start BackgroundModelExecutor: $e');
      _log('Stack trace: $stackTrace');
      _isRunning = false;
      return false;
    }
  }

  /// Stop background execution
  Future<void> stop() async {
    if (!_isRunning) {
      _log('⚠️  BackgroundModelExecutor not running');
      return;
    }

    try {
      _log('🛑 Stopping BackgroundModelExecutor...');
      _executionTimer?.cancel();
      _executionTimer = null;
      _isRunning = false;
      _currentChildHash = null;
      _currentChildName = null;
      _log('✅ BackgroundModelExecutor stopped');
    } catch (e, stackTrace) {
      _log('❌ Error stopping BackgroundModelExecutor: $e');
      _log('Stack trace: $stackTrace');
    }
  }

  /// Execute text analysis on recent messages
  Future<void> _executeAnalysis() async {
    if (!_isRunning || _currentChildHash == null || _database == null) {
      return;
    }

    final startTime = DateTime.now();
    try {
      _executionCount++;
      _lastExecutionTime = startTime;
      _log('📊 Execution #$_executionCount started at ${_formatTime(startTime)}');

      // Get text analysis service
      final textAnalysisService = TextAnalysisService.instance;
      if (!textAnalysisService.isInitialized) {
        _log('⚠️  TextAnalysisService not initialized, skipping analysis');
        return;
      }

      // In a real implementation, fetch recent messages from chat service
      // For now, this is a placeholder for the actual message fetching logic
      // TODO: Integrate with ChatService to get recent messages for the child

      // Example: Analyze hypothetical recent messages
      final recentMessages = await _getRecentMessages();
      _log('   Found ${recentMessages.length} recent messages to analyze');

      // Analyze each message
      for (final message in recentMessages) {
        try {
          final score = await textAnalysisService.analyzeText(message);
          final riskScore = (score * 100).toInt();

          // Only create alerts for significant detections (>30% confidence)
          if (riskScore >= 30) {
            final alert = Alert(
              id: const Uuid().v4(),
              timestamp: DateTime.now(),
              riskScore: riskScore,
              summary: _generateAlertSummary(message, riskScore),
              severity: Alert.determineSeverity(riskScore),
              contentType: ContentType.TEXT,
              detectedContent: message,
              childHash: _currentChildHash!,
              childName: _currentChildName ?? 'Unknown',
            );

            // Save to database
            await _saveAlert(alert);

            // Emit alert to stream
            _alertController.add(alert);

            _log('   🚨 Alert created: ${alert.severity} - '
                'Score: $riskScore - "${message.substring(0, min(50, message.length))}"...');
          }
        } catch (e) {
          _log('   ❌ Error analyzing message: $e');
        }
      }

      final duration = DateTime.now().difference(startTime);
      _log('✅ Execution #$_executionCount completed in ${duration.inMilliseconds}ms');
    } catch (e, stackTrace) {
      _log('❌ Error during analysis execution: $e');
      _log('Stack trace: $stackTrace');
    }
  }

  /// Get recent messages (placeholder - to be integrated with ChatService)
  Future<List<String>> _getRecentMessages() async {
    // TODO: Integrate with ChatService to fetch recent messages for current child
    // For MVP, return empty list - actual implementation will query chat history
    return [];
  }

  /// Save alert to local database
  Future<void> _saveAlert(Alert alert) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      await _database!.insert(
        'alerts',
        {
          'id': alert.id,
          'timestamp': alert.timestamp.toIso8601String(),
          'risk_score': alert.riskScore,
          'summary': alert.summary,
          'severity': alert.severity.toString().split('.').last,
          'content_type': alert.contentType.toString().split('.').last,
          'detected_content': alert.detectedContent,
          'child_hash': alert.childHash,
          'child_name': alert.childName,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _log('   💾 Alert saved to database');
    } catch (e) {
      _log('   ❌ Failed to save alert to database: $e');
      rethrow;
    }
  }

  /// Generate alert summary from detected content and risk score
  String _generateAlertSummary(String content, int riskScore) {
    final severity = Alert.determineSeverity(riskScore);
    final severityStr = severity.toString().split('.').last;
    final preview = content.length > 40
        ? '${content.substring(0, 40)}...'
        : content;
    return '[$severityStr] Potential risk detected: $preview';
  }

  /// Clean up resources
  void dispose() {
    _log('🧹 Disposing BackgroundModelExecutor...');
    _executionTimer?.cancel();
    _executionTimer = null;
    _alertController.close();
    _isRunning = false;
    _isInitialized = false;
    _currentChildHash = null;
    _currentChildName = null;
    _log('✅ BackgroundModelExecutor disposed');
  }

  /// Format timestamp for logging
  String _formatTime(DateTime time) {
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  /// Log message with timestamp
  void _log(String message) {
    final timestamp = DateTime.now();
    final formattedTime =
        '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final logMessage = '[$formattedTime] 🤖 $message';
    print(logMessage);
    developer.log(logMessage, name: 'BackgroundModelExecutor');
  }
}

// Helper function for string length
int min(int a, int b) => a < b ? a : b;
