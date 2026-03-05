import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../config.dart';
import '../models/time_extension_request.dart';
import '../utils/preferences_manager.dart';
import 'encryption_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Connection state — mirrors the four states in the WebSocket guide
// ─────────────────────────────────────────────────────────────────────────────
enum WsConnectionState { disconnected, connecting, connected, error }

enum ChildWsLogType { sent, received, system }

class ChildWsLogEntry {
  final ChildWsLogType type;
  final String content;
  final DateTime timestamp;

  const ChildWsLogEntry({
    required this.type,
    required this.content,
    required this.timestamp,
  });
}

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
  // ── URLs (derived from Config – single source of truth) ─────────────────
  static String get _baseUrl => Config.baseUrl;
  static String get _guardianWsUrl => Config.guardianWsUrl;
  static String _childWsUrl(String childHash) => Config.childWsUrl(childHash);

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
  Completer<void>? _childConnectCompleter;

  // ── Shared data ────────────────────────────────────────────────────────────
  List<TimeExtensionRequest> _pendingRequests = [];
  final StreamController<TimeExtensionRequest> _newRequestStreamCtrl =
      StreamController<TimeExtensionRequest>.broadcast();
  final StreamController<Map<String, dynamic>> _childResponseStreamCtrl =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _notifyScheduled = false;

  // Status / last-response text reported to the child UI
  String? _childWsStatusMessage;
  String? _lastChildWsResponse;
  String? _childErrorMessage;

  // Child debug/visibility fields for UI
  String? _childHashForWs;
  String? _childWsUrlForUi;
  String? _lastGuardianPublicKey;
  int? _lastGuardianId;
  String? _lastChildWsPayloadPretty;
  final List<ChildWsLogEntry> _childWsLog = [];

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
  Stream<Map<String, dynamic>> get childResponseStream =>
      _childResponseStreamCtrl.stream;

  void refreshPendingRequests() {
    _guardianSend({'type': 'get_pending_requests'});
  }

  // --- Child side ---
  WsConnectionState get childState        => _childState;
  bool get childWsConnected               => _childState == WsConnectionState.connected;
  String? get childWsStatusMessage        => _childWsStatusMessage;
  String? get lastChildWsResponse         => _lastChildWsResponse;
  String? get childErrorMessage            => _childErrorMessage;

  String childWsUrl(String childHash) => _childWsUrl(childHash);

  String? get childHashForWs              => _childHashForWs;
  String? get childWsUrlForUi             => _childWsUrlForUi;
  String? get lastGuardianPublicKey       => _lastGuardianPublicKey;
  int? get lastGuardianId                 => _lastGuardianId;
  String? get lastChildWsPayloadPretty    => _lastChildWsPayloadPretty;
  List<ChildWsLogEntry> get childWsLog    => List.unmodifiable(_childWsLog);

  void clearChildWsLog() {
    _childWsLog.clear();
    _notify();
  }

  Future<void> preloadGuardianKey({required String childHash}) async {
    await _fetchParentPublicKeyAndId(childHash);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GUARDIAN CHANNEL — parent side
  // ═══════════════════════════════════════════════════════════════════════════

  /// Opens the guardian WebSocket and waits for authentication to complete.
  /// Safe to call multiple times — no-ops if already connecting / connected.
  Future<void> connect() async {
    if (_guardianState == WsConnectionState.connecting ||
        _guardianState == WsConnectionState.connected) {
      return;
    }

    _setGuardianState(WsConnectionState.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(_guardianWsUrl));
      _guardianChannel = channel;

      // Guide rule 1: await handshake before attaching listener
      await channel.ready;

      if (_disposed) {
        _safeCloseGuardian();
        return;
      }

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
          final wsGuardianId = _extractGuardianId(data);
          if (wsGuardianId != null) {
            _lastGuardianId = wsGuardianId;
            PreferencesManager.init().then((prefs) =>
                prefs.setGuardianId(wsGuardianId));
          }
          debugPrint('✅ TimeExt Guardian: Authenticated '
              '(guardian_id=$wsGuardianId)');
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

        case 'task_completed':
          // Child completed the assigned task — update the matching request
          // so the parent UI can show the "Approve" button.
          final d = data['data'] as Map<String, dynamic>? ?? data;
          final reqId = d['request_id'] as int?;
          debugPrint('📋 TimeExt Guardian: Task completed for request #$reqId');
          if (reqId != null) {
            final idx = _pendingRequests.indexWhere((r) => r.requestId == reqId);
            if (idx != -1) {
              // Replace the request with an updated copy that reflects task completion
              final old = _pendingRequests[idx];
              _pendingRequests[idx] = TimeExtensionRequest(
                requestId: old.requestId,
                childHash: old.childHash,
                childName: d['child_name'] as String? ?? old.childName,
                appDomain: old.appDomain,
                requestedHours: old.requestedHours,
                messageEncrypted: old.messageEncrypted,
                status: 'task_completed',
                grantedHours: old.grantedHours,
                created: old.created,
                respondedAt: old.respondedAt,
                guardianId: old.guardianId,
                guardianName: old.guardianName,
                responseEncrypted: old.responseEncrypted,
                assignedTask: old.assignedTask != null
                    ? AssignedTask(
                        id: old.assignedTask!.id,
                        title: old.assignedTask!.title,
                        description: old.assignedTask!.description,
                        isCompleted: true,
                        completedAt: DateTime.now(),
                      )
                    : null,
                taskId: old.taskId,
                taskTitle: d['task_title'] as String? ?? old.taskTitle,
                taskDescription: old.taskDescription,
                isTaskCompleted: true,
              );
            } else {
              // Request not in our list yet — re-fetch from server
              fetchPendingRequests();
            }
          }
          _newRequestStreamCtrl.add(
            TimeExtensionRequest.fromJson(d),
          );
          _notify();

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
        _guardianState != WsConnectionState.connected) {
      return;
    }
    _guardianChannel!.sink.add(json.encode(payload));
  }

  void _scheduleGuardianReconnect() {
    if (_disposed) {
      return;
    }
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

  /// Directly approve a pending time extension request without assigning a task.
  /// Uses the dedicated `/approve/` endpoint (REST).
  Future<bool> approveRequest({
    required int requestId,
    double? grantedHours,
    String? responseEncrypted,
  }) async {
    debugPrint('📤 TimeExt Guardian: Approving request #$requestId directly');
    try {
      final prefs    = await PreferencesManager.init();
      final email    = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';

      final body = <String, dynamic>{};
      if (grantedHours != null) body['granted_hours'] = grantedHours;
      if (responseEncrypted != null && responseEncrypted.isNotEmpty) {
        body['response_encrypted'] = responseEncrypted;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/mobile/time-extension-requests/$requestId/approve/'),
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _pendingRequests.removeWhere((r) => r.requestId == requestId);
        _notify();
        debugPrint('✅ TimeExt Guardian: Request #$requestId approved via REST');
        return true;
      }
      debugPrint('❌ TimeExt Guardian: Approve HTTP ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('❌ TimeExt Guardian: Approve error – $e');
      return false;
    }
  }

  /// Loads pending requests via REST (initial boot / offline fallback).
  /// Fetches ALL active requests (pending + task_assigned) so the
  /// parent UI can segment them.
  Future<void> fetchPendingRequests() async {
    try {
      final prefs    = await PreferencesManager.init();
      final email    = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';

      // Fetch all statuses, then keep only active ones
      final response = await http.get(
        Uri.parse('$_baseUrl/api/mobile/time-extension-requests/?status=all'),
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final list = (data['requests'] as List? ?? []);
        // Include task_completed so parent sees tasks done by child and can approve
        const activeStatuses = {'pending', 'task_assigned', 'task_completed'};
        _pendingRequests = list
            .map((r) => TimeExtensionRequest.fromJson(r as Map<String, dynamic>))
            .where((r) => activeStatuses.contains(r.status))
            .toList();
        debugPrint('📋 TimeExt HTTP: ${_pendingRequests.length} active requests');
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
  ///
  /// Follows the same connect pattern as WEBSOCKET_APP_GUIDE.md:
  ///   1. No-op when already connecting / connected.
  ///   2. Resolve [childHash] from [PreferencesManager] when not supplied.
  ///   3. `channel.ready.then(…).catchError(…)` for the handshake.
  ///   4. Stream listener attached immediately (before ready resolves).
  ///   5. Returns a Future so callers (e.g. createRequest) can await.
  Future<void> connectChildSocket({String? childHash}) async {
    // Guide pattern: no-op when already connecting / connected.
    if (_childState == WsConnectionState.connected ||
        _childState == WsConnectionState.connecting) {
      // If a connect is already in-flight, await it.
      if (_childConnectCompleter != null) {
        await _childConnectCompleter!.future;
      }
      return;
    }

    // Resolve child hash dynamically from preferences when not passed in.
    final prefs = await PreferencesManager.init();
    final hash  = childHash ?? prefs.getChildHash() ?? '';

    _childHashForWs = hash;
    _childWsUrlForUi = hash.isEmpty ? null : _childWsUrl(hash);

    if (hash.isEmpty) {
      debugPrint('⚠️ TimeExt Child: No child_hash – cannot connect');
      _setChildStatus('No device ID – please log in again');
      _addChildLog(ChildWsLogType.system, 'No child hash available');
      return;
    }

    // Clean up any previous channel/subscription before reconnecting.
    // Silent: skip notifications — we'll notify with the new state immediately after.
    if (_childSub != null || _childChannel != null) {
      _disconnectChildSilent();
    }

    _setChildState(WsConnectionState.connecting);
    _childErrorMessage = null;
    _setChildStatus('Connecting…');
    _addChildLog(ChildWsLogType.system, 'Connecting to ${_childWsUrl(hash)}');

    _childConnectCompleter = Completer<void>();

    try {
      final channel =
          WebSocketChannel.connect(Uri.parse(_childWsUrl(hash)));
      _childChannel = channel;

      // Guide pattern: .then() / .catchError() on ready
      channel.ready.then((_) {
        if (_disposed) {
          _safeCloseChild();
          return;
        }
        _setChildState(WsConnectionState.connected);
        _setChildStatus('Connected');
        debugPrint('✅ TimeExt Child: Connected ($hash)');
        _addChildLog(ChildWsLogType.system, 'Connected to server');
        _childConnectCompleter?.complete();
        _childConnectCompleter = null;
      }).catchError((e) {
        if (_disposed) return;
        _childErrorMessage = e.toString();
        _setChildState(WsConnectionState.error);
        _setChildStatus('Connection failed');
        _addChildLog(ChildWsLogType.system, 'Connection failed: $e');
        debugPrint('❌ TimeExt Child: Connection failed – $e');
        _childConnectCompleter?.complete();
        _childConnectCompleter = null;
      });

      // Guide pattern: attach listener immediately (before ready resolves)
      _childSub = channel.stream.listen(
        _onChildMessage,
        onError: _onChildError,
        onDone:  _onChildDone,
        cancelOnError: false,
      );
    } catch (e) {
      _childErrorMessage = e.toString();
      _setChildState(WsConnectionState.error);
      _setChildStatus('Connection failed');
      _addChildLog(ChildWsLogType.system, 'Exception: $e');
      debugPrint('❌ TimeExt Child: Exception – $e');
      _childConnectCompleter?.complete();
      _childConnectCompleter = null;
    }

    // Allow callers (e.g. createRequest) to await the connection result.
    if (_childConnectCompleter != null) {
      await _childConnectCompleter!.future;
    }
  }

  /// Cleanly closes the child channel.
  /// Follows the guide's simple disconnect: cancel, close, null, null.
  void disconnectChild() {
    _disconnectChildSilent();
    if (!_disposed) {
      _setChildState(WsConnectionState.disconnected);
      _setChildStatus(null);
      _addChildLog(ChildWsLogType.system, 'Disconnected');
    }
  }

  /// Internal cleanup without notifications — used when reconnecting
  /// so that an intermediate 'disconnected' state is never broadcast.
  void _disconnectChildSilent() {
    _childSub?.cancel();
    _childChannel?.sink.close();
    _childChannel = null;
    _childSub = null;
    _childConnectCompleter?.complete();
    _childConnectCompleter = null;
  }

  // ── Child message router ───────────────────────────────────────────────────

  void _onChildMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final data = json.decode(raw as String) as Map<String, dynamic>;
      debugPrint('📨 TimeExt Child ← ${data['type']}');

      _addChildLog(
        ChildWsLogType.received,
        const JsonEncoder.withIndent('  ').convert(data),
      );

      // Speak to listeners
      _childResponseStreamCtrl.add(data);

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
          final grantedHrs = d['granted_hours'];
          final appDomain = d['app_domain'] as String? ?? '';
          if (status == 'approved') {
            _lastChildWsResponse =
                'Request approved! ${grantedHrs ?? ''} hours granted'
                '${appDomain.isNotEmpty ? ' for $appDomain' : ''}';
            debugPrint('✅ TimeExt Child: Approved – $grantedHrs h for $appDomain');
          } else {
            _lastChildWsResponse = 'Request denied';
            debugPrint('❌ TimeExt Child: Request denied');
          }
          // Emit on the stream so child_screen can re-fetch restrictions
          _childResponseStreamCtrl.add(data);
          _notify();

        case 'task_assigned':
          // Guardian assigned a task to the child for this request
          final d = data['data'] as Map<String, dynamic>? ?? data;
          debugPrint('📋 TimeExt Child: Task assigned – ${d['task_title'] ?? d['title'] ?? 'unknown'}');
          _lastChildWsResponse = 'Task assigned — complete it to earn time!';
          _childResponseStreamCtrl.add(data);
          _notify();

        case 'task_auto_approved':
          // Task was completed and time extension was auto-approved
          final d = data['data'] as Map<String, dynamic>? ?? data;
          debugPrint('🎉 TimeExt Child: Auto-approved after task completion');
          _lastChildWsResponse =
              'Time extension approved! ${d['granted_hours'] ?? ''} hours granted';
          _childResponseStreamCtrl.add(data);
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
      _addChildLog(ChildWsLogType.system, 'Parse error: $e');
    }
  }

  void _onChildError(dynamic error) {
    if (_disposed) return;
    debugPrint('❌ TimeExt Child stream error: $error');
    _safeCloseChild();
    _childSub = null;
    _setChildState(WsConnectionState.error);
    _setChildStatus('Connection error');
    _addChildLog(ChildWsLogType.system, 'Stream error: $error');
    if (_childRequestCompleter != null &&
        !_childRequestCompleter!.isCompleted) {
      _childRequestCompleter!.complete(false);
    }
  }

  void _onChildDone() {
    if (_disposed) return;
    debugPrint('🔌 TimeExt Child: Stream closed');
    _safeCloseChild();
    _childSub = null;
    _setChildState(WsConnectionState.disconnected);
    _addChildLog(ChildWsLogType.system, 'Connection closed');
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
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('📤 TimeExt Child: createRequest CALLED');
    debugPrint('   childHash=$childHash');
    debugPrint('   requestedHours=$requestedHours');
    debugPrint('   reason=$reason');
    debugPrint('   pkg=$packageName app=$appName');
    debugPrint('═══════════════════════════════════════════════════════');

    // ── 1. Encrypt reason ───────────────────────────────────────────────────
    String encrypted;
    int? guardianId;

    if (messageEncrypted != null && messageEncrypted.isNotEmpty) {
      encrypted = messageEncrypted;
      final prefs = await PreferencesManager.init();
      guardianId = prefs.getGuardianId();
      _lastGuardianId = guardianId;
      debugPrint('📝 TimeExt Child: Using pre-encrypted message');
    } else {
      try {
        final parentData = await _fetchParentPublicKeyAndId(childHash);
        final publicKey = parentData['public_key'] as String?;
        guardianId = _extractGuardianId(parentData);

        _lastGuardianPublicKey = publicKey;
        _lastGuardianId = guardianId;

        if (publicKey != null && publicKey.isNotEmpty) {
          encrypted = EncryptionService.instance.encryptWithPublicKey(reason, publicKey);
          debugPrint('🔐 TimeExt Child: Successfully encrypted reason with guardian public key');
        } else {
          debugPrint('⚠️ TimeExt Child: No public key found, falling back to base64');
          encrypted = base64.encode(utf8.encode(reason));
        }
      } catch (e) {
        debugPrint('⚠️ TimeExt Child: Encryption fail – $e; using base64');
        encrypted = base64.encode(utf8.encode(reason));
      }
    }

    // Best-effort fallback: if guardianId wasn't parsed from HTTP response,
    // pull it from local prefs (e.g. previously cached).
    guardianId ??= (await PreferencesManager.init()).getGuardianId();
    _lastGuardianId = guardianId;

    // ── 2. Connect child WS if needed ───────────────────────────────────────
    if (_childState != WsConnectionState.connected) {
      debugPrint('🔌 TimeExt Child: WS not connected, attempting to connect...');
      await connectChildSocket(childHash: childHash);
    }

    // ── 3 & 4. Send via WebSocket ────────────────────────────────────────────
    if (_childState == WsConnectionState.connected && _childChannel != null) {
      _childRequestCompleter = Completer<bool>();

      final payload = {
        'type': 'time_extension_request',
        'data': {
          'app_domain': packageName ?? appName ?? '',
          'requested_hours': requestedHours,
          'message_encrypted': encrypted,
          if (guardianId != null) 'guardian_id': guardianId,
        },
      };

      _lastChildWsPayloadPretty =
          const JsonEncoder.withIndent('  ').convert(payload);
      _addChildLog(ChildWsLogType.sent, _lastChildWsPayloadPretty!);

      // ── DEBUG: log WSS link, guardian public key & payload ──────────────
      final wsLink = _childWsUrl(childHash);
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('🔗 TIME-EXT WSS LINK: $wsLink');
      debugPrint('🔑 GUARDIAN PUBLIC KEY: ${_lastGuardianPublicKey ?? "NULL"}');
      debugPrint('📦 PAYLOAD SENT:\n$_lastChildWsPayloadPretty');
      debugPrint('═══════════════════════════════════════════════════════');
      // ── END DEBUG ──────────────────────────────────────────────────────

      _childChannel!.sink.add(json.encode(payload));

      _setChildStatus('Request sent – waiting for confirmation…');
      debugPrint('📡 TimeExt Child: Payload sent – awaiting ack…');

      try {
        final ack = await _childRequestCompleter!.future
            .timeout(const Duration(seconds: 10), onTimeout: () {
          debugPrint('⏱️ TimeExt Child: No ack after 10 s – assuming sent');
          return true; // optimistic timeout
        });
        _childRequestCompleter = null;
        if (ack) {
          _setChildStatus('Request delivered to guardian');
          debugPrint('✅ TimeExt Child: Request acknowledged via WS');
          return true;
        } else {
          debugPrint('⚠️ TimeExt Child: Ack was false');
          return false;
        }
      } catch (e) {
        _childRequestCompleter = null;
        debugPrint('❌ TimeExt Child: WS ack error – $e');
        _addChildLog(ChildWsLogType.system, 'Ack error: $e');
        return false;
      }
    } else {
      debugPrint('❌ TimeExt Child: WS connection failed, cannot send request');
      _setChildStatus('Failed to connect to server');
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
      // Use the documented endpoint: GET /api/mobile/child/<child_hash>/guardians/public-keys/
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/api/mobile/child/$childHash/guardians/public-keys/'),
        headers: {
          'Content-Type': 'application/json',
          'X-Child-Hash': childHash,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Response format: { "guardians": [{"guardian_id": 1, "guardian_name": "...", "public_key": "..."}] }
        final guardians = (data['guardians'] as List?) ?? [];
        if (guardians.isNotEmpty) {
          final first = Map<String, dynamic>.from(guardians.first as Map);
          final guardianId = _extractGuardianId(first);
          final publicKey = first['public_key'] as String?;

          _lastGuardianId = guardianId;
          _lastGuardianPublicKey = publicKey;
          if (guardianId != null) {
            final prefs = await PreferencesManager.init();
            await prefs.setGuardianId(guardianId);
          }
          debugPrint('✅ TimeExt: Guardian key fetched (id=$guardianId)');
          _notify();
          return first;
        } else {
          debugPrint('⚠️ TimeExt: No guardians found in response');
        }
      } else {
        debugPrint('❌ TimeExt: Guardian keys HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ TimeExt: Failed to fetch guardian key – $e');
    }
    return {};
  }

  int? _extractGuardianId(Map<String, dynamic> data) {
    final raw = data['guardian_id'] ?? data['id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  void _addChildLog(ChildWsLogType type, String content) {
    _childWsLog.add(
      ChildWsLogEntry(type: type, content: content, timestamp: DateTime.now()),
    );
    if (_childWsLog.length > 200) {
      _childWsLog.removeRange(0, _childWsLog.length - 200);
    }
    _notify();
  }

  void _notify() {
    if (_disposed) return;

    // Coalesce rapid-fire state changes into a single notifyListeners().
    // Uses Future.microtask so the notification fires after the current
    // synchronous call-stack completes but does NOT depend on a frame being
    // scheduled (addPostFrameCallback can stall when no animation is active).
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      if (_disposed) return;
      notifyListeners();
    });
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
