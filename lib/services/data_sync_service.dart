import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'websocket_service.dart';
import 'api_service.dart';
import '../models/websocket_data.dart';

/// Unified data sync service that uses WebSocket with HTTP fallback
class DataSyncService extends ChangeNotifier {
  final WebSocketService _webSocketService;
  final ApiService _apiService;
  
  String? _childHash;
  bool _preferWebSocket = true;
  double? _lastLatitude;
  double? _lastLongitude;
  
  DataSyncService({
    required WebSocketService webSocketService,
    required ApiService apiService,
  })  : _webSocketService = webSocketService,
        _apiService = apiService {
    // Listen to WebSocket status changes
    _webSocketService.addListener(_onWebSocketStatusChanged);
  }
  
  bool get isConnected => _webSocketService.isConnected;
  WebSocketStatus get connectionStatus => _webSocketService.status;
  
  /// Initialize connection with child hash
  Future<void> initialize(String childHash) async {
    _childHash = childHash;
    
    if (_preferWebSocket) {
      debugPrint('🔄 DataSync: Initializing WebSocket connection');
      await _webSocketService.connect(childHash);
    }
  }
  
  /// Handle WebSocket status changes
  void _onWebSocketStatusChanged() {
    if (_webSocketService.status == WebSocketStatus.failed) {
      debugPrint('⚠️ DataSync: WebSocket failed, will use HTTP fallback');
    } else if (_webSocketService.status == WebSocketStatus.connected) {
      debugPrint('✅ DataSync: WebSocket connected, resuming real-time sync');
    }
    notifyListeners();
  }
  
  /// Send screen time data (WebSocket preferred, HTTP fallback)
  Future<bool> sendScreenTime({
    required String date,
    required int totalScreenTime,
    required Map<String, Map<String, int>> appWiseData,
    int? timezoneOffsetMinutes,
    String? timezoneName,
  }) async {
    final screenTimeData = ScreenTimeData(
      date: date,
      totalScreenTime: totalScreenTime,
      appWiseData: appWiseData,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      timezoneName: timezoneName,
    );
    
    // Try WebSocket first
    if (_webSocketService.isConnected) {
      debugPrint('📡 DataSync: Sending screen time via WebSocket');
      final success = await _webSocketService.sendScreenTime(
        date: date,
        totalScreenTime: totalScreenTime,
        appWiseData: appWiseData,
        timezoneOffsetMinutes: timezoneOffsetMinutes,
        timezoneName: timezoneName,
      );
      
      if (success) return true;
      debugPrint('⚠️ DataSync: WebSocket send failed, falling back to HTTP');
    }
    
    // Fallback to HTTP
    if (_childHash == null) {
      debugPrint('❌ DataSync: Cannot send without child hash');
      return false;
    }
    
    debugPrint('📡 DataSync: Sending screen time via HTTP');
    final result = await _apiService.sendDataViaHttp(
      childHash: _childHash!,
      screenTimeData: screenTimeData,
    );
    
    return result['success'] ?? false;
  }
  
  /// Send location data (WebSocket preferred, HTTP fallback)
  Future<bool> sendLocation({
    required double latitude,
    required double longitude,
  }) async {
    // Check if we have moved at least 5 meters since last update
    if (_lastLatitude != null && _lastLongitude != null) {
      double distance = Geolocator.distanceBetween(
        _lastLatitude!,
        _lastLongitude!,
        latitude,
        longitude,
      );

      if (distance < 5.0) {
        debugPrint('📡 DataSync: Location update skipped (moved ${distance.toStringAsFixed(2)}m)');
        return true; // Consider it a "success" because no sync was needed
      }
    }

    final timestamp = DateTime.now().toUtc().toIso8601String();
    final locationData = LocationData(
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
    );
    
    // Try WebSocket first
    if (_webSocketService.isConnected) {
      debugPrint('📡 DataSync: Sending location via WebSocket');
      final success = await _webSocketService.sendLocation(
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
      );
      
      if (success) {
        _lastLatitude = latitude;
        _lastLongitude = longitude;
        return true;
      }
      debugPrint('⚠️ DataSync: WebSocket send failed, falling back to HTTP');
    }
    
    // Fallback to HTTP
    if (_childHash == null) {
      debugPrint('❌ DataSync: Cannot send without child hash');
      return false;
    }
    
    debugPrint('📡 DataSync: Sending location via HTTP');
    final result = await _apiService.sendDataViaHttp(
      childHash: _childHash!,
      locationData: locationData,
    );
    
    if (result['success'] == true) {
      _lastLatitude = latitude;
      _lastLongitude = longitude;
    }
    
    return result['success'] ?? false;
  }
  
  /// Send site access logs (WebSocket preferred, HTTP fallback)
  Future<bool> sendSiteAccess({
    required List<SiteAccessLog> logs,
  }) async {
    final siteAccessData = SiteAccessData(logs: logs);
    
    // Try WebSocket first
    if (_webSocketService.isConnected) {
      debugPrint('📡 DataSync: Sending site access via WebSocket');
      final success = await _webSocketService.sendSiteAccess(
        logs: logs.map((log) => log.toJson()).toList(),
      );
      
      if (success) return true;
      debugPrint('⚠️ DataSync: WebSocket send failed, falling back to HTTP');
    }
    
    // Fallback to HTTP
    if (_childHash == null) {
      debugPrint('❌ DataSync: Cannot send without child hash');
      return false;
    }
    
    debugPrint('📡 DataSync: Sending site access via HTTP');
    final result = await _apiService.sendDataViaHttp(
      childHash: _childHash!,
      siteAccessData: siteAccessData,
    );
    
    return result['success'] ?? false;
  }
  
  /// Send all data types at once
  Future<Map<String, bool>> sendAllData({
    ScreenTimeData? screenTimeData,
    LocationData? locationData,
    SiteAccessData? siteAccessData,
  }) async {
    final results = <String, bool>{};
    
    if (screenTimeData != null) {
      results['screen_time'] = await sendScreenTime(
        date: screenTimeData.date,
        totalScreenTime: screenTimeData.totalScreenTime,
        appWiseData: screenTimeData.appWiseData,
      );
    }
    
    if (locationData != null) {
      results['location'] = await sendLocation(
        latitude: locationData.latitude,
        longitude: locationData.longitude,
      );
    }
    
    if (siteAccessData != null) {
      results['site_access'] = await sendSiteAccess(
        logs: siteAccessData.logs,
      );
    }
    
    return results;
  }
  
  /// Retry WebSocket connection
  Future<void> retryConnection() async {
    if (_childHash != null) {
      await _webSocketService.retry();
    }
  }
  
  /// Get buffered message count
  int get bufferedMessageCount => _webSocketService.bufferedMessageCount;
  
  /// Disconnect
  Future<void> disconnect() async {
    await _webSocketService.disconnect();
  }
  
  @override
  void dispose() {
    _webSocketService.removeListener(_onWebSocketStatusChanged);
    super.dispose();
  }
}
