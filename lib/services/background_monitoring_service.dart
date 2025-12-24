import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class BackgroundMonitoringService {
  static const platform = MethodChannel('com.example.guardian_ai/monitoring_service');
  
  /// Start the background monitoring service
  static Future<bool> start() async {
    try {
      final result = await platform.invokeMethod('startMonitoring');
      debugPrint('🔔 Background monitoring service started');
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to start monitoring service: $e');
      return false;
    }
  }
  
  /// Stop the background monitoring service
  static Future<bool> stop() async {
    try {
      final result = await platform.invokeMethod('stopMonitoring');
      debugPrint('🔕 Background monitoring service stopped');
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to stop monitoring service: $e');
      return false;
    }
  }
  
  /// Update restrictions in the background service
  static Future<bool> updateRestrictions(Map<String, dynamic> restrictions) async {
    try {
      final result = await platform.invokeMethod('updateRestrictions', {
        'restrictions': restrictions,
      });
      debugPrint('📋 Updated restrictions in background service: ${restrictions.length} apps');
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to update restrictions: $e');
      return false;
    }
  }
}
