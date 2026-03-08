import 'dart:async';
import 'dart:developer' as developer;
import 'package:sqflite/sqflite.dart';
import '../models/alert.dart';
import 'websocket_service.dart';
import 'api_service.dart';
import '../utils/app_logger.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../models/content_analysis_result.dart';
/// Service that manages real-time alerts from multiple sources
/// Listens to background model detections and WebSocket alerts from parent devices
/// Provides a unified alerts stream and database persistence
class RealtimeAlertService {
  static final RealtimeAlertService _instance =
      RealtimeAlertService._internal();

  factory RealtimeAlertService() {
    return _instance;
  }

  RealtimeAlertService._internal();

  // Singleton instance
  static RealtimeAlertService get instance => _instance;

  // Internal state
  Database? _database;
  bool _isInitialized = false;
  String? _currentChildHash;
  StreamSubscription? _websocketSubscription;

  // Controllers
  final StreamController<Alert> _alertController =
      StreamController<Alert>.broadcast();
  final StreamController<int> _alertCountController =
      StreamController<int>.broadcast();

  /// Unified stream of all detected alerts
  Stream<Alert> get alertStream => _alertController.stream;

  /// Stream of alert count updates
  Stream<int> get alertCountStream => _alertCountController.stream;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the realtime alert service
  Future<bool> initialize(
    Database db,
    WebSocketService webSocketService,
  ) async {
    if (_isInitialized) {
      _log('✅ RealtimeAlertService already initialized');
      return true;
    }

    try {
      _log('🔄 Initializing RealtimeAlertService...');
      _database = db;

      // Create alerts table if needed
      await _createAlertsTable();

      // Listen to WebSocket alerts
      _websocketSubscription =
          webSocketService.messages.listen(_onWebSocketMessage);
          
      // Listen to Background Service alerts
      FlutterBackgroundService().on('alertGenerated').listen((event) {
        if (event != null) {
          try {
            _log('🚨 Received alert from background isolate!');
            final alertResult = ContentAnalysisResult.fromJson(event.cast<String, dynamic>());
            final alert = Alert(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              timestamp: DateTime.now(),
              riskScore: alertResult.riskScore,
              severity: alertResult.riskScore >= 90 ? AlertSeverity.HIGH : AlertSeverity.MEDIUM,
              summary: 'Detected High Risk Content',
              contentType: ContentType.IMAGE,
              childName: 'Child',
              childHash: _currentChildHash ?? 'unknown',
              detectedContent: alertResult.categories.toString(),
            );
            addAlert(alert);
          } catch (e) {
            _log('❌ Error parsing background alert: $e');
          }
        }
      });

      _isInitialized = true;
      _log('✅ RealtimeAlertService initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _log('❌ RealtimeAlertService initialization failed: $e');
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
          created_at TEXT NOT NULL,
          source TEXT NOT NULL
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

  /// Set the current child context
  void setCurrentChild(String childHash, String childName) {
    _currentChildHash = childHash;
    _log('📍 Current child set: $childName ($childHash)');
  }

  /// Add a new alert to the system
  /// Stores in database and emits to stream
  Future<void> addAlert(Alert alert) async {
    if (!_isInitialized || _database == null) {
      _log('❌ RealtimeAlertService not initialized');
      return;
    }

    try {
      // Filter by current child if set
      if (_currentChildHash != null &&
          alert.childHash != _currentChildHash) {
        _log('⊘ Alert filtered (different child): ${alert.childHash}');
        return;
      }

      // Save to database
      await _saveAlert(alert, 'model');

      // Emit to stream
      _alertController.add(alert);

      // Update alert count
      await _updateAlertCount();

      _log('✅ Alert added: ${alert.severity} - '
          '${alert.summary.substring(0, min(50, alert.summary.length))}');
    } catch (e, stackTrace) {
      _log('❌ Error adding alert: $e');
      _log('Stack trace: $stackTrace');
    }
  }

  /// Handle alert from background model executor
  // void _onModelAlert(Alert alert) {
  //   _log('🤖 Alert from model: ${alert.severity} - ${alert.id}');
  //   addAlert(alert);
  // }

  /// Handle message from WebSocket
  void _onWebSocketMessage(Map<String, dynamic> message) {
    try {
      // Check if this is an alert message
      if (message['type'] != 'alert') {
        return;
      }

      // Only process alerts from parent (trusted source)
      if (message['source'] != 'parent' && message['source'] != 'parent_device') {
        _log('⊘ Alert from untrusted source: ${message['source']}');
        return;
      }

      // Create Alert from message
      final alertData = message['data'] as Map<String, dynamic>?;
      if (alertData == null) {
        _log('⚠️  WebSocket alert message missing data field');
        return;
      }

      final alert = Alert.fromJson(alertData);

      // Validate this alert is for our child
      if (_currentChildHash != null &&
          alert.childHash != _currentChildHash) {
        _log('⊘ WebSocket alert filtered (different child): ${alert.childHash}');
        return;
      }

      _log('📡 Alert received from parent device: ${alert.severity}');
      _saveAlert(alert, 'websocket');
      _alertController.add(alert);
      _updateAlertCount();
    } catch (e, stackTrace) {
      _log('❌ Error processing WebSocket alert: $e');
      _log('Stack trace: $stackTrace');
    }
  }

  /// Save alert to database with source
  Future<void> _saveAlert(Alert alert, String source) async {
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
          'source': source,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      _log('⚠️  Failed to save alert to database: $e');
    }
  }

  /// Get all alerts from database
  /// Optionally filtered by child hash
  Future<List<Alert>> getAlerts({String? childHash}) async {
    if (!_isInitialized || _database == null) {
      _log('❌ RealtimeAlertService not initialized');
      return [];
    }

    try {
      String query = 'SELECT * FROM alerts ORDER BY timestamp DESC';
      List<dynamic> args = [];

      // Filter by current child or specified child
      final filterHash = childHash ?? _currentChildHash;
      if (filterHash != null) {
        query += ' WHERE child_hash = ?';
        args.add(filterHash);
      }

      final results = await _database!.rawQuery(query, args);
      return results
          .map((row) => Alert.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e, stackTrace) {
      _log('❌ Error fetching alerts: $e');
      _log('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get recent alerts (last N)
  Future<List<Alert>> getRecentAlerts({
    int limit = 50,
    String? childHash,
  }) async {
    if (!_isInitialized || _database == null) {
      _log('❌ RealtimeAlertService not initialized');
      return [];
    }

    try {
      String query = 'SELECT * FROM alerts ORDER BY timestamp DESC LIMIT ?';
      List<dynamic> args = [limit];

      // Filter by current child or specified child
      final filterHash = childHash ?? _currentChildHash;
      if (filterHash != null) {
        query = 'SELECT * FROM alerts WHERE child_hash = ? '
            'ORDER BY timestamp DESC LIMIT ?';
        args = [filterHash, limit];
      }

      final results = await _database!.rawQuery(query, args);
      return results
          .map((row) => Alert.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e, stackTrace) {
      _log('❌ Error fetching recent alerts: $e');
      _log('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get alerts filtered by severity
  Future<List<Alert>> getAlertsBySeverity(AlertSeverity severity,
      {String? childHash}) async {
    if (!_isInitialized || _database == null) {
      _log('❌ RealtimeAlertService not initialized');
      return [];
    }

    try {
      final severityStr = severity.toString().split('.').last;
      String query = 'SELECT * FROM alerts WHERE severity = ? '
          'ORDER BY timestamp DESC';
      List<dynamic> args = [severityStr];

      // Filter by current child or specified child
      final filterHash = childHash ?? _currentChildHash;
      if (filterHash != null) {
        query = 'SELECT * FROM alerts WHERE severity = ? AND child_hash = ? '
            'ORDER BY timestamp DESC';
        args = [severityStr, filterHash];
      }

      final results = await _database!.rawQuery(query, args);
      return results
          .map((row) => Alert.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e, stackTrace) {
      _log('❌ Error fetching alerts by severity: $e');
      _log('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Get alerts in date range
  Future<List<Alert>> getAlertsInDateRange(
    DateTime start,
    DateTime end, {
    String? childHash,
  }) async {
    if (!_isInitialized || _database == null) {
      _log('❌ RealtimeAlertService not initialized');
      return [];
    }

    try {
      String query = 'SELECT * FROM alerts WHERE timestamp >= ? AND timestamp <= ? '
          'ORDER BY timestamp DESC';
      List<dynamic> args = [
        start.toIso8601String(),
        end.toIso8601String(),
      ];

      // Filter by current child or specified child
      final filterHash = childHash ?? _currentChildHash;
      if (filterHash != null) {
        query = 'SELECT * FROM alerts WHERE timestamp >= ? AND timestamp <= ? '
            'AND child_hash = ? ORDER BY timestamp DESC';
        args = [
          start.toIso8601String(),
          end.toIso8601String(),
          filterHash,
        ];
      }

      final results = await _database!.rawQuery(query, args);
      return results
          .map((row) => Alert.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e, stackTrace) {
      _log('❌ Error fetching alerts in date range: $e');
      _log('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Delete alert by ID
  Future<bool> deleteAlert(String alertId) async {
    if (!_isInitialized || _database == null) {
      _log('❌ RealtimeAlertService not initialized');
      return false;
    }

    try {
      final count = await _database!
          .delete('alerts', where: 'id = ?', whereArgs: [alertId]);
      if (count > 0) {
        await _updateAlertCount();
        _log('✅ Alert deleted: $alertId');
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      _log('❌ Error deleting alert: $e');
      _log('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Clear all alerts for current child
  Future<bool> clearAlerts({String? childHash}) async {
    if (!_isInitialized || _database == null) {
      _log('❌ RealtimeAlertService not initialized');
      return false;
    }

    try {
      final filterHash = childHash ?? _currentChildHash;
      if (filterHash == null) {
        _log('⚠️  No child hash specified');
        return false;
      }

      final count = await _database!
          .delete('alerts', where: 'child_hash = ?', whereArgs: [filterHash]);
      await _updateAlertCount();
      _log('✅ Cleared $count alerts');
      return true;
    } catch (e, stackTrace) {
      _log('❌ Error clearing alerts: $e');
      _log('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Get count of alerts for current child
  Future<int> getAlertCount({String? childHash}) async {
    if (!_isInitialized || _database == null) {
      _log('❌ RealtimeAlertService not initialized');
      return 0;
    }

    try {
      final filterHash = childHash ?? _currentChildHash;
      String query = 'SELECT COUNT(*) as count FROM alerts';
      List<dynamic> args = [];

      if (filterHash != null) {
        query += ' WHERE child_hash = ?';
        args.add(filterHash);
      }

      final result = await _database!.rawQuery(query, args);
      return (result.first['count'] as int?) ?? 0;
    } catch (e, stackTrace) {
      _log('❌ Error getting alert count: $e');
      _log('Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Update alert count in stream
  Future<void> _updateAlertCount() async {
    try {
      final count = await getAlertCount();
      _alertCountController.add(count);
    } catch (e) {
      _log('⚠️  Error updating alert count: $e');
    }
  }

  /// Sync new alerts via HTTP to server
  /// This is called to send locally detected alerts to the backend
  Future<void> syncAlertToServer(Alert alert, ApiService apiService, String childName) async {
    try {
      final result = await apiService.sendAIAlert(
        childHash: alert.childHash,
        alertId: alert.id,
        timestamp: alert.timestamp.toIso8601String(),
        riskScore: alert.riskScore,
        severity: alert.severity.toString().split('.').last,
        contentType: alert.contentType.toString().split('.').last,
        summary: alert.summary,
        childName: childName,
        detectedContent: alert.detectedContent,
        sourceApp: alert.sourceApp,
      );
      
      if (result['success'] == true) {
        _log('✅ Alert synced to server: ${alert.id}');
      } else {
        _log('⚠️ Failed to sync alert to server: ${result['error']}');
      }
    } catch (e, stackTrace) {
      _log('❌ Error syncing alert to server: $e');
      _log('Stack trace: $stackTrace');
    }
  }

  /// Fetch alerts from server (for Guardian app)
  /// Uses the new API endpoint: GET /api/mobile/child/<child_hash>/alerts/
  Future<List<Alert>> fetchAlertsFromServer({
    required ApiService apiService,
    required String email,
    required String password,
    required String childHash,
    String? startDate,
    String? endDate,
    String? severity,
    String? contentType,
    int limit = 50,
  }) async {
    try {
      _log('📡 Fetching alerts from server for child: $childHash');
      
      final result = await apiService.fetchAIAlerts(
        email: email,
        password: password,
        childHash: childHash,
        startDate: startDate,
        endDate: endDate,
        severity: severity,
        contentType: contentType,
        limit: limit,
      );
      
      if (result['success'] == true) {
        final alertsList = result['alerts'] as List? ?? [];
        final alerts = alertsList
            .map((alertData) => Alert.fromJson(alertData as Map<String, dynamic>))
            .toList();
        
        _log('✅ Fetched ${alerts.length} alerts from server');
        return alerts;
      } else {
        _log('⚠️ Failed to fetch alerts from server: ${result['error']}');
        return [];
      }
    } catch (e, stackTrace) {
      _log('❌ Error fetching alerts from server: $e');
      _log('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Acknowledge an alert on the server (for Guardian app)
  Future<bool> acknowledgeAlertOnServer({
    required ApiService apiService,
    required String email,
    required String password,
    required String childHash,
    required String alertId,
  }) async {
    try {
      _log('📤 Acknowledging alert on server: $alertId');
      
      final result = await apiService.acknowledgeAlert(
        email: email,
        password: password,
        childHash: childHash,
        alertId: alertId,
      );
      
      if (result['success'] == true) {
        _log('✅ Alert acknowledged on server: $alertId');
        return true;
      } else {
        _log('⚠️ Failed to acknowledge alert: ${result['error']}');
        return false;
      }
    } catch (e, stackTrace) {
      _log('❌ Error acknowledging alert: $e');
      _log('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Clean up resources
  void dispose() {
    _log('🧹 Disposing RealtimeAlertService...');
    _websocketSubscription?.cancel();
    _alertController.close();
    _alertCountController.close();
    _isInitialized = false;
    _currentChildHash = null;
    _log('✅ RealtimeAlertService disposed');
  }

  /// Log message with timestamp
  void _log(String message) {
    AppLogger.log('[RealtimeAlertService] $message');
  }
}

// Helper function for string length
int min(int a, int b) => a < b ? a : b;
