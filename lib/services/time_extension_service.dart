import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../models/time_extension_request.dart';
import 'encryption_service.dart';
import '../utils/preferences_manager.dart';

class TimeExtensionService extends ChangeNotifier {
  static const String baseUrl = 'https://seraphguardlabs.com';
  static const String wsUrl = 'wss://seraphguardlabs.com/ws/guardian/time-extension';
  
  WebSocketChannel? _channel;
  WebSocketChannel? _childChannel;
  List<TimeExtensionRequest> _pendingRequests = [];
  List<TimeExtensionRequest> _allRequests = [];
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isAuthenticated = false;
  bool _childWsConnected = false;
  bool _childWsConnecting = false;
  String? _childWsStatusMessage;
  String? _childWsResponseMessage;
  Completer<bool>? _childRequestCompleter;
  DateTime? _lastConnectionAttempt;
  int _reconnectAttempts = 0;
  
  final StreamController<TimeExtensionRequest> _newRequestController = 
      StreamController<TimeExtensionRequest>.broadcast();
  
  List<TimeExtensionRequest> get pendingRequests => _pendingRequests;
  List<TimeExtensionRequest> get allRequests => _allRequests;
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  bool get childWsConnected => _childWsConnected;
  String? get childWsStatusMessage => _childWsStatusMessage;
  String? get lastChildWsResponse => _childWsResponseMessage;
  Stream<TimeExtensionRequest> get newRequestStream => _newRequestController.stream;

  TimeExtensionService() {
    debugPrint('⏰ TimeExt: Service initialized');
    // Auto-connect when service is created
    Future.delayed(const Duration(milliseconds: 500), () {
      debugPrint('⏰ TimeExt: Auto-connecting...');
      connect();
      connectChildSocket();
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

  void _onWebSocketError(error) {
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

  Future<void> connectChildSocket({String? childHash}) async {
    if (_childWsConnecting || _childWsConnected) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final resolvedChildHash = childHash ?? prefs.getString('child_hash');

    if (resolvedChildHash == null || resolvedChildHash.isEmpty) {
      _childWsStatusMessage = 'Child profile not found';
      notifyListeners();
      return;
    }

    _childWsConnecting = true;
    _childWsStatusMessage = 'Connecting...';
    notifyListeners();

    try {
      final uri = Uri.parse('wss://seraphguardlabs.com/ws/child/$resolvedChildHash/time-extension/');
      debugPrint('📡 TimeExt: Connecting child WebSocket at: $uri');
      _childChannel = WebSocketChannel.connect(uri);

      _childChannel!.stream.listen(
        _onChildWebSocketMessage,
        onError: _onChildWebSocketError,
        onDone: _onChildWebSocketDisconnected,
        cancelOnError: false,
      );

      _childWsConnected = true;
      _childWsConnecting = false;
      _childWsStatusMessage = 'Connected';
      notifyListeners();
    } catch (e) {
      _childWsConnected = false;
      _childWsConnecting = false;
      _childWsStatusMessage = 'Connection failed';
      _childWsResponseMessage = e.toString();
      notifyListeners();
      debugPrint('❌ TimeExt: Child WebSocket connection error: $e');
    }
  }

  void _onChildWebSocketMessage(dynamic message) {
    try {
      debugPrint('📨 TimeExt (child): Received message: $message');
      final data = json.decode(message as String);
      final messageType = data['type'];

      if (messageType == 'connection_established') {
        _childWsConnected = true;
        _childWsStatusMessage = data['message'] ?? 'Connection established';
        notifyListeners();
        return;
      }

      if (messageType == 'request_created' || messageType == 'request_received' || messageType == 'success') {
        _childWsResponseMessage = data['message'] ?? messageType;
        notifyListeners();
        if (_childRequestCompleter != null && !_childRequestCompleter!.isCompleted) {
          _childRequestCompleter!.complete(true);
        }
        return;
      }

      if (messageType == 'error') {
        _childWsResponseMessage = data['message'] ?? 'Server error';
        notifyListeners();
        if (_childRequestCompleter != null && !_childRequestCompleter!.isCompleted) {
          _childRequestCompleter!.complete(false);
        }
        return;
      }

      _childWsResponseMessage = data['message'] ?? 'Unknown response';
      notifyListeners();
    } catch (e) {
      _childWsResponseMessage = 'Failed to parse server response';
      notifyListeners();
      debugPrint('❌ TimeExt: Error parsing child response: $e');
    }
  }

  void _onChildWebSocketError(error) {
    _childWsConnected = false;
    _childWsConnecting = false;
    _childWsStatusMessage = 'Connection error';
    _childWsResponseMessage = error.toString();
    notifyListeners();
    if (_childRequestCompleter != null && !_childRequestCompleter!.isCompleted) {
      _childRequestCompleter!.complete(false);
    }
    debugPrint('❌ TimeExt child WebSocket error: $error');
  }

  void _onChildWebSocketDisconnected() {
    _childWsConnected = false;
    _childWsConnecting = false;
    _childWsStatusMessage = 'Disconnected';
    notifyListeners();
    if (_childRequestCompleter != null && !_childRequestCompleter!.isCompleted) {
      _childRequestCompleter!.complete(false);
    }
    debugPrint('🔌 TimeExt: Child WebSocket disconnected');
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
      _childWsResponseMessage = null;
      notifyListeners();

      debugPrint('\n📤 TimeExt: Creating new time extension request');
      debugPrint('📤 TimeExt: Child: $childHash');
      debugPrint('📤 TimeExt: Hours: $requestedHours');
      debugPrint('📤 TimeExt: Reason (plaintext): $reason');
      debugPrint('📤 TimeExt: Package: $packageName');
      debugPrint('📤 TimeExt: App: $appName');

      // Fetch parent's public key and encrypt the message
      String? encryptedMessage = messageEncrypted;
      final prefsManager = await PreferencesManager.init();
      int? guardianId = prefsManager.getGuardianId();
      
      if (encryptedMessage == null) {
        debugPrint('🔐 TimeExt: Fetching parent public key for encryption...');
        final parentData = await _fetchParentPublicKeyAndId(childHash);
        final parentPublicKey = parentData['public_key'];
        guardianId = guardianId ?? parentData['guardian_id'];
        
        if (parentPublicKey != null && parentPublicKey.isNotEmpty) {
          try {
            debugPrint('🔐 TimeExt: Encrypting message with parent public key...');
            final encryptionService = EncryptionService.instance;
            encryptedMessage = encryptionService.encryptWithPublicKey(reason, parentPublicKey);
            debugPrint('✅ TimeExt: Message encrypted successfully');
            debugPrint('🔐 TimeExt: Encrypted message (base64): ${encryptedMessage.substring(0, 50)}...');
          } catch (e) {
            debugPrint('❌ TimeExt: Encryption failed: $e');
            debugPrint('⚠️ TimeExt: Sending base64-encoded plaintext as fallback');
            encryptedMessage = base64.encode(utf8.encode(reason));
          }
        } else {
          debugPrint('⚠️ TimeExt: Parent public key not available');
          debugPrint('⚠️ TimeExt: Sending base64-encoded plaintext as fallback');
          encryptedMessage = base64.encode(utf8.encode(reason));
        }
      }

      // Ensure we always have a message to send (server requires NOT NULL)
      if (encryptedMessage == null || encryptedMessage.isEmpty) {
        debugPrint('⚠️ TimeExt: No encrypted message, using base64-encoded plaintext');
        encryptedMessage = base64.encode(utf8.encode(reason));
      }

      // Refresh guardian_id from preferences after any fetch
      guardianId = guardianId ?? prefsManager.getGuardianId();

      // Use WebSocket for sending time extension request
      debugPrint('📡 TimeExt: Sending via WebSocket...');
      final wsUrl = 'wss://seraphguardlabs.com/ws/child/$childHash/time-extension/';
      debugPrint('📡 TimeExt: Connecting to: $wsUrl');
      
      try {
        if (!_childWsConnected || _childChannel == null) {
          await connectChildSocket(childHash: childHash);
        }

        final channel = _childChannel ?? WebSocketChannel.connect(Uri.parse(wsUrl));
        
        final payload = {
          'type': 'time_extension_request',
          'data': {
            'app_domain': packageName ?? '',
            'requested_hours': requestedHours,
            'message_encrypted': encryptedMessage,
            if (guardianId != null) 'guardian_id': guardianId,
          }
        };
        
        debugPrint('📦 TimeExt: Sending payload: ${json.encode(payload)}');
        
        // For persistent child socket, rely on the shared listener
        bool success = true;
        Completer<bool>? completer;
        StreamSubscription? subscription;

        if (channel == _childChannel) {
          _childRequestCompleter = Completer<bool>();
          completer = _childRequestCompleter;
        } else {
          success = false;
          completer = Completer<bool>();
          subscription = channel.stream.listen(
            (message) {
              try {
                debugPrint('📨 TimeExt: Received response: $message');
                final data = json.decode(message as String);
                final messageType = data['type'];

                debugPrint('📨 TimeExt: Message type: $messageType');

                if (messageType == 'connection_established') {
                  _childWsConnected = true;
                  _childWsStatusMessage = data['message'] ?? 'Connection established';
                  notifyListeners();
                  return;
                }

                if (messageType == 'pending_requests') {
                  debugPrint('ℹ️ TimeExt: Ignoring pending_requests message (not relevant for child)');
                  return;
                }

                if (messageType == 'success' || messageType == 'request_received' || messageType == 'request_created') {
                  _childWsResponseMessage = data['message'] ?? messageType;
                  notifyListeners();
                  debugPrint('✅ TimeExt: Request sent successfully');
                  success = true;
                  if (!completer!.isCompleted) {
                    completer.complete(true);
                  }
                } else if (messageType == 'error') {
                  _childWsResponseMessage = data['message'] ?? 'Server error';
                  notifyListeners();
                  debugPrint('❌ TimeExt: Error from server: ${data['message']}');
                  if (!completer!.isCompleted) {
                    completer.complete(false);
                  }
                } else {
                  _childWsResponseMessage = data['message'] ?? 'Unknown response';
                  notifyListeners();
                  debugPrint('ℹ️ TimeExt: Unknown message type: $messageType');
                }
              } catch (e) {
                _childWsResponseMessage = 'Failed to parse server response';
                notifyListeners();
                debugPrint('❌ TimeExt: Error parsing response: $e');
                if (!completer!.isCompleted) {
                  completer.complete(false);
                }
              }
            },
            onError: (error) {
              _childWsConnected = false;
              _childWsStatusMessage = 'Connection error';
              _childWsResponseMessage = error.toString();
              notifyListeners();
              debugPrint('❌ TimeExt: WebSocket error: $error');
              if (!completer!.isCompleted) {
                completer.complete(false);
              }
            },
            onDone: () {
              _childWsConnected = false;
              _childWsStatusMessage = 'Disconnected';
              notifyListeners();
              debugPrint('🔌 TimeExt: WebSocket closed');
              if (!completer!.isCompleted) {
                completer.complete(success);
              }
            },
          );
        }
        
        // Send the payload
        channel.sink.add(json.encode(payload));
        debugPrint('✅ TimeExt: Payload sent, waiting for response...');
        
        // Wait a bit for response, but don't fail if we don't get one
        if (completer != null) {
          final result = await completer.future.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              debugPrint('⏱️ TimeExt: No response received, but assuming success since message was sent');
              _childWsResponseMessage = 'No response from server yet';
              notifyListeners();
              return true; // Assume success if message was sent
            },
          );

          // Clean up
          await subscription?.cancel();
          if (channel != _childChannel) {
            await channel.sink.close();
          }
          if (_childRequestCompleter == completer) {
            _childRequestCompleter = null;
          }
          debugPrint('✅ TimeExt: Request completed with result: $result');
          return result;
        }

        return true;
        
      } catch (e) {
        debugPrint('❌ TimeExt: WebSocket connection error: $e');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ TimeExt: Error creating request: $e');
      debugPrint('❌ TimeExt: Stack trace: $stackTrace');
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
        
        if (guardianId != null) {
          final prefsManager = await PreferencesManager.init();
          await prefsManager.setGuardianId(guardianId);
        }

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
    try {
      _childChannel?.sink.close(ws_status.normalClosure);
    } catch (e) {
      debugPrint('⚠️ TimeExt: Error closing child WebSocket: $e');
    }
    _newRequestController.close();
    super.dispose();
  }
}
