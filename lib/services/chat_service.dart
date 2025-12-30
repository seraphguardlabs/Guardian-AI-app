import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../models/chat_message.dart';

class ChatService extends ChangeNotifier {
  static const String baseUrl = 'https://seraphguardlabs.com';
  static const String wsUrl = 'wss://seraphguardlabs.com/ws/guardian/chat';
  
  WebSocketChannel? _channel;
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isConnected = false;
  String? _childPublicKey;
  String? _guardianPrivateKey;
  String? _currentChildHash;
  bool _isConnecting = false;
  DateTime? _lastConnectionAttempt;
  int _reconnectAttempts = 0;
  
  final StreamController<ChatMessage> _messageController = 
      StreamController<ChatMessage>.broadcast();
  
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  Stream<ChatMessage> get messageStream => _messageController.stream;

  // Get authentication headers
  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('guardian_email') ?? '';
    final password = prefs.getString('guardian_password') ?? '';
    
    return {
      'Content-Type': 'application/json',
      'X-Email': email,
      'X-Password': password,
    };
  }

  // Connect to WebSocket for real-time chat
  Future<void> connect(String childHash) async {
    // Prevent connection if already connecting
    if (_isConnecting) {
      debugPrint('⚠️ Chat: Connection already in progress, skipping');
      return;
    }

    if (_isConnected && _currentChildHash == childHash) {
      debugPrint('💬 Chat: Already connected to $childHash');
      return;
    }

    // Throttle connection attempts (min 2 seconds between attempts)
    if (_lastConnectionAttempt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(_lastConnectionAttempt!);
      if (timeSinceLastAttempt.inSeconds < 2) {
        debugPrint('⚠️ Chat: Connection attempt too soon, waiting...');
        return;
      }
    }

    _isConnecting = true;
    _lastConnectionAttempt = DateTime.now();
    _currentChildHash = childHash;
    await disconnect();
    
    try {
      // Fetch child's public key first
      await fetchChildPublicKey(childHash);
      
      // Connect to WebSocket
      final uri = Uri.parse('$wsUrl/');
      debugPrint('💬 Chat: Connecting to $uri with child: $childHash');
      
      _channel = WebSocketChannel.connect(uri);
      
      // Authenticate
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('guardian_email') ?? '';
      final password = prefs.getString('guardian_password') ?? '';
      
      _channel!.sink.add(json.encode({
        'type': 'auth',
        'email': email,
        'password': password,
      }));
      
      // Listen for messages
      _channel!.stream.listen(
        _onWebSocketMessage,
        onError: _onWebSocketError,
        onDone: _onWebSocketDisconnected,
        cancelOnError: false,
      );
      
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      notifyListeners();
      debugPrint('✅ Chat: Connected successfully to $childHash');
      
    } catch (e) {
      _reconnectAttempts++;
      debugPrint('❌ Chat: Connection failed (attempt $_reconnectAttempts): $e');
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();
      
      // Stop trying after 3 consecutive failures
      if (_reconnectAttempts >= 3) {
        debugPrint('🛑 Chat: Max reconnection attempts reached. Stopping auto-reconnect.');
      }
    }
  }

  // Handle incoming WebSocket messages
  void _onWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message as String);
      debugPrint('💬 Chat received: ${data['type']}');
      
      switch (data['type']) {
        case 'auth_success':
          debugPrint('✅ Chat: Authenticated successfully');
          // Request chat history
          _channel?.sink.add(json.encode({'type': 'get_history'}));
          break;
          
        case 'chat_history':
          _handleChatHistory(data);
          break;
          
        case 'new_message':
          _handleNewMessage(data['data']);
          break;
          
        case 'message_sent':
          debugPrint('✅ Chat: Message sent confirmation');
          break;
          
        case 'error':
          debugPrint('❌ Chat error: ${data['message']}');
          break;
      }
    } catch (e) {
      debugPrint('❌ Chat: Error parsing message: $e');
    }
  }

  void _handleChatHistory(Map<String, dynamic> data) {
    try {
      final List<dynamic> messagesList = data['messages'] ?? [];
      _messages = messagesList.map((msg) {
        final chatMsg = ChatMessage.fromJson(msg);
        // Try to decrypt if it's from the child
        if (!chatMsg.isFromParent && chatMsg.messageEncrypted.isNotEmpty) {
          final decrypted = decryptMessage(chatMsg.messageEncrypted);
          if (decrypted != null) {
            return ChatMessage(
              messageId: chatMsg.messageId,
              senderHash: chatMsg.senderHash,
              receiverHash: chatMsg.receiverHash,
              messageEncrypted: chatMsg.messageEncrypted,
              messageDecrypted: decrypted,
              timestamp: chatMsg.timestamp,
              isFromParent: chatMsg.isFromParent,
              senderName: chatMsg.senderName,
            );
          }
        }
        return chatMsg;
      }).toList();
      
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      notifyListeners();
      debugPrint('💬 Chat: Loaded ${_messages.length} messages');
    } catch (e) {
      debugPrint('❌ Chat: Error handling history: $e');
    }
  }

  void _handleNewMessage(Map<String, dynamic> data) {
    try {
      final chatMsg = ChatMessage.fromJson(data);
      
      // Decrypt if it's from the child
      ChatMessage finalMsg = chatMsg;
      if (!chatMsg.isFromParent && chatMsg.messageEncrypted.isNotEmpty) {
        final decrypted = decryptMessage(chatMsg.messageEncrypted);
        if (decrypted != null) {
          finalMsg = ChatMessage(
            messageId: chatMsg.messageId,
            senderHash: chatMsg.senderHash,
            receiverHash: chatMsg.receiverHash,
            messageEncrypted: chatMsg.messageEncrypted,
            messageDecrypted: decrypted,
            timestamp: chatMsg.timestamp,
            isFromParent: chatMsg.isFromParent,
            senderName: chatMsg.senderName,
          );
        }
      }
      
      _messages.add(finalMsg);
      _messageController.add(finalMsg);
      notifyListeners();
      debugPrint('💬 Chat: New message received');
    } catch (e) {
      debugPrint('❌ Chat: Error handling new message: $e');
    }
  }

  void _onWebSocketError(error) {
    debugPrint('❌ Chat WebSocket error: $error');
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
  }

  void _onWebSocketDisconnected() {
    if (_isConnected) {
      debugPrint('🔌 Chat: WebSocket disconnected unexpectedly');
    } else {
      debugPrint('💬 Chat: WebSocket disconnected normally');
    }
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
  }

  // Disconnect WebSocket
  Future<void> disconnect() async {
    if (_channel != null) {
      try {
        await _channel!.sink.close(ws_status.normalClosure);
      } catch (e) {
        debugPrint('⚠️ Chat: Error closing WebSocket: $e');
      }
      _channel = null;
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();
      debugPrint('🔌 Chat: Disconnected');
    }
  }

  // Fetch child's public key for encryption
  Future<bool> fetchChildPublicKey(String childHash) async {
    try {
      final url = '$baseUrl/api/mobile/child/$childHash/public-key/';
      debugPrint('📡 Chat: Fetching public key from: $url');
      
      final headers = await _getAuthHeaders();
      debugPrint('📋 Chat: Headers: ${headers.keys.join(", ")}');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      debugPrint('📥 Chat: Public key response status: ${response.statusCode}');
      debugPrint('📥 Chat: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _childPublicKey = data['public_key'];
        debugPrint('✅ Chat: Child public key loaded successfully');
        debugPrint('🔑 Child Public Key: $_childPublicKey');
        notifyListeners();
        return true;
      } else if (response.statusCode == 404) {
        debugPrint('⚠️ Chat: No public key found for child $childHash (404)');
        return false;
      } else {
        debugPrint('❌ Chat: Failed to fetch public key - Status ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Chat: Error fetching child public key: $e');
      return false;
    }
  }

  // Encrypt message using child's public key
  String encryptMessage(String plainText) {
    debugPrint('🔐 Chat: Encrypting message...');
    if (_childPublicKey == null) {
      debugPrint('❌ Chat: Cannot encrypt - No public key loaded');
      throw Exception('Child public key not loaded');
    }

    try {
      final publicKey = encrypt.RSAKeyParser().parse(_childPublicKey!) as RSAPublicKey;
      final encrypter = encrypt.Encrypter(encrypt.RSA(publicKey: publicKey));
      final encrypted = encrypter.encrypt(plainText);
      debugPrint('✅ Chat: Message encrypted successfully');
      return encrypted.base64;
    } catch (e) {
      debugPrint('❌ Chat: Encryption error: $e');
      rethrow;
    }
  }

  // Decrypt message using guardian's private key (when implemented)
  String? decryptMessage(String encryptedBase64) {
    if (_guardianPrivateKey == null) {
      return null; // Cannot decrypt without private key
    }

    try {
      final privateKey = encrypt.RSAKeyParser().parse(_guardianPrivateKey!) as RSAPrivateKey;
      final encrypter = encrypt.Encrypter(encrypt.RSA(privateKey: privateKey));
      final encrypted = encrypt.Encrypted.fromBase64(encryptedBase64);
      return encrypter.decrypt(encrypted);
    } catch (e) {
      debugPrint('Decryption error: $e');
      return null;
    }
  }

  // Fetch chat history with a child (fallback REST API)
  Future<void> fetchChatHistory(String childHash) async {
    // If WebSocket is connected, request history through it
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode({'type': 'get_history'}));
      return;
    }
    
    // Otherwise use REST API as fallback
    _isLoading = true;
    notifyListeners();

    try {
      if (_childPublicKey == null) {
        await fetchChildPublicKey(childHash);
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/mobile/chat/$childHash/'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> messagesList = data['messages'] ?? [];
        
        _messages = messagesList.map((msg) {
          final chatMsg = ChatMessage.fromJson(msg);
          if (chatMsg.messageEncrypted.isNotEmpty && !chatMsg.isFromParent) {
            final decrypted = decryptMessage(chatMsg.messageEncrypted);
            if (decrypted != null) {
              return ChatMessage(
                messageId: chatMsg.messageId,
                senderHash: chatMsg.senderHash,
                receiverHash: chatMsg.receiverHash,
                messageEncrypted: chatMsg.messageEncrypted,
                messageDecrypted: decrypted,
                timestamp: chatMsg.timestamp,
                isFromParent: chatMsg.isFromParent,
                senderName: chatMsg.senderName,
              );
            }
          }
          return chatMsg;
        }).toList();
        
        notifyListeners();
      } else if (response.statusCode == 404) {
        _messages = [];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching chat history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Send encrypted message to child via WebSocket
  Future<bool> sendMessage(String childHash, String message) async {
    debugPrint('\n📤 Chat: Starting to send message...');
    debugPrint('📤 Chat: Child hash: $childHash');
    debugPrint('📤 Chat: Message: $message');
    debugPrint('📤 Chat: Is connected: $_isConnected');
    debugPrint('📤 Chat: Has public key: ${_childPublicKey != null}');
    
    try {
      // Ensure we have the child's public key
      if (_childPublicKey == null) {
        debugPrint('💬 Chat: Fetching child public key...');
        final keyFetched = await fetchChildPublicKey(childHash);
        debugPrint('💬 Chat: Key fetched result: $keyFetched');
        if (!keyFetched || _childPublicKey == null) {
          debugPrint('⚠️ Chat: Cannot send message - No public key found for child');
          throw Exception('No public key found for child. Please ensure the child device is registered.');
        }
      }

      // Encrypt the message
      debugPrint('🔐 Chat: About to encrypt message');
      final encryptedMessage = encryptMessage(message);
      debugPrint('🔐 Chat: Encrypted message: ${encryptedMessage.substring(0, 50)}...');

      // Send via WebSocket if connected
      if (_isConnected && _channel != null) {
        debugPrint('📡 Chat: Sending via WebSocket...');
        final payload = json.encode({
          'type': 'send_message',
          'data': {
            'message_encrypted': encryptedMessage,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }
        });
        debugPrint('📡 Chat: WebSocket payload: $payload');
        
        _channel!.sink.add(payload);
        
        // Add to local messages immediately
        final newMessage = ChatMessage(
          messageId: DateTime.now().millisecondsSinceEpoch.toString(),
          senderHash: 'guardian',
          receiverHash: childHash,
          messageEncrypted: encryptedMessage,
          messageDecrypted: message,
          timestamp: DateTime.now(),
          isFromParent: true,
          senderName: 'You',
        );
        
        debugPrint('✅ Chat: Adding message to local list');
        _messages.add(newMessage);
        _messageController.add(newMessage);
        notifyListeners();
        debugPrint('✅ Chat: Message sent via WebSocket successfully!');
        return true;
      } else {
        debugPrint('📡 Chat: WebSocket not connected, using HTTP fallback...');
        // Fallback to REST API
        final url = '$baseUrl/api/mobile/chat/$childHash/send/';
        debugPrint('📡 Chat: Sending to: $url');
        
        final response = await http.post(
          Uri.parse(url),
          headers: await _getAuthHeaders(),
          body: json.encode({
            'message_encrypted': encryptedMessage,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }),
        );

        debugPrint('📥 Chat: HTTP response status: ${response.statusCode}');
        debugPrint('📥 Chat: HTTP response body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          final newMessage = ChatMessage(
            messageId: DateTime.now().millisecondsSinceEpoch.toString(),
            senderHash: 'guardian',
            receiverHash: childHash,
            messageEncrypted: encryptedMessage,
            messageDecrypted: message,
            timestamp: DateTime.now(),
            isFromParent: true,
            senderName: 'You',
          );
          
          debugPrint('✅ Chat: Adding message to local list');
          _messages.add(newMessage);
          notifyListeners();
          debugPrint('✅ Chat: Message sent via HTTP successfully!');
          return true;
        }
        
        debugPrint('❌ Chat: HTTP send failed with status ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Chat: Error sending message: $e');
      debugPrint('❌ Chat: Stack trace: $stackTrace');
      return false;
    }
  }

  // Clear chat
  void clearChat() {
    _messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    super.dispose();
  }
}
