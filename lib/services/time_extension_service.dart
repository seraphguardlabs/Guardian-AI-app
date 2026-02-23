import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../models/time_extension_request.dart';
import '../utils/preferences_manager.dart';
import 'encryption_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Connection state — mirrors the four states in the WebSocket guide
// ─────────────────────────────────────────────────────────────────────────────
enum WsConnectionState { disconnected, connecting, connected, error }

// ─────────────────────────────────────────────────────────────────────────────
// TimeExtensionService
//
// Manages two independent WebSocket connections:
//   • Guardian channel  — wss://.../ws/guardian/time-extension/
//     Used by the parent to receive requests and send responses.
//   • Child channel     — wss://.../ws/child/<hash>/time-extension/
//     Used by the child to submit extension requests.
//
// Design rules (from WEBSOCKET_APP_GUIDE.md):
//   1. channel.ready  is awaited before sending any message.
//   2. Exactly one StreamSubscription per channel; cancelled in disconnect().
//   3. No auto-connect in constructor — callers decide when to connect.
//   4. All async callbacks guard with if (!_disposed).
//   5. Guardian reconnects with exponential back-off capped at 30 s.
// ─────────────────────────────────────────────────────────────────────────────
class TimeExtensionService extends ChangeNotifier {
  // ── URLs ───────────────────────────────────────────────────────────────────
  static const String _baseUrl = 'https://seraphguardlabs.com';
  static const String _guardianWsUrl =
      'wss://seraphguardlabs.com/ws/guardian/time-extension/';
  static String _childWsUrl(String childHash) =>
      'wss://seraphguardlabs.com/ws/child/$childHash/time-extension/';

  // ── Guardian channel ───────────────────────────────────────────────────────
  WebSocketChannel? _guardianChannel;
  StreamSubscription<dynamic>? _guardianSub;
  WsConnectionState _guardianState = WsConnectionState.disconnected;
  bool _guardianAuthenticated = false;
  int _guardianReconnectAttempts = 0;
  Timer? _guardianReconnectTimer;

  // ── Child channel ──────────────────────────────────────────────────────────
  WebSocketChannel? _childChannel;
  StreamSubscription<dynamic>? _childSub;
  WsConnectionState _childState = WsConnectionState.disconnected;
  Completer<bool>? _childRequestCompleter;

  // ── Shared data ────────────────────────────────────────────────────────────
  List<TimeExtensionRequest> _pendingRequests = [];
  final StreamController<TimeExtensionRequest> _newRequestStreamCtrl =
      StreamController<TimeExtensionRequest>.broadcast();

  // Status / last-response text reported to the child UI
  String? _childWsStatusMessage;
  String? _lastChildWsResponse;

  bool _disposed = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  // --- Guardian (parent) side ---
  WsConnectionState get guardianState     => _guardianState;
  bool get isConnected                    => _guardianState == WsConnectionState.connected;
  bool get isAuthenticated                => _guardianAuthenticated;
  List<TimeExtensionRequest> get pendingRequests =>
      List.unmodifiable(_pendingRequests);
  Stream<TimeExtensionRequest> get newRequestStream =>
      _newRequestStreamCtrl.stream;

  // --- Child side ---
  WsConnectionState get childState        => _childState;
  bool get childWsConnected               => _childState == WsConnectionState.connected;
  String? get childWsStatusMessage        => _childWsStatusMessage;
  String? get lastChildWsResponse         => _lastChildWsResponse;

  // ═══════════════════════════════════════════════════════════════════════════
  // GUARDIAN CHANNEL — parent side
  // ═══════════════════════════════════════════════════════════════════════════

  /// Opens the guardian WebSocket and waits for authentication to complete.
  /// Safe to call multiple times — no-ops if already connecting / connected.
  Future<void> connect() async {
    if (_guardianState == WsConnectionState.connecting ||
        _guardianState == WsConnectionState.connected) return;

    _setGuardianState(WsConnectionState.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(_guardianWsUrl));
      _guardianChannel = channel;

      // Guide rule 1: await handshake before attaching listener
      await channel.ready;

      if (_disposed) { _safeCloseGuardian(); return; }

      _guardianSub = channel.stream.listen(
        _onGuardianMessage,
        onError: _onGuardianError,
        onDone:  _onGuardianDone,
        cancelOnError: false,
      );

      _setGuardianState(WsConnectionState.connected);
      _guardianReconnectAttempts = 0;
      debugPrint('✅ TimeExt Guardian: Connected – awaiting auth_required');

    } catch (e) {
      debugPrint('❌ TimeExt Guardian: Connection failed – $e');
      _setGuardianState(WsConnectionState.error);
      _scheduleGuardianReconnect();
    }
  }

  /// Cleanly closes the guardian channel and cancels any reconnect timer.
  Future<void> disconnectGuardian() async {
    _guardianReconnectTimer?.cancel();
    _guardianReconnectTimer = null;
    await _guardianSub?.cancel();
    _guardianSub = null;
    try {
      await _guardianChannel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _guardianChannel = null;
    _guardianAuthenticated = false;
    _setGuardianState(WsConnectionState.disconnected);
    debugPrint('🔌 TimeExt Guardian: Disconnected');
  }

  // ── Guardian message router ────────────────────────────────────────────────

  void _onGuardianMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final data = json.decode(raw as String) as Map<String, dynamic>;
      debugPrint('📨 TimeExt Guardian ← ${data['type']}');

      switch (data['type']) {
        case 'auth_required':
          _sendGuardianAuth();

        case 'auth_success':
          _guardianAuthenticated = true;
          debugPrint('✅ TimeExt Guardian: Authenticated '
              '(guardian_id=${data['guardian_id']})');
          _notify();
          _guardianSend({'type': 'get_pending_requests'});

        case 'pending_requests':
          final list = (data['requests'] as List? ?? []);
          _pendingRequests = list
              .map((r) =>
                  TimeExtensionRequest.fromJson(r as Map<String, dynamic>))
              .toList();
          debugPrint(
              '📋 TimeExt Guardian: ${_pendingRequests.length} pending requests');
          _notify();

        case 'time_extension_request':
          final req = TimeExtensionRequest.fromJson(
              data['data'] as Map<String, dynamic>);
          _pendingRequests.add(req);
          _newRequestStreamCtrl.add(req);
          debugPrint(
              '🔔 TimeExt Guardian: New request from ${req.childName}');
          _notify();

        case 'response_sent':
          final id = data['request_id'] as int?;
          if (id != null) {
            _pendingRequests.removeWhere((r) => r.requestId == id);
            debugPrint('✅ TimeExt Guardian: Request #$id resolved');
            _notify();
          }

        case 'error':
          debugPrint(
              '❌ TimeExt Guardian server error: ${data['message']}');

        default:
          debugPrint(
              'ℹ️ TimeExt Guardian: Unknown type "${data['type']}"');
      }
    } catch (e) {
      debugPrint('❌ TimeExt Guardian: Parse error – $e');
    }
  }

  void _onGuardianError(dynamic error) {
    if (_disposed) return;
    debugPrint('❌ TimeExt Guardian stream error: $error');
    _guardianAuthenticated = false;
    _setGuardianState(WsConnectionState.error);
    _scheduleGuardianReconnect();
  }

  void _onGuardianDone() {
    if (_disposed) return;
    debugPrint('🔌 TimeExt Guardian: Stream closed');
    final wasConnected = _guardianState == WsConnectionState.connected;
    _guardianAuthenticated = false;
    _setGuardianState(WsConnectionState.disconnected);
    if (wasConnected) _scheduleGuardianReconnect();
  }

  // ── Guardian auth helper ───────────────────────────────────────────────────

  Future<void> _sendGuardianAuth() async {
    final prefs    = await PreferencesManager.init();
    final email    = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    if (email.isEmpty || password.isEmpty) {
      debugPrint('⚠️ TimeExt Guardian: No credentials – skipping auth');
      return;
    }
    debugPrint('🔐 TimeExt Guardian: Sending auth for $email');
    _guardianSend({'type': 'auth', 'email': email, 'password': password});
  }

  // ── Guardian utilities ─────────────────────────────────────────────────────

  void _guardianSend(Map<String, dynamic> payload) {
    if (_guardianChannel == null ||
        _guardianState != WsConnectionState.connected) return;
    _guardianChannel!.sink.add(json.encode(payload));
  }

  void _scheduleGuardianReconnect() {
    if (_disposed) return;
    _guardianReconnectTimer?.cancel();
    _guardianReconnectAttempts++;
    final delay =
        Duration(seconds: (_guardianReconnectAttempts * 2).clamp(2, 30));
    debugPrint('⏳ TimeExt Guardian: Reconnect in ${delay.inSeconds}s '
        '(attempt $_guardianReconnectAttempts)');
    _guardianReconnectTimer = Timer(delay, connect);
  }

  void _safeCloseGuardian() {
    try {
      _guardianChannel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _guardianChannel = null;
  }

  void _setGuardianState(WsConnectionState s) {
    _guardianState = s;
    _notify();
  }

  // ── Respond to a request (parent action) ──────────────────────────────────

  /// Sends the guardian's decision (approve / deny / message).
  /// Tries WebSocket first; falls back to HTTP when not authenticated.
  Future<bool> respondToRequest({
    required int requestId,
    required String action, // 'approve' | 'deny' | 'message'
    double? grantedHours,
    String? responseEncrypted,
  }) async {
    debugPrint(
        '📤 TimeExt Guardian: Responding to #$requestId action=$action');

    if (_guardianAuthenticated && _guardianChannel != null) {
      // WebSocket path
      _guardianSend({
        'type': 'time_extension_response',
        'data': {
          'request_id': requestId,
          'action': action,
          if (grantedHours != null) 'granted_hours': grantedHours,
          'response_encrypted': responseEncrypted ?? '',
        },
      });
      _pendingRequests.removeWhere((r) => r.requestId == requestId);
      _notify();
      debugPrint('✅ TimeExt Guardian: Response sent via WebSocket');
      return true;
    }

    // HTTP fallback
    debugPrint('📡 TimeExt Guardian: WS not ready – HTTP fallback');
    try {
      final prefs    = await PreferencesManager.init();
      final email    = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';

      final response = await http.post(
        Uri.parse('$_baseUrl/api/mobile/time-extension-requests/'
            '$requestId/respond/'),
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
        body: json.encode({
          'action': action,
          if (grantedHours != null) 'granted_hours': grantedHours,
          'response_encrypted': responseEncrypted ?? '',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _pendingRequests.removeWhere((r) => r.requestId == requestId);
        _notify();
        debugPrint('✅ TimeExt Guardian: HTTP response sent');
        return true;
      }
      debugPrint(
          '❌ TimeExt Guardian: HTTP ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('❌ TimeExt Guardian: HTTP error – $e');
      return false;
    }
  }

  /// Asks the server for the latest pending-request list.
  void requestPendingUpdates() =>
      _guardianSend({'type': 'get_pending_requests'});

  /// Loads pending requests via REST (initial boot / offline fallback).
  Future<void> fetchPendingRequests() async {
    try {
      final prefs    = await PreferencesManager.init();
      final email    = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';

      final response = await http.get(
        Uri.parse(
            '$_baseUrl/api/mobile/time-extension-requests/?status=pending'),
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final list = (data['requests'] as List? ?? []);
        _pendingRequests = list
            .map((r) =>
                TimeExtensionRequest.fromJson(r as Map<String, dynamic>))
            .toList();
        debugPrint(
            '📋 TimeExt HTTP: ${_pendingRequests.length} pending requests');
        _notify();
      }
    } catch (e) {
      debugPrint('❌ TimeExt HTTP: fetchPendingRequests error – $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHILD CHANNEL — child side
  // ═══════════════════════════════════════════════════════════════════════════

  /// Opens the child time-extension WebSocket.
  Future<void> connectChildSocket({String? childHash}) async {
    if (_childState == WsConnectionState.connecting ||
        _childState == WsConnectionState.connected) return;

    final prefs = await PreferencesManager.init();
    final hash  = childHash ?? prefs.getChildHash() ?? '';

    if (hash.isEmpty) {
      debugPrint('⚠️ TimeExt Child: No child_hash – cannot connect');
      _setChildStatus('No device ID – please log in again');
      return;
    }

    _setChildState(WsConnectionState.connecting);
    _setChildStatus('Connecting…');

    try {
      final channel =
          WebSocketChannel.connect(Uri.parse(_childWsUrl(hash)));
      _childChannel = channel;

      await channel.ready;

      if (_disposed) { _safeCloseChild(); return; }

      _childSub = channel.stream.listen(
        _onChildMessage,
        onError: _onChildError,
        onDone:  _onChildDone,
        cancelOnError: false,
      );

      _setChildState(WsConnectionState.connected);
      _setChildStatus('Connected');
      debugPrint('✅ TimeExt Child: Connected ($hash)');

    } catch (e) {
      debugPrint('❌ TimeExt Child: Connection failed – $e');
      _setChildState(WsConnectionState.error);
      _setChildStatus('Connection failed – will retry');
    }
  }

  /// Cleanly closes the child channel.
  Future<void> disconnectChild() async {
    await _childSub?.cancel();
    _childSub = null;
    try {
      await _childChannel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _childChannel = null;
    _setChildState(WsConnectionState.disconnected);
    _setChildStatus(null);
  }

  // ── Child message router ───────────────────────────────────────────────────

  void _onChildMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final data = json.decode(raw as String) as Map<String, dynamic>;
      debugPrint('📨 TimeExt Child ← ${data['type']}');

      switch (data['type']) {
        case 'connection_established':
          _setChildStatus('Ready');
          debugPrint('✅ TimeExt Child: ${data['message']}');

        case 'request_created':
          final msg = data['message'] as String? ?? 'Request sent';
          _lastChildWsResponse = msg;
          _setChildStatus(msg);
          debugPrint(
              '✅ TimeExt Child: Request #${data['request_id']} – $msg');
          if (_childRequestCompleter != null &&
              !_childRequestCompleter!.isCompleted) {
            _childRequestCompleter!.complete(true);
          }

        case 'time_extension_response':
          final d = data['data'] as Map<String, dynamic>? ?? {};
          final status = d['status'] as String? ?? '';
          _lastChildWsResponse =
              'Request ${status == 'approved' ? 'approved' : 'denied'}';
          _notify();

        case 'error':
          final msg = data['message'] as String? ?? 'Server error';
          _lastChildWsResponse = msg;
          _setChildStatus('Error: $msg');
          debugPrint('❌ TimeExt Child server error: $msg');
          if (_childRequestCompleter != null &&
              !_childRequestCompleter!.isCompleted) {
            _childRequestCompleter!.complete(false);
          }

        default:
          debugPrint('ℹ️ TimeExt Child: Unknown type "${data['type']}"');
      }
    } catch (e) {
      debugPrint('❌ TimeExt Child: Parse error – $e');
    }
  }

  void _onChildError(dynamic error) {
    if (_disposed) return;
    debugPrint('❌ TimeExt Child stream error: $error');
    _setChildState(WsConnectionState.error);
    _setChildStatus('Connection error');
    if (_childRequestCompleter != null &&
        !_childRequestCompleter!.isCompleted) {
      _childRequestCompleter!.complete(false);
    }
  }

  void _onChildDone() {
    if (_disposed) return;
    debugPrint('🔌 TimeExt Child: Stream closed');
    _setChildState(WsConnectionState.disconnected);
    if (_childRequestCompleter != null &&
        !_childRequestCompleter!.isCompleted) {
      _childRequestCompleter!.complete(false);
    }
  }

  // ── Create time extension request (child action) ──────────────────────────

  /// Submits a time-extension request from the child.
  ///
  /// Steps:
  ///   1. Fetch guardian public key and encrypt [reason].
  ///   2. Ensure child WebSocket is connected.
  ///   3. Send `time_extension_request` message.
  ///   4. Await `request_created` ack (≤10 s); fall back to HTTP on failure.
  Future<bool> createRequest({
    required String childHash,
    required double requestedHours,
    required String reason,
    String? packageName,
    String? appName,
    String? messageEncrypted, // pre-encrypted override
  }) async {
    debugPrint('📤 TimeExt Child: createRequest – ${requestedHours}h '
        'pkg=$packageName app=$appName');

    // ── 1. Encrypt reason ───────────────────────────────────────────────────
    String encrypted;
    int? guardianId;

    if (messageEncrypted != null && messageEncrypted.isNotEmpty) {
      encrypted  = messageEncrypted;
      final prefs = await PreferencesManager.init();
      guardianId  = prefs.getGuardianId();
    } else {
      try {
        final parentData = await _fetchParentPublicKeyAndId(childHash);
        final publicKey  = parentData['public_key'] as String?;
        guardianId       = parentData['guardian_id'] as int?;

        if (publicKey != null && publicKey.isNotEmpty) {
          encrypted = EncryptionService.instance
                  .encryptWithPublicKey(reason, publicKey) ??
              base64.encode(utf8.encode(reason));
        } else {
          encrypted = base64.encode(utf8.encode(reason));
        }
      } catch (e) {
        debugPrint('⚠️ TimeExt Child: Encryption fail – $e; using base64');
        encrypted = base64.encode(utf8.encode(reason));
      }
    }

    // ── 2. Connect child WS if needed ───────────────────────────────────────
    if (_childState != WsConnectionState.connected) {
      await connectChildSocket(childHash: childHash);
    }

    // ── 3 & 4. Send via WebSocket ────────────────────────────────────────────
    if (_childState == WsConnectionState.connected && _childChannel != null) {
      _childRequestCompleter = Completer<bool>();

      _childChannel!.sink.add(json.encode({
        'type': 'time_extension_request',
        'data': {
          'app_domain': packageName ?? appName ?? '',
          'requested_hours': requestedHours,
          'message_encrypted': encrypted,
          if (guardianId != null) 'guardian_id': guardianId,
        },
      }));

      _setChildStatus('Request sent – waiting for confirmation…');
      debugPrint('📡 TimeExt Child: Payload sent – awaiting ack…');

      try {
        final ack = await _childRequestCompleter!.future
            .timeout(const Duration(seconds: 10), onTimeout: () {
          debugPrint('⏱️ TimeExt Child: No ack after 10 s – assuming sent');
          return true; // optimistic timeout
        });
        _childRequestCompleter = null;
        if (ack) _setChildStatus('Request delivered to guardian');
        debugPrint(ack
            ? '✅ TimeExt Child: Request acknowledged'
            : '⚠️ TimeExt Child: Ack was false');
        return ack;
      } catch (e) {
        _childRequestCompleter = null;
        debugPrint('❌ TimeExt Child: WS ack error – $e');
      }
    }

    // ── 5. HTTP fallback ─────────────────────────────────────────────────────
    return _createRequestHttp(
      childHash: childHash,
      requestedHours: requestedHours,
      packageName: packageName ?? '',
      appName: appName ?? '',
      encrypted: encrypted,
      guardianId: guardianId,
    );
  }

  Future<bool> _createRequestHttp({
    required String childHash,
    required double requestedHours,
    required String packageName,
    required String appName,
    required String encrypted,
    int? guardianId,
  }) async {
    debugPrint('📡 TimeExt Child: HTTP fallback for createRequest');
    try {
      final response = await http.post(
        Uri.parse(
            '$_baseUrl/api/mobile/time-extension-requests/create/'),
        headers: {
          'Content-Type': 'application/json',
          'X-Child-Hash': childHash,
        },
        body: json.encode({
          'child_hash': childHash,
          'app_domain': packageName,
          'app_name': appName,
          'requested_hours': requestedHours,
          'message_encrypted': encrypted,
          if (guardianId != null) 'guardian_id': guardianId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _setChildStatus('Request sent successfully');
        debugPrint('✅ TimeExt Child: HTTP request created');
        return true;
      }
      debugPrint(
          '❌ TimeExt Child: HTTP ${response.statusCode} – ${response.body}');
      _setChildStatus('Request failed (${response.statusCode})');
      return false;
    } catch (e) {
      debugPrint('❌ TimeExt Child: HTTP error – $e');
      _setChildStatus('Network error');
      return false;
    }
  }

  // ── Child utilities ────────────────────────────────────────────────────────

  void _safeCloseChild() {
    try {
      _childChannel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _childChannel = null;
  }

  void _setChildState(WsConnectionState s) {
    _childState = s;
    _notify();
  }

  void _setChildStatus(String? msg) {
    _childWsStatusMessage = msg;
    _notify();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> _fetchParentPublicKeyAndId(
      String childHash) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/api/mobile/child/$childHash/guardian-public-key/'),
        headers: {
          'Content-Type': 'application/json',
          'X-Child-Hash': childHash,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final guardianId = data['guardian_id'] as int?;
        if (guardianId != null) {
          final prefs = await PreferencesManager.init();
          await prefs.setGuardianId(guardianId);
        }
        debugPrint('✅ TimeExt: Guardian key fetched (id=$guardianId)');
        return data;
      }
    } catch (e) {
      debugPrint('❌ TimeExt: Failed to fetch guardian key – $e');
    }
    return {};
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _disposed = true;
    _guardianReconnectTimer?.cancel();
    _guardianSub?.cancel();
    try {
      _guardianChannel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _childSub?.cancel();
    try {
      _childChannel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _newRequestStreamCtrl.close();
    super.dispose();
  }
}
