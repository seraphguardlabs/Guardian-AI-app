import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import 'encryption_service.dart';

enum ChatRole { guardian, child }

class ChatService extends ChangeNotifier {
  static const String baseUrl = 'https://seraphguardlabs.com';

  final StreamController<ChatMessage> _messageController =
      StreamController<ChatMessage>.broadcast();

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isConnected = false;

  ChatRole? _activeRole;
  String? _activeChildHash;
  int? _activeGuardianId;

  Timer? _pollTimer;
  bool _isPolling = false;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  Stream<ChatMessage> get messageStream => _messageController.stream;
  ChatRole? get activeRole => _activeRole;
  String? get activeChildHash => _activeChildHash;
  int? get activeGuardianId => _activeGuardianId;

  Future<Map<String, String>?> _getGuardianHeaders({bool jsonBody = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final email =
        (prefs.getString('parent_email') ?? prefs.getString('guardian_email') ?? '')
            .trim();
    final password =
        (prefs.getString('parent_password') ?? prefs.getString('guardian_password') ?? '')
            .trim();

    if (email.isEmpty || password.isEmpty) {
      return null;
    }

    return {
      if (jsonBody) 'Content-Type': 'application/json',
      'X-Email': email,
      'X-Password': password,
    };
  }

  Future<Map<String, String>?> _getChildHeaders({
    required String childHash,
    bool jsonBody = false,
  }) async {
    final effectiveChildHash = childHash.trim();
    if (effectiveChildHash.isEmpty) {
      return null;
    }

    return {
      if (jsonBody) 'Content-Type': 'application/json',
      'X-Child-Hash': effectiveChildHash,
    };
  }

  Future<void> _ensureEncryptionReady() async {
    if (!EncryptionService.instance.isInitialized) {
      await EncryptionService.instance.initialize();
    }
  }

  Future<void> openGuardianChat({required String childHash}) async {
    _activeRole = ChatRole.guardian;
    _activeChildHash = childHash;
    _activeGuardianId = null;
    await _loadMessages(markRead: true);
    _startPolling();
  }

  Future<void> openChildChat({
    required String childHash,
    required int guardianId,
  }) async {
    _activeRole = ChatRole.child;
    _activeChildHash = childHash;
    _activeGuardianId = guardianId;
    await _loadMessages(markRead: true);
    _startPolling();
  }

  Future<int?> ensureGuardianIdForChild(String childHash) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getInt('guardian_id');
    if (existing != null) {
      return existing;
    }

    try {
      final headers = await _getChildHeaders(childHash: childHash);
      if (headers == null) {
        return null;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/mobile/child/$childHash/guardians/public-keys/'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final guardians = (data['guardians'] as List?) ?? [];
      if (guardians.isEmpty) {
        return null;
      }

      final first = Map<String, dynamic>.from(guardians.first as Map);
      final rawId = first['guardian_id'] ?? first['id'];
      final guardianId =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

      if (guardianId != null) {
        await prefs.setInt('guardian_id', guardianId);
      }

      return guardianId;
    } catch (e) {
      debugPrint('❌ Chat: Failed to resolve guardian id: $e');
      return null;
    }
  }

  // Backward-compatible guardian connect entry
  Future<void> connect(String childHash) async {
    await openGuardianChat(childHash: childHash);
  }

  Future<bool> sendMessage(String childHash, String message) async {
    final text = message.trim();
    if (text.isEmpty) {
      return false;
    }

    if (_activeRole != ChatRole.guardian || _activeChildHash != childHash) {
      await openGuardianChat(childHash: childHash);
    }

    try {
      await _ensureEncryptionReady();
      final childPublicKey = await _fetchChildPublicKey(childHash);
      if (childPublicKey == null || childPublicKey.isEmpty) {
        debugPrint('❌ Chat: Child public key not available');
        return false;
      }

      final encryptedMessage =
          EncryptionService.instance.encryptWithPublicKey(text, childPublicKey);

      final headers = await _getGuardianHeaders(jsonBody: true);
      if (headers == null) {
        debugPrint('❌ Chat: Missing guardian credentials');
        return false;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/mobile/child/$childHash/chat/'),
        headers: headers,
        body: jsonEncode({'message_encrypted': encryptedMessage}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final localMessage = ChatMessage(
          messageId: (data['message_id'] ?? DateTime.now().millisecondsSinceEpoch)
              .toString(),
          senderHash: 'guardian',
          receiverHash: childHash,
          senderType: 'guardian',
          messageEncrypted: encryptedMessage,
          messageDecrypted: text,
          timestamp: DateTime.now(),
          isFromParent: true,
          senderName: 'You',
          isRead: true,
        );
        _appendMessage(localMessage);
        return true;
      }

      debugPrint('❌ Chat: Guardian send failed ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      debugPrint('❌ Chat: Guardian send error: $e');
      return false;
    }
  }

  Future<bool> sendMessageAsChild({
    required String childHash,
    required int guardianId,
    required String message,
  }) async {
    final text = message.trim();
    if (text.isEmpty) {
      return false;
    }

    if (_activeRole != ChatRole.child ||
        _activeChildHash != childHash ||
        _activeGuardianId != guardianId) {
      await openChildChat(childHash: childHash, guardianId: guardianId);
    }

    try {
      await _ensureEncryptionReady();

      final guardianPublicKey = await _fetchGuardianPublicKey(
        childHash: childHash,
        guardianId: guardianId,
      );
      if (guardianPublicKey == null || guardianPublicKey.isEmpty) {
        debugPrint('❌ Chat: Guardian public key not available');
        return false;
      }

      final encryptedMessage =
          EncryptionService.instance.encryptWithPublicKey(text, guardianPublicKey);

      final headers =
          await _getChildHeaders(childHash: childHash, jsonBody: true);
      if (headers == null) {
        debugPrint('❌ Chat: Missing child hash for send');
        return false;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/mobile/guardian/$guardianId/chat/'),
        headers: headers,
        body: jsonEncode({'message_encrypted': encryptedMessage}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final localMessage = ChatMessage(
          messageId: (data['message_id'] ?? DateTime.now().millisecondsSinceEpoch)
              .toString(),
          senderHash: childHash,
          receiverHash: guardianId.toString(),
          senderType: 'child',
          messageEncrypted: encryptedMessage,
          messageDecrypted: text,
          timestamp: DateTime.now(),
          isFromParent: false,
          senderName: 'You',
          isRead: true,
        );
        _appendMessage(localMessage);
        return true;
      }

      debugPrint('❌ Chat: Child send failed ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      debugPrint('❌ Chat: Child send error: $e');
      return false;
    }
  }

  Future<void> _loadMessages({bool markRead = false}) async {
    if (_activeRole == null || _activeChildHash == null) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      Uri uri;
      Map<String, String>? headers;

      if (_activeRole == ChatRole.guardian) {
        uri = Uri.parse(
          '$baseUrl/api/mobile/child/${_activeChildHash!}/chat/?limit=100&mark_read=${markRead ? 'true' : 'false'}',
        );
        headers = await _getGuardianHeaders();
      } else {
        if (_activeGuardianId == null) {
          _isConnected = false;
          return;
        }

        uri = Uri.parse(
          '$baseUrl/api/mobile/guardian/${_activeGuardianId!}/chat/?limit=100&mark_read=${markRead ? 'true' : 'false'}',
        );
        headers = await _getChildHeaders(childHash: _activeChildHash!);
      }

      if (headers == null) {
        _isConnected = false;
        return;
      }

      final response = await http.get(
        uri,
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawMessages = (data['messages'] as List?) ?? [];
        final parsed = await _parseAndDecryptMessages(rawMessages);

        parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _messages = parsed;
        _isConnected = true;
      } else {
        _isConnected = false;
        debugPrint('❌ Chat: load failed ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      _isConnected = false;
      debugPrint('❌ Chat: load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<ChatMessage>> _parseAndDecryptMessages(List<dynamic> rawMessages) async {
    await _ensureEncryptionReady();

    return rawMessages.map((raw) {
      final chatMessage = ChatMessage.fromJson(Map<String, dynamic>.from(raw as Map));

      final shouldDecrypt = (_activeRole == ChatRole.guardian && !chatMessage.isFromParent) ||
          (_activeRole == ChatRole.child && chatMessage.isFromParent);

      if (shouldDecrypt && chatMessage.messageEncrypted.isNotEmpty) {
        final decrypted =
            EncryptionService.instance.decryptWithPrivateKey(chatMessage.messageEncrypted);
        if (decrypted != null && decrypted.isNotEmpty) {
          return chatMessage.copyWith(messageDecrypted: decrypted);
        }
      }

      return chatMessage;
    }).toList();
  }

  void _appendMessage(ChatMessage message) {
    final exists = _messages.any((m) => m.messageId == message.messageId);
    if (!exists) {
      _messages = [..._messages, message]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } else {
      _messages = _messages.map((m) {
        if (m.messageId == message.messageId) {
          return message;
        }
        return m;
      }).toList();
    }

    _messageController.add(message);
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_isPolling) {
        return;
      }
      _isPolling = true;
      try {
        await _loadMessages();
      } finally {
        _isPolling = false;
      }
    });
  }

  Future<String?> _fetchChildPublicKey(String childHash) async {
    try {
      final headers = await _getGuardianHeaders();
      if (headers == null) {
        return null;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/mobile/child/$childHash/public-key/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['public_key']?.toString();
      }

      return null;
    } catch (e) {
      debugPrint('❌ Chat: Error fetching child key: $e');
      return null;
    }
  }

  Future<String?> _fetchGuardianPublicKey({
    required String childHash,
    required int guardianId,
  }) async {
    try {
      final headers = await _getChildHeaders(childHash: childHash);
      if (headers == null) {
        return null;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/mobile/guardian/$guardianId/public-key/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['public_key']?.toString();
      }

      return null;
    } catch (e) {
      debugPrint('❌ Chat: Error fetching guardian key: $e');
      return null;
    }
  }

  Future<void> fetchChatHistory(String childHash) async {
    if (_activeRole != ChatRole.guardian || _activeChildHash != childHash) {
      await openGuardianChat(childHash: childHash);
      return;
    }
    await _loadMessages(markRead: true);
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isPolling = false;
    _isConnected = false;
    notifyListeners();
  }

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
