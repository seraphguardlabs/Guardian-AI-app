import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

enum WebSocketStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

class WebSocketService extends ChangeNotifier {
  static const String wsBaseUrl = 'wss://seraphguardlabs.com/ws/ingest';
  static const String wsRestrictionsUrl = 'wss://seraphguardlabs.com/ws/restrictions';
  static const int maxReconnectAttempts = 5;
  static const int initialReconnectDelay = 1000; // milliseconds
  
  WebSocketChannel? _channel;
  WebSocketChannel? _restrictionsChannel;
  WebSocketStatus _status = WebSocketStatus.disconnected;
  WebSocketStatus _restrictionsStatus = WebSocketStatus.disconnected;
  String? _childHash;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _restrictionsHeartbeatTimer;
  
  final List<Map<String, dynamic>> _messageBuffer = [];
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _restrictionsController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  WebSocketStatus get status => _status;
  WebSocketStatus get restrictionsStatus => _restrictionsStatus;
  String? get childHash => _childHash;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<Map<String, dynamic>> get restrictions => _restrictionsController.stream;
  bool get isConnected => _status == WebSocketStatus.connected;
  bool get isRestrictionsConnected => _restrictionsStatus == WebSocketStatus.connected;
  
  /// Connect to WebSocket with child hash
  Future<void> connect(String childHash) async {
    if (_status == WebSocketStatus.connected && _childHash == childHash) {
      debugPrint('🔌 WebSocket: Already connected to $childHash');
      return;
    }
    
    _childHash = childHash;
    await _disconnect();
    await _establishConnection();
    await _establishRestrictionsConnection();
  }
  
  /// Establish WebSocket connection
  Future<void> _establishConnection() async {
    if (_childHash == null) {
      debugPrint('❌ WebSocket: Cannot connect without child hash');
      return;
    }
    
    _updateStatus(WebSocketStatus.connecting);
    
    try {
      final uri = Uri.parse('$wsBaseUrl/$_childHash/');
      debugPrint('🔌 WebSocket: Connecting to $uri');
      
      _channel = WebSocketChannel.connect(uri);
      
      // Listen for messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnected,
        cancelOnError: false,
      );
      
      // Start heartbeat
      _startHeartbeat();
      
      _reconnectAttempts = 0;
      _updateStatus(WebSocketStatus.connected);
      debugPrint('✅ WebSocket: Connected successfully');
      
      // Send any buffered messages
      await _sendBufferedMessages();
      
    } catch (e) {
      debugPrint('❌ WebSocket: Connection failed: $e');
      _updateStatus(WebSocketStatus.failed);
      await _scheduleReconnect();
    }
  }
  
  /// Handle incoming messages
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      debugPrint('📥 WebSocket: Received: ${data['type']}');
      
      // Handle different message types
      switch (data['type']) {
        case 'connection_established':
          debugPrint('✅ WebSocket: Connection acknowledged by server');
          break;
        case 'ack':
          debugPrint('✅ WebSocket: Message acknowledged: ${data['message_type']}');
          break;
        case 'error':
          debugPrint('❌ WebSocket: Server error: ${data['message']}');
          break;
        case 'pong':
          debugPrint('💓 WebSocket: Heartbeat response received');
          break;
        default:
          debugPrint('📨 WebSocket: Unknown message type: ${data['type']}');
      }
      
      _messageController.add(data);
      
    } catch (e) {
      debugPrint('❌ WebSocket: Failed to parse message: $e');
    }
  }
  
  /// Handle incoming restrictions messages
  void _onRestrictionsMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      debugPrint('📥 WSS Restrictions: Received: ${data['type']}');
      
      // Handle different message types
      switch (data['type']) {
        case 'connection_established':
          debugPrint('✅ WSS Restrictions: Connection acknowledged by server');
          break;
        case 'restrictions_update':
          debugPrint('🚫 WSS Restrictions: Restrictions updated');
          final restrictedApps = data['restricted_apps'] as Map<String, dynamic>? ?? {};
          debugPrint('📋 Restricted apps count: ${restrictedApps.length}');
          _restrictionsController.add(data);
          break;
        case 'pong':
          debugPrint('💓 WSS Restrictions: Heartbeat response received');
          break;
        default:
          debugPrint('📨 WSS Restrictions: Unknown message type: ${data['type']}');
      }
      
    } catch (e) {
      debugPrint('❌ WSS Restrictions: Failed to parse message: $e');
    }
  }
  
  /// Handle errors
  void _onError(error) {
    debugPrint('❌ WebSocket: Error: $error');
    _updateStatus(WebSocketStatus.failed);
  }
  
  /// Handle disconnection
  void _onDisconnected() {
    debugPrint('🔌 WebSocket: Disconnected');
    _stopHeartbeat();
    _updateStatus(WebSocketStatus.disconnected);
    _scheduleReconnect();
  }
  
  /// Handle restrictions disconnection
  void _onRestrictionsDisconnected() {
    debugPrint('🔌 WSS Restrictions: Disconnected');
    _stopRestrictionsHeartbeat();
    _updateRestrictionsStatus(WebSocketStatus.disconnected);
  }
  
  /// Establish restrictions WebSocket connection
  Future<void> _establishRestrictionsConnection() async {
    if (_childHash == null) {
      debugPrint('❌ WSS Restrictions: Cannot connect without child hash');
      return;
    }
    
    _updateRestrictionsStatus(WebSocketStatus.connecting);
    
    try {
      final uri = Uri.parse('$wsRestrictionsUrl/$_childHash/');
      debugPrint('🔌 WSS Restrictions: Connecting to $uri');
      
      _restrictionsChannel = WebSocketChannel.connect(uri);
      
      // Listen for messages
      _restrictionsChannel!.stream.listen(
        _onRestrictionsMessage,
        onError: (error) {
          debugPrint('❌ WSS Restrictions: Error: $error');
          _updateRestrictionsStatus(WebSocketStatus.failed);
        },
        onDone: _onRestrictionsDisconnected,
        cancelOnError: false,
      );
      
      // Start heartbeat
      _startRestrictionsHeartbeat();
      
      _updateRestrictionsStatus(WebSocketStatus.connected);
      debugPrint('✅ WSS Restrictions: Connected successfully');
      
    } catch (e) {
      debugPrint('❌ WSS Restrictions: Connection failed: $e');
      _updateRestrictionsStatus(WebSocketStatus.failed);
    }
  }
  
  /// Schedule reconnection with exponential backoff
  Future<void> _scheduleReconnect() async {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      debugPrint('❌ WebSocket: Max reconnection attempts reached');
      _updateStatus(WebSocketStatus.failed);
      return;
    }
    
    _reconnectAttempts++;
    final delay = initialReconnectDelay * (1 << (_reconnectAttempts - 1));
    
    debugPrint('🔄 WebSocket: Reconnecting in ${delay}ms (attempt $_reconnectAttempts/$maxReconnectAttempts)');
    _updateStatus(WebSocketStatus.reconnecting);
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _establishConnection();
    });
  }
  
  /// Send screen time data
  Future<bool> sendScreenTime({
    required String date,
    required int totalScreenTime,
    required Map<String, Map<String, int>> appWiseData,
    int? timezoneOffsetMinutes,
    String? timezoneName,
  }) async {
    final message = {
      'type': 'screen_time',
      'data': {
        'date': date,
        'total_screen_time': totalScreenTime,
        'app_wise_data': appWiseData,
        if (timezoneOffsetMinutes != null) 'timezone_offset_minutes': timezoneOffsetMinutes,
        if (timezoneName != null) 'timezone_name': timezoneName,
      },
    };
    
    return await _sendMessage(message);
  }
  
  /// Send location data
  Future<bool> sendLocation({
    required String timestamp,
    required double latitude,
    required double longitude,
  }) async {
    final message = {
      'type': 'location',
      'data': {
        'timestamp': timestamp,
        'latitude': latitude,
        'longitude': longitude,
      },
    };
    
    return await _sendMessage(message);
  }
  
  /// Send site access logs
  Future<bool> sendSiteAccess({
    required List<Map<String, dynamic>> logs,
  }) async {
    final message = {
      'type': 'site_access',
      'data': {
        'logs': logs,
      },
    };
    
    return await _sendMessage(message);
  }
  
  /// Send a message through WebSocket
  Future<bool> _sendMessage(Map<String, dynamic> message) async {
    if (!isConnected) {
      debugPrint('⚠️ WebSocket: Not connected, buffering message');
      _bufferMessage(message);
      return false;
    }
    
    try {
      final jsonString = jsonEncode(message);
      _channel!.sink.add(jsonString);
      debugPrint('📤 WebSocket: Sent ${message['type']}');
      return true;
    } catch (e) {
      debugPrint('❌ WebSocket: Failed to send message: $e');
      _bufferMessage(message);
      return false;
    }
  }
  
  /// Buffer message for later sending
  void _bufferMessage(Map<String, dynamic> message) {
    _messageBuffer.add({
      ...message,
      'buffered_at': DateTime.now().toIso8601String(),
    });
    debugPrint('💾 WebSocket: Message buffered (${_messageBuffer.length} total)');
  }
  
  /// Send all buffered messages
  Future<void> _sendBufferedMessages() async {
    if (_messageBuffer.isEmpty) return;
    
    debugPrint('📦 WebSocket: Sending ${_messageBuffer.length} buffered messages');
    
    final messagesToSend = List<Map<String, dynamic>>.from(_messageBuffer);
    _messageBuffer.clear();
    
    for (final message in messagesToSend) {
      message.remove('buffered_at'); // Remove metadata
      final success = await _sendMessage(message);
      if (!success) {
        // If sending fails, it will be re-buffered
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100)); // Small delay between messages
    }
  }
  
  /// Start heartbeat/ping mechanism
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (isConnected) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
          debugPrint('💓 WebSocket: Heartbeat sent');
        } catch (e) {
          debugPrint('❌ WebSocket: Heartbeat failed: $e');
        }
      }
    });
  }
  
  /// Stop heartbeat
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  /// Start restrictions heartbeat
  void _startRestrictionsHeartbeat() {
    _restrictionsHeartbeatTimer?.cancel();
    _restrictionsHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (isRestrictionsConnected) {
        try {
          _restrictionsChannel!.sink.add(jsonEncode({'type': 'ping'}));
          debugPrint('💓 WSS Restrictions: Heartbeat sent');
        } catch (e) {
          debugPrint('❌ WSS Restrictions: Heartbeat failed: $e');
        }
      }
    });
  }
  
  /// Stop restrictions heartbeat
  void _stopRestrictionsHeartbeat() {
    _restrictionsHeartbeatTimer?.cancel();
    _restrictionsHeartbeatTimer = null;
  }
  
  /// Update status and notify listeners
  void _updateStatus(WebSocketStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
      debugPrint('🔄 WebSocket: Status changed to ${newStatus.name}');
    }
  }
  
  /// Update restrictions status and notify listeners
  void _updateRestrictionsStatus(WebSocketStatus newStatus) {
    if (_restrictionsStatus != newStatus) {
      _restrictionsStatus = newStatus;
      notifyListeners();
      debugPrint('🔄 WSS Restrictions: Status changed to ${newStatus.name}');
    }
  }
  
  /// Disconnect WebSocket
  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _stopRestrictionsHeartbeat();
    
    if (_channel != null) {
      await _channel!.sink.close(ws_status.goingAway);
      _channel = null;
    }
    
    if (_restrictionsChannel != null) {
      await _restrictionsChannel!.sink.close(ws_status.goingAway);
      _restrictionsChannel = null;
    }
    
    _updateStatus(WebSocketStatus.disconnected);
    _updateRestrictionsStatus(WebSocketStatus.disconnected);
  }
  
  /// Manually retry connection
  Future<void> retry() async {
    _reconnectAttempts = 0;
    await _establishConnection();
  }
  
  /// Public disconnect method
  Future<void> disconnect() async {
    await _disconnect();
  }
  
  /// Get buffered message count
  int get bufferedMessageCount => _messageBuffer.length;
  
  /// Clear buffered messages
  void clearBuffer() {
    _messageBuffer.clear();
    debugPrint('🗑️ WebSocket: Message buffer cleared');
  }
  
  @override
  void dispose() {
    _disconnect(); // Fire and forget - can't await in dispose
    _messageController.close();
    _restrictionsController.close();
    super.dispose();
  }
}
