import 'package:flutter/foundation.dart';
import '../models/content_analysis_result.dart';

/// Service to synchronize high-risk content alerts to a Parent Dashboard.
/// This simulates real-time alerting and provides hooks for backend integration.
class AlertSyncService {
  static final AlertSyncService _instance = AlertSyncService._internal();

  factory AlertSyncService() {
    return _instance;
  }

  AlertSyncService._internal();

  /// Callback when an alert is generated (for UI integration)
  final List<Function(ContentAnalysisResult result, String context)> _alertCallbacks = [];

  /// Register a callback to be called when an alert is generated
  void addAlertCallback(Function(ContentAnalysisResult result, String context) callback) {
    _alertCallbacks.add(callback);
  }

  /// Remove a callback
  void removeAlertCallback(Function(ContentAnalysisResult result, String context) callback) {
    _alertCallbacks.remove(callback);
  }

  /// Synchronizes a high-risk alert to the Parent Dashboard.
  /// Only syncs alerts with riskScore > 70.
  Future<void> syncAlert(ContentAnalysisResult result, String context) async {
    if (result.riskScore <= 70) return; // Only sync high-risk items

    debugPrint('\n======================================================');
    debugPrint('🚨 [ALERT SYNC] HIGH RISK CONTENT DETECTED 🚨');
    debugPrint('======================================================');
    debugPrint('Risk Score: ${result.riskScore}/100');
    debugPrint('Summary: ${result.summary}');
    debugPrint('Context: $context');
    debugPrint('Categories:');
    result.categories.forEach((key, value) {
      if (value > 0) {
        debugPrint('  - $key: ${(value * 100).toStringAsFixed(0)}%');
      }
    });
    debugPrint(
      'Syncing to Parent Dashboard backend via hypothetical API...\n\n',
    );

    // Notify all registered callbacks
    for (final callback in _alertCallbacks) {
      try {
        callback(result, context);
      } catch (e) {
        debugPrint('Error in alert callback: $e');
      }
    }

    // TODO: In a real implementation, integrate with backend:
    // await Dio().post(
    //   'https://api.parent-dashboard.com/alerts',
    //   data: {
    //     'risk_score': result.riskScore,
    //     'summary': result.summary,
    //     'categories': result.categories,
    //     'context': context,
    //     'timestamp': DateTime.now().toIso8601String(),
    //   },
    // );
  }

  /// Clear all registered callbacks
  void clearCallbacks() {
    _alertCallbacks.clear();
  }
}
