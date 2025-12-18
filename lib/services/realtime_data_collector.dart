import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:intl/intl.dart';
import '../services/websocket_service.dart';
import '../models/websocket_data.dart';

/// Real-time data collector and sender
/// This service continuously collects and sends data via WebSocket
class RealTimeDataCollector {
  final WebSocketService _wsService;
  final String _childHash;
  
  Timer? _screenTimeTimer;
  Timer? _locationTimer;
  Timer? _websiteTimer;
  
  bool _isRunning = false;
  
  RealTimeDataCollector({
    required WebSocketService webSocketService,
    required String childHash,
  })  : _wsService = webSocketService,
        _childHash = childHash;
  
  /// Start real-time data collection and sending
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('🔄 RealTimeCollector: Already running');
      return;
    }
    
    debugPrint('🚀 RealTimeCollector: Starting real-time data collection');
    _isRunning = true;
    
    // Connect WebSocket
    await _wsService.connect(_childHash);
    
    // Start periodic data collection
    _startScreenTimeCollection();
    _startLocationCollection();
    _startWebsiteCollection();
  }
  
  /// Stop data collection
  void stop() {
    debugPrint('⏹️ RealTimeCollector: Stopping');
    _screenTimeTimer?.cancel();
    _locationTimer?.cancel();
    _websiteTimer?.cancel();
    _isRunning = false;
  }
  
  /// Collect and send screen time every 10 seconds
  void _startScreenTimeCollection() {
    _screenTimeTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) async {
        try {
          await _collectAndSendScreenTime();
        } catch (e) {
          debugPrint('❌ Error collecting screen time: $e');
        }
      },
    );
  }
  
  /// Collect and send location every 30 seconds
  void _startLocationCollection() {
    _locationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) async {
        try {
          await _collectAndSendLocation();
        } catch (e) {
          debugPrint('❌ Error collecting location: $e');
        }
      },
    );
  }
  
  /// Collect and send website access every 15 seconds
  void _startWebsiteCollection() {
    _websiteTimer = Timer.periodic(
      const Duration(seconds: 15),
      (timer) async {
        try {
          await _collectAndSendWebsites();
        } catch (e) {
          debugPrint('❌ Error collecting websites: $e');
        }
      },
    );
  }
  
  /// Collect screen time data from UsageStats
  Future<void> _collectAndSendScreenTime() async {
    try {
      final endDate = DateTime.now();
      final startDate = DateTime(endDate.year, endDate.month, endDate.day);
      
      // Get usage stats for today
      final stats = await UsageStats.queryUsageStats(
        startDate,
        endDate,
      );
      
      if (stats.isEmpty) {
        debugPrint('⚠️ No screen time data available');
        return;
      }
      
      // Calculate total screen time and app-wise breakdown
      int totalScreenTime = 0;
      final appWiseData = <String, Map<String, int>>{};
      
      for (final stat in stats) {
        final packageName = stat.packageName ?? 'unknown';
        final usageTime = int.parse(stat.totalTimeInForeground ?? '0') ~/ 1000; // Convert to seconds
        
        if (usageTime > 0) {
          totalScreenTime += usageTime;
          
          // Get the hour of usage (simplified - you may want more accurate hourly breakdown)
          final hour = DateTime.now().hour.toString().padLeft(2, '0');
          
          appWiseData[packageName] = {
            hour: usageTime,
          };
        }
      }
      
      if (totalScreenTime == 0) {
        debugPrint('⚠️ Total screen time is 0');
        return;
      }
      
      // Send via WebSocket
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      debugPrint('📱 Sending screen time: ${totalScreenTime}s, ${appWiseData.length} apps');
      
      await _wsService.sendScreenTime(
        date: dateStr,
        totalScreenTime: totalScreenTime,
        appWiseData: appWiseData,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to collect screen time: $e');
    }
  }
  
  /// Collect location data from Geolocator
  Future<void> _collectAndSendLocation() async {
    try {
      // Check location permission
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ Location permission denied');
        return;
      }
      
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      debugPrint('📍 Sending location: ${position.latitude}, ${position.longitude}');
      
      await _wsService.sendLocation(
        timestamp: DateTime.now().toUtc().toIso8601String(),
        latitude: position.latitude,
        longitude: position.longitude,
      );
      
    } catch (e) {
      debugPrint('❌ Failed to collect location: $e');
    }
  }
  
  /// Collect website access logs (placeholder - implement based on your tracking method)
  Future<void> _collectAndSendWebsites() async {
    try {
      // TODO: Implement your website tracking logic here
      // This is a placeholder showing the structure
      
      final logs = <Map<String, dynamic>>[];
      
      // Example: Get recent website visits from your tracking system
      // Replace this with your actual implementation
      final recentVisits = await _getRecentWebsiteVisits();
      
      for (final visit in recentVisits) {
        logs.add({
          'timestamp': visit['timestamp'],
          'url': visit['url'],
          'accessed': visit['accessed'] ?? true,
        });
      }
      
      if (logs.isNotEmpty) {
        debugPrint('🌐 Sending ${logs.length} website access logs');
        await _wsService.sendSiteAccess(logs: logs);
      }
      
    } catch (e) {
      debugPrint('❌ Failed to collect websites: $e');
    }
  }
  
  /// Placeholder for website visit tracking
  Future<List<Map<String, dynamic>>> _getRecentWebsiteVisits() async {
    // TODO: Implement your website tracking logic
    // This could come from VPN logs, browser history, etc.
    
    // For now, return empty list
    return [];
  }
  
  /// Get current connection status
  bool get isConnected => _wsService.isConnected;
  
  /// Get WebSocket status
  WebSocketStatus get status => _wsService.status;
  
  /// Get buffered message count
  int get bufferedCount => _wsService.bufferedMessageCount;
}
