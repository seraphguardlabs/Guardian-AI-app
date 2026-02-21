import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../models/time_extension_request.dart';
import 'encryption_service.dart';

class TimeExtensionService extends ChangeNotifier {
  static const String baseUrl = 'https://seraphguardlabs.com';
  static const String wsUrl = 'wss://seraphguardlabs.com/ws/guardian/time-extension';
  
  WebSocketChannel? _channel;
  List<TimeExtensionRequest> _pendingRequests = [];
  List<TimeExtensionRequest> _allRequests = [];
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isAuthenticated = false;
  DateTime? _lastConnectionAttempt;
  int _reconnectAttempts = 0;
  
  final StreamController<TimeExtensionRequest> _newRequestController = 
      StreamController<TimeExtensionRequest>.broadcast();
  
  List<TimeExtensionRequest> get pendingRequests => _pendingRequests;
  List<TimeExtensionRequest> get allRequests => _allRequests;
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  Stream<TimeExtensionRequest> get newRequestStream => _newRequestController.stream;

  TimeExtensionService() {
    debugPrint('⏰ TimeExt: Service initialized');
    // Auto-connect when service is created
    Future.delayed(const Duration(milliseconds: 500), () {
      debugPrint('⏰ TimeExt: Auto-connecting...');
      connect();
    });
  }

  // Get authentication headers
  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('parent_email') ?? '';
    final password = prefs.getString('parent_password') ?? '';
    
    return {
      'Content-Type': 'application/json',
      'X-Email': email,
      'X-Password': password,
    };
  }

  // Connect to WebSocket for real-time time extension requests
  Future<void> connect() async {
    debugPrint('\n⏰ TimeExt: connect() called');
    debugPrint('⏰ TimeExt: Current state - isConnecting: $_isConnecting, isConnected: $_isConnected, isAuth: $_isAuthenticated');
    
    if (_isConnecting) {
      debugPrint('⚠️ TimeExt: Connection already in progress, skipping');
      return;
    }

    if (_isConnected && _isAuthenticated) {
      debugPrint('⏰ TimeExt: Already connected and authenticated');
      return;
    }

    // Throttle connection attempts (min 2 seconds between attempts)
    if (_lastConnectionAttempt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(_lastConnectionAttempt!);
      if (timeSinceLastAttempt.inSeconds < 2) {
        debugPrint('⚠️ TimeExt: Connection attempt too soon (${timeSinceLastAttempt.inSeconds}s ago), waiting...');
        return;
      }
    }

    _isConnecting = true;
    _lastConnectionAttempt = DateTime.now();
    await disconnect();
    
    try {
      final uri = Uri.parse('$wsUrl/');
      debugPrint('⏰ TimeExt: Connecting to WebSocket at: $uri');
      
      _channel = WebSocketChannel.connect(uri);
      debugPrint('⏰ TimeExt: WebSocket channel created');
      
      // Listen for messages
      _channel!.stream.listen(
        _onWebSocketMessage,
        onError: _onWebSocketError,
        onDone: _onWebSocketDisconnected,
        cancelOnError: false,
      );
      
      debugPrint('⏰ TimeExt: Stream listeners attached');
      
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      notifyListeners();
      debugPrint('✅ TimeExt: WebSocket connected successfully, waiting for server messages...');
      debugPrint('⏰ TimeExt: Connection state - isConnected: $_isConnected, isAuth: $_isAuthenticated');
      
    } catch (e, stackTrace) {
      _reconnectAttempts++;
      debugPrint('❌ TimeExt: Connection failed (attempt $_reconnectAttempts): $e');
      debugPrint('❌ TimeExt: Stack trace: $stackTrace');
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();
      
      if (_reconnectAttempts >= 3) {
        debugPrint('🛑 TimeExt: Max reconnection attempts reached');
      }
    }
  }

  // Authenticate after connection
  Future<void> _authenticate() async {
    debugPrint('\n🔐 TimeExt: _authenticate() called');
    debugPrint('🔐 TimeExt: isConnected: $_isConnected, channel: ${_channel != null}');
    
    if (!_isConnected || _channel == null) {
      debugPrint('❌ TimeExt: Cannot authenticate - not connected');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('parent_email') ?? '';
    final password = prefs.getString('parent_password') ?? '';
    
    debugPrint('🔐 TimeExt: Email: $email');
    debugPrint('🔐 TimeExt: Password: ${password.isNotEmpty ? "[PRESENT]" : "[MISSING]"}');
    
    if (email.isEmpty || password.isEmpty) {
      debugPrint('❌ TimeExt: Missing credentials - email: ${email.isEmpty ? "EMPTY" : "OK"}, password: ${password.isEmpty ? "EMPTY" : "OK"}');
      return;
    }

    debugPrint('🔐 TimeExt: Sending auth message...');
    final authPayload = json.encode({
      'type': 'auth',
      'email': email,
      'password': password,
    });
    debugPrint('🔐 TimeExt: Auth payload: ${authPayload.replaceAll(password, "[HIDDEN]") }');
    _channel!.sink.add(authPayload);
    debugPrint('✅ TimeExt: Auth message sent, waiting for response...');
  }

  // Handle incoming WebSocket messages
  void _onWebSocketMessage(dynamic message) {
    try {
      debugPrint('\n📨 TimeExt: Received message: $message');
      final data = json.decode(message as String);
      debugPrint('⏰ TimeExt: Message type: ${data['type']}');
      
      switch (data['type']) {
        case 'auth_required':
          debugPrint('🔐 TimeExt: Auth required received, authenticating...');
          _authenticate();
          break;
          
        case 'auth_success':
          _isAuthenticated = true;
          notifyListeners();
          debugPrint('✅ TimeExt: Authenticated successfully!');
          debugPrint('✅ TimeExt: Guardian ID: ${data['guardian_id']}');
          debugPrint('✅ TimeExt: Email: ${data['email']}');
          debugPrint('⏰ TimeExt: Final state - isConnected: $_isConnected, isAuth: $_isAuthenticated');
          break;
          
        case 'pending_requests':
          _handlePendingRequests(data);
          break;
          
        case 'time_extension_request':
          _handleNewRequest(data['data']);
          break;
          
        case 'response_sent':
          debugPrint('✅ TimeExt: Response sent for request ${data['request_id']}');
          // Remove from pending list
          _pendingRequests.removeWhere((r) => r.requestId == data['request_id']);
          notifyListeners();
          break;
          
        case 'error':
          debugPrint('❌ TimeExt error: ${data['message']}');
          break;
      }
    } catch (e) {
      debugPrint('❌ TimeExt: Error parsing message: $e');
    }
  }

  void _handlePendingRequests(Map<String, dynamic> data) {
    try {
      final List<dynamic> requestsList = data['requests'] ?? [];
      _pendingRequests = requestsList.map((req) => TimeExtensionRequest.fromJson(req)).toList();
      notifyListeners();
      debugPrint('📋 TimeExt: Loaded ${_pendingRequests.length} pending requests');
    } catch (e) {
      debugPrint('❌ TimeExt: Error handling pending requests: $e');
    }
  }

  void _handleNewRequest(Map<String, dynamic> data) {
    try {
      final request = TimeExtensionRequest.fromJson(data);
      _pendingRequests.add(request);
      _allRequests.add(request);
      _newRequestController.add(request);
      notifyListeners();
      debugPrint('🔔 TimeExt: New request from ${request.childName} for ${request.appDomain}');
    } catch (e) {
      debugPrint('❌ TimeExt: Error handling new request: $e');
    }
  }

  void _onWebSocketError(Object error) {
    debugPrint('❌ TimeExt WebSocket error: $error');
    _isConnected = false;
    _isConnecting = false;
    _isAuthenticated = false;
    notifyListeners();
  }


  void _onWebSocketDisconnected() {
    if (_isConnected) {
      debugPrint('🔌 TimeExt: WebSocket disconnected unexpectedly');
    } else {
      debugPrint('⏰ TimeExt: WebSocket disconnected normally');
    }
    _isConnected = false;
    _isConnecting = false;
    _isAuthenticated = false;
    notifyListeners();
  }

  // Disconnect WebSocket
  Future<void> disconnect() async {
    if (_channel != null) {
      try {
        await _channel!.sink.close(ws_status.normalClosure);
      } catch (e) {
        debugPrint('⚠️ TimeExt: Error closing WebSocket: $e');
      }
      _channel = null;
      _isConnected = false;
      _isConnecting = false;
      _isAuthenticated = false;
      notifyListeners();
      debugPrint('🔌 TimeExt: Disconnected');
    }
  }

  // Fetch pending requests via REST API (fallback)
  Future<void> fetchPendingRequests() async {
    try {
      debugPrint('📡 TimeExt: Fetching pending requests via API');
      final response = await http.get(
        Uri.parse('$baseUrl/api/mobile/time-extension-requests/?status=pending'),
        headers: await _getAuthHeaders(),
      );

      debugPrint('📥 TimeExt: Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> requestsList = data['requests'] ?? [];
        _pendingRequests = requestsList.map((req) => TimeExtensionRequest.fromJson(req)).toList();
        notifyListeners();
        debugPrint('✅ TimeExt: Loaded ${_pendingRequests.length} pending requests');
      }
    } catch (e) {
      debugPrint('❌ TimeExt: Error fetching requests: $e');
    }
  }

  // Respond to a time extension request via WebSocket
  Future<bool> respondToRequest({
    required int requestId,
    required String action, // 'approve', 'deny', 'message'
    double? grantedHours,
    String? responseEncrypted,
  }) async {
    try {
      debugPrint('\n📤 TimeExt: Responding to request $requestId');
      debugPrint('📤 TimeExt: Action: $action');
      if (grantedHours != null) debugPrint('📤 TimeExt: Granted hours: $grantedHours');

      // Send via WebSocket if connected
      if (_isConnected && _isAuthenticated && _channel != null) {
        final payload = {
          'type': 'time_extension_response',
          'data': {
            'request_id': requestId,
            'action': action,
            if (grantedHours != null) 'granted_hours': grantedHours,
            if (responseEncrypted != null) 'response_encrypted': responseEncrypted,
          }
        };
        
        debugPrint('📡 TimeExt: Sending via WebSocket: $payload');
        _channel!.sink.add(json.encode(payload));
        debugPrint('✅ TimeExt: Response sent via WebSocket');
        return true;
      } else {
        // Fallback to REST API
        debugPrint('📡 TimeExt: WebSocket not available, using HTTP fallback');
        final url = '$baseUrl/api/mobile/time-extension-requests/$requestId/respond/';
        
        final body = {
          'action': action,
          if (grantedHours != null) 'granted_hours': grantedHours,
          if (responseEncrypted != null) 'response_encrypted': responseEncrypted,
        };
        
        debugPrint('📡 TimeExt: Sending to: $url');
        debugPrint('📦 TimeExt: Body: $body');
        
        final response = await http.post(
          Uri.parse(url),
          headers: await _getAuthHeaders(),
          body: json.encode(body),
        );

        debugPrint('📥 TimeExt: Response status: ${response.statusCode}');
        debugPrint('📥 TimeExt: Response body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          // Remove from pending list
          _pendingRequests.removeWhere((r) => r.requestId == requestId);
          notifyListeners();
          debugPrint('✅ TimeExt: Response sent via HTTP successfully');
          return true;
        }
        
        debugPrint('❌ TimeExt: HTTP response failed');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ TimeExt: Error responding to request: $e');
      debugPrint('❌ TimeExt: Stack trace: $stackTrace');
      return false;
    }
  }

  // Request pending updates manually
  void requestPendingUpdates() {
    if (_isConnected && _isAuthenticated && _channel != null) {
      debugPrint('📡 TimeExt: Requesting pending requests update');
      _channel!.sink.add(json.encode({'type': 'get_pending_requests'}));
    }
  }


  // Create a new time extension request (from child side)
  Future<bool> createRequest({
    required String childHash,
    required double requestedHours,
    required String reason,
    String? packageName,
    String? appName,
    String? messageEncrypted,
  }) async {
    try {
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('🚀 TIME EXTENSION REQUEST: Start');
      debugPrint('   Child Hash: $childHash');
      debugPrint('   Hours: $requestedHours');
      debugPrint('   Reason: $reason');
      debugPrint('   App: $appName ($packageName)');

      // Fetch parent's public key and encrypt the message
      String? encryptedMessage = messageEncrypted;
      int? guardianId;
      
      if (encryptedMessage == null) {
        debugPrint('🔐 ENCRYPTION: Fetching parent keys...');
        final parentData = await _fetchParentPublicKeyAndId(childHash);
        final parentPublicKey = parentData['public_key'];
        guardianId = parentData['guardian_id'];
        
        if (parentPublicKey != null && parentPublicKey.isNotEmpty) {
          try {
            debugPrint('🔐 ENCRYPTION: Encrypting with parent key...');
            final encryptionService = EncryptionService.instance;
            encryptedMessage = encryptionService.encryptWithPublicKey(reason, parentPublicKey);
            debugPrint('✅ ENCRYPTION: Message encrypted successfully');
          } catch (e) {
            debugPrint('❌ ENCRYPTION: Failed: $e');
            debugPrint('⚠️ FALLBACK: Using base64 encoding');
            encryptedMessage = base64.encode(utf8.encode(reason));
          }
        } else {
          debugPrint('⚠️ KEYS: Parent public key not found');
          debugPrint('⚠️ FALLBACK: Using base64 encoding');
          encryptedMessage = base64.encode(utf8.encode(reason));
        }
      }

      final payload = {
        'type': 'time_extension_request',
        'data': { 
          'child_hash': childHash, // Ensure child hash is sent 
          'app_domain': packageName ?? '',
          'app_name': appName ?? '',
          'requested_hours': requestedHours,
          'message_encrypted': encryptedMessage,
          if (guardianId != null) 'guardian_id': guardianId,
        }
      };

      debugPrint('📦 PAYLOAD PREPARED:');
      debugPrint(const JsonEncoder.withIndent('  ').convert(payload));

      // 1. Try WebSocket
      debugPrint('📡 API (WEBSOCKET): Attempting connection...');
      final wsUrl = 'wss://seraphguardlabs.com/ws/child/$childHash/time-extension/';
      debugPrint('   URL: $wsUrl');
      
      bool wsSuccess = false;
      try {
        final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        
        final completer = Completer<bool>();
        final connectionCompleter = Completer<bool>();
        bool payloadSent = false;
        final subscription = channel.stream.listen(
          (message) {
            debugPrint('📨 WEBSOCKET MESSAGE: $message');
            try {
              final data = json.decode(message as String);
              if (data['type'] == 'connection_established' && !connectionCompleter.isCompleted) {
                connectionCompleter.complete(true);
                if (!payloadSent) {
                  channel.sink.add(json.encode(payload));
                  payloadSent = true;
                  debugPrint('📤 WEBSOCKET: Payload sent after connection established');
                }
              } else if (data['type'] == 'success' || data['type'] == 'request_created') {
                if (!completer.isCompleted) completer.complete(true);
              } else if (data['type'] == 'error') {
                debugPrint('❌ WEBSOCKET ERROR: ${data['message']}');
                if (!completer.isCompleted) completer.complete(false);
              }
            } catch (e) {
              if (!completer.isCompleted) completer.complete(false);
            }
          },
          onError: (e) {
            debugPrint('❌ WEBSOCKET CONNECTION ERROR: $e');
            if (!connectionCompleter.isCompleted) connectionCompleter.complete(false);
            if (!completer.isCompleted) completer.complete(false);
          },
          onDone: () {
            if (!connectionCompleter.isCompleted) connectionCompleter.complete(false);
            if (!completer.isCompleted) completer.complete(false);
          }
        );

        // Wait for connection acknowledgement before sending
        final connected = await connectionCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⏱️ WEBSOCKET: Timeout waiting for connection acknowledgement');
            return false;
          },
        );

        if (!connected) {
          await subscription.cancel();
          await channel.sink.close();
          wsSuccess = false;
        } else {
          wsSuccess = await completer.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⏱️ WEBSOCKET: Timeout waiting for confirmation');
              return false;
            },
          );

          await subscription.cancel();
          await channel.sink.close();
        }
      } catch (e) {
        debugPrint('❌ WEBSOCKET FAILED: $e');
        wsSuccess = false;
      }

      if (wsSuccess) {
        debugPrint('✅ SUCCESS: Request sent via WebSocket');
        debugPrint('═══════════════════════════════════════════════════════');
        return true;
      }

      // 2. HTTP Fallback
      debugPrint('⚠️ WEBSOCKET FAILED: Trying HTTP fallback...');
      debugPrint('📡 API (HTTP): Sending POST request');
      final httpUrl = Uri.parse('$baseUrl/api/mobile/time-extension-requests/');
      debugPrint('   URL: $httpUrl');
      
      // HTTP payload structure might differ slightly (usually just the 'data' part)
      final httpPayload = payload['data'];
      
      final response = await http.post(
        httpUrl,
        headers: {
          'Content-Type': 'application/json',
          'X-Child-Hash': childHash,
        },
        body: jsonEncode(httpPayload),
      );

      debugPrint('📥 HTTP RESPONSE: ${response.statusCode}');
      debugPrint('📥 BODY: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('✅ SUCCESS: Request sent via HTTP');
        debugPrint('═══════════════════════════════════════════════════════');
        return true;
      } else {
        debugPrint('❌ HTTP FAILED: ${response.body}');
        debugPrint('═══════════════════════════════════════════════════════');
        return false;
      }

    } catch (e, stackTrace) {
      debugPrint('❌ CRITICAL ERROR: $e');
      debugPrint('❌ STACK TRACE: $stackTrace');
      debugPrint('═══════════════════════════════════════════════════════');
      return false;
    }
  }


  // Fetch parent's public key and guardian ID for encryption
  Future<Map<String, dynamic>> _fetchParentPublicKeyAndId(String childHash) async {
    try {
      debugPrint('\n🔑 TimeExt: Fetching parent public key and guardian ID...');
      final url = '$baseUrl/api/mobile/child/$childHash/guardian-public-key/';
      
      final prefs = await SharedPreferences.getInstance();
      final childHashStored = prefs.getString('child_hash') ?? '';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Child-Hash': childHashStored,
        },
      );

      debugPrint('📥 TimeExt: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final publicKey = data['public_key'] as String?;
        final guardianId = data['guardian_id'] as int?;
        
        if (publicKey != null && publicKey.isNotEmpty) {
          debugPrint('✅ TimeExt: Parent public key fetched successfully');
          debugPrint('✅ TimeExt: Guardian ID: $guardianId');
          return {
            'public_key': publicKey,
            'guardian_id': guardianId,
          };
        }
      }
      
      debugPrint('❌ TimeExt: Failed to fetch parent public key');
      return {};
    } catch (e) {
      debugPrint('❌ TimeExt: Error fetching parent public key: $e');
      return {};
    }
  }

  @override
  void dispose() {
    disconnect();
    _newRequestController.close();
    super.dispose();
  }
}
