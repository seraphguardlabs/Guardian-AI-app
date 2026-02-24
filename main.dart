import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Extension — Debug Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const WebSocketScreen(),
    );
  }
}

// ── Connection state ──────────────────────────────────────────────────────────

enum ConnectionStatus { disconnected, connecting, connected, error }

// ── Main screen ───────────────────────────────────────────────────────────────

class WebSocketScreen extends StatefulWidget {
  const WebSocketScreen({super.key});

  @override
  State<WebSocketScreen> createState() => _WebSocketScreenState();
}

class _WebSocketScreenState extends State<WebSocketScreen>
    with SingleTickerProviderStateMixin {
  static const String _baseApi  = 'https://seraphguardlabs.com';
  static const String _wsBase   = 'wss://seraphguardlabs.com/ws/child/';
  static const String _wsPath   = '/time-extension/';

  // ── Controllers ────────────────────────────────────────────────────────────
  final TextEditingController _childHashCtrl = TextEditingController();
  final TextEditingController _appDomainCtrl = TextEditingController();
  final TextEditingController _hoursCtrl     = TextEditingController();
  final TextEditingController _reasonCtrl    = TextEditingController();

  // ── WSS connection ─────────────────────────────────────────────────────────
  String get _wsUrl =>
      '$_wsBase${_childHashCtrl.text.trim()}$_wsPath';

  WebSocketChannel?    _channel;
  StreamSubscription?  _subscription;
  ConnectionStatus     _status = ConnectionStatus.disconnected;
  String?              _wsError;

  // ── Parent public key ──────────────────────────────────────────────────────
  String? _parentPublicKey;
  int?    _guardianId;
  bool    _fetchingKey = false;
  String? _keyError;

  // ── Messages ───────────────────────────────────────────────────────────────
  final List<_Message>       _messages        = [];
  final ScrollController     _scrollController = ScrollController();

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _childHashCtrl.addListener(_rebuild);
    _appDomainCtrl.addListener(_rebuild);
    _hoursCtrl.addListener(_rebuild);
    _reasonCtrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _pulseController.dispose();
    _subscription?.cancel();
    _channel?.sink.close();
    _scrollController.dispose();
    _childHashCtrl.dispose();
    _appDomainCtrl.dispose();
    _hoursCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ── WebSocket helpers ──────────────────────────────────────────────────────

  void _connect() {
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) return;

    final hash = _childHashCtrl.text.trim();
    if (hash.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the Child Hash before connecting.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _status  = ConnectionStatus.connecting;
      _wsError = null;
    });

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _channel!.ready.then((_) {
        if (mounted) {
          setState(() => _status = ConnectionStatus.connected);
          _addMessage(_Message.system('Connected → $_wsUrl'));
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _status  = ConnectionStatus.error;
            _wsError = e.toString();
          });
          _addMessage(_Message.system('Connection failed: $e'));
        }
      });

      _subscription = _channel!.stream.listen(
        (data) => _addMessage(_Message.received(data.toString())),
        onError: (e) {
          if (mounted) {
            setState(() {
              _status  = ConnectionStatus.error;
              _wsError = e.toString();
            });
            _addMessage(_Message.system('Stream error: $e'));
          }
        },
        onDone: () {
          if (mounted) {
            setState(() => _status = ConnectionStatus.disconnected);
            _addMessage(_Message.system('Connection closed by server'));
          }
        },
      );
    } catch (e) {
      setState(() {
        _status  = ConnectionStatus.error;
        _wsError = e.toString();
      });
      _addMessage(_Message.system('Exception: $e'));
    }
  }

  void _disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel      = null;
    _subscription = null;
    if (mounted) {
      setState(() => _status = ConnectionStatus.disconnected);
      _addMessage(_Message.system('Disconnected'));
    }
  }

  // ── Fetch parent public key ────────────────────────────────────────────────

  Future<void> _fetchParentKey() async {
    final hash = _childHashCtrl.text.trim();
    if (hash.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the Child Hash first.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() {
      _fetchingKey    = true;
      _keyError       = null;
      _parentPublicKey = null;
      _guardianId     = null;
    });
    try {
      final url = Uri.parse(
          '$_baseApi/api/mobile/child/$hash/guardian-public-key/');
      _addMessage(_Message.system('GET $url'));

      final res = await http.get(url,
          headers: {'Content-Type': 'application/json'});
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        final pk  = body['public_key'] as String? ?? '';
        final gid = body['guardian_id'];
        setState(() {
          _parentPublicKey = pk;
          _guardianId = gid is int ? gid : int.tryParse('$gid');
        });
        _addMessage(_Message.system(
            'Key fetched ✓  guardian_id=$_guardianId  (${pk.length} chars)'));
      } else {
        setState(() => _keyError = 'HTTP ${res.statusCode}: ${res.body}');
        _addMessage(_Message.system('Key fetch failed: HTTP ${res.statusCode}'));
      }
    } catch (e) {
      setState(() => _keyError = e.toString());
      _addMessage(_Message.system('Key fetch error: $e'));
    } finally {
      setState(() => _fetchingKey = false);
    }
  }

  // ── Send payload ───────────────────────────────────────────────────────────

  void _sendPayload() {
    if (_status != ConnectionStatus.connected || _channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to the WSS server first.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final domain = _appDomainCtrl.text.trim();
    final hours  = double.tryParse(_hoursCtrl.text.trim());
    final reason = _reasonCtrl.text.trim();

    if (domain.isEmpty || hours == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fill in App/Domain and Hours.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_guardianId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fetch the Parent Public Key first so guardian_id is known.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // In production the real app uses RSA; here we base64-encode for debug
    final encrypted = base64.encode(utf8.encode(reason.isEmpty ? '(no reason)' : reason));

    final payload = {
      "type": "time_extension_request",
      "data": {
        "app_domain":        domain,
        "requested_hours":   hours,
        "message_encrypted": encrypted,
        "guardian_id":       _guardianId,
      },
    };

    _channel!.sink.add(jsonEncode(payload));
    _addMessage(
        _Message.sent(const JsonEncoder.withIndent('  ').convert(payload)));
  }

  // ── Message helpers ────────────────────────────────────────────────────────

  void _addMessage(_Message msg) {
    setState(() => _messages.add(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearMessages() => setState(() => _messages.clear());

  // ── Status helpers ─────────────────────────────────────────────────────────

  Color get _statusColor => switch (_status) {
        ConnectionStatus.connected    => const Color(0xFF4CAF50),
        ConnectionStatus.connecting   => const Color(0xFFFFB300),
        ConnectionStatus.error        => const Color(0xFFF44336),
        ConnectionStatus.disconnected => const Color(0xFF9E9E9E),
      };

  String get _statusLabel => switch (_status) {
        ConnectionStatus.connected    => 'Connected',
        ConnectionStatus.connecting   => 'Connecting…',
        ConnectionStatus.error        => 'Error',
        ConnectionStatus.disconnected => 'Disconnected',
      };

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connectionActive = _status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting;
    final domain  = _appDomainCtrl.text.trim();
    final hours   = double.tryParse(_hoursCtrl.text.trim());
    final reason  = _reasonCtrl.text.trim();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text(
          'Time Extension — Debug Tool',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
            onPressed: _clearMessages,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Section 1: WSS Connection ────────────────────────────────────
            _SectionCard(
              icon: Icons.cable_rounded,
              iconColor: const Color(0xFF6C63FF),
              title: 'WSS Connection',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InputField(
                    controller: _childHashCtrl,
                    label: 'Child Hash',
                    hint: 'e.g. RGI3l1IbHya5t6YT',
                    enabled: !connectionActive,
                  ),
                  const SizedBox(height: 10),
                  // Live URL bar + status dot
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (_, __) => Opacity(
                            opacity: _status == ConnectionStatus.connecting
                                ? _pulseAnimation.value
                                : 1.0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _statusColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: _statusColor.withValues(alpha: 0.4),
                                    blurRadius: 5,
                                    spreadRadius: 1,
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _statusLabel,
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _wsUrl,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_wsError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _wsError!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: connectionActive
                            ? const Color(0xFF333355)
                            : const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: connectionActive ? _disconnect : _connect,
                      icon: Icon(connectionActive
                          ? Icons.link_off
                          : Icons.link_rounded),
                      label: Text(
                        _status == ConnectionStatus.connected
                            ? 'Disconnect'
                            : _status == ConnectionStatus.connecting
                                ? 'Connecting…'
                                : 'Connect',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Section 2: Parent Public Key ─────────────────────────────────
            _SectionCard(
              icon: Icons.key_rounded,
              iconColor: const Color(0xFFFFB300),
              title: 'Parent Public Key',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _parentPublicKey == null
                            ? Text(
                                _keyError ?? 'Not fetched yet',
                                style: TextStyle(
                                  color: _keyError != null
                                      ? Colors.redAccent
                                      : Colors.white38,
                                  fontSize: 11,
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'guardian_id: $_guardianId',
                                    style: const TextStyle(
                                      color: Color(0xFFFFB300),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Endpoint: $_baseApi/api/mobile/child/'
                                    '${_childHashCtrl.text.trim()}/guardian-public-key/',
                                    style: const TextStyle(
                                      color: Colors.white24,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A2215),
                            foregroundColor: const Color(0xFFFFB300),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _fetchingKey ? null : _fetchParentKey,
                          icon: _fetchingKey
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFB300),
                                  ),
                                )
                              : const Icon(Icons.download_rounded, size: 16),
                          label: const Text(
                            'Fetch Key',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_parentPublicKey != null) ...[
                    const SizedBox(height: 8),
                    _KeyDisplay(
                      label: 'RSA Public Key (PEM)',
                      value: _parentPublicKey!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Section 3: Payload to Send ────────────────────────────────────
            _SectionCard(
              icon: Icons.data_object,
              iconColor: const Color(0xFF00BFA5),
              title: 'Payload to Send',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _InputField(
                          controller: _appDomainCtrl,
                          label: 'App / Domain',
                          hint: 'youtube.com',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _InputField(
                          controller: _hoursCtrl,
                          label: 'Hours',
                          hint: '2.0',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _InputField(
                    controller: _reasonCtrl,
                    label: 'Reason (will be base64-encoded)',
                    hint: 'e.g. Need more time for homework',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  _LivePayload(
                    appDomain:  domain,
                    hours:      hours,
                    reason:     reason,
                    guardianId: _guardianId,
                    hasKey:     _parentPublicKey != null,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _status == ConnectionStatus.connected
                            ? const Color(0xFF00BFA5)
                            : const Color(0xFF2A2A2A),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white30,
                        disabledBackgroundColor: const Color(0xFF2A2A2A),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _status == ConnectionStatus.connected
                          ? _sendPayload
                          : null,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text(
                        'Send Request',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Section 4: Message Log ────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF12122A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2A4A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.terminal,
                              size: 15, color: Color(0xFF9E9EFF)),
                          const SizedBox(width: 7),
                          const Text(
                            'Message Log',
                            style: TextStyle(
                              color: Color(0xFF9E9EFF),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_messages.length} msg${_messages.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF2A2A4A), height: 1),
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(
                              child: Text(
                                'No messages yet.\nConnect then send a request.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(10),
                              itemCount: _messages.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) =>
                                  _MessageBubble(message: _messages[i]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section card wrapper ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color    iconColor;
  final String   title;
  final Widget   child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: iconColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Key display (copyable, collapsible) ───────────────────────────────────────

class _KeyDisplay extends StatefulWidget {
  const _KeyDisplay({required this.label, required this.value});
  final String label;
  final String value;

  @override
  State<_KeyDisplay> createState() => _KeyDisplayState();
}

class _KeyDisplayState extends State<_KeyDisplay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final display = _expanded
        ? widget.value
        : widget.value.length > 80
            ? '${widget.value.substring(0, 80)}…'
            : widget.value;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFFFFB300).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Key copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: const Icon(Icons.copy_rounded,
                    size: 14, color: Colors.white38),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            display,
            style: const TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 10,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live payload preview ──────────────────────────────────────────────────────

class _LivePayload extends StatelessWidget {
  const _LivePayload({
    required this.appDomain,
    required this.hours,
    required this.reason,
    required this.guardianId,
    required this.hasKey,
  });

  final String  appDomain;
  final double? hours;
  final String  reason;
  final int?    guardianId;
  final bool    hasKey;

  @override
  Widget build(BuildContext context) {
    final encrypted = reason.isEmpty
        ? '<reason will be encoded>'
        : 'base64("${reason.length > 20 ? reason.substring(0, 20) : reason}…")';

    final preview = {
      "type": "time_extension_request",
      "data": {
        "app_domain":        appDomain.isEmpty ? '<app_domain>'      : appDomain,
        "requested_hours":   hours             ?? '<requested_hours>',
        "message_encrypted": encrypted,
        "guardian_id":       guardianId        ?? '<guardian_id>',
      },
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF00BFA5).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.preview_rounded,
                  size: 12, color: Color(0xFF00BFA5)),
              const SizedBox(width: 5),
              const Text(
                'Live Payload Preview',
                style: TextStyle(
                    color: Color(0xFF00BFA5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (!hasKey)
                const Text(
                  '⚠ fetch key first',
                  style:
                      TextStyle(color: Color(0xFFFFB300), fontSize: 10),
                ),
              if (hasKey)
                const Text(
                  '✓ key obtained',
                  style: TextStyle(color: Color(0xFF4CAF50), fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            const JsonEncoder.withIndent('  ').convert(preview),
            style: const TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 10.5,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '* message_encrypted = base64(reason) for debug; RSA used in production',
            style: TextStyle(
                color: Colors.white24,
                fontSize: 9.5,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

// ── Reusable input field ──────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String                label;
  final String                hint;
  final bool                  enabled;
  final TextInputType         keyboardType;
  final int                   maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:   controller,
      enabled:      enabled,
      keyboardType: keyboardType,
      maxLines:     maxLines,
      style: const TextStyle(
          color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText:    label,
        hintText:     hint,
        labelStyle:   const TextStyle(color: Color(0xFF9E9EFF), fontSize: 12),
        hintStyle:    const TextStyle(color: Colors.white24, fontSize: 12),
        filled:       true,
        fillColor:    const Color(0xFF0F0F1A),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2A2A4A))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF2A2A4A))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF6C63FF))),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1A1A1A))),
      ),
    );
  }
}

// ── Message model ─────────────────────────────────────────────────────────────

enum _MessageType { sent, received, system }

class _Message {
  final String       content;
  final _MessageType type;
  final DateTime     timestamp;

  _Message.sent(this.content)
      : type      = _MessageType.sent,
        timestamp = DateTime.now();
  _Message.received(this.content)
      : type      = _MessageType.received,
        timestamp = DateTime.now();
  _Message.system(this.content)
      : type      = _MessageType.system,
        timestamp = DateTime.now();
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _Message message;

  @override
  Widget build(BuildContext context) {
    final (bg, border, label, labelColor, icon) = switch (message.type) {
      _MessageType.sent => (
          const Color(0xFF1E2E4A),
          const Color(0xFF6C63FF),
          'SENT',
          const Color(0xFF9E9EFF),
          Icons.arrow_upward_rounded,
        ),
      _MessageType.received => (
          const Color(0xFF1A2E2A),
          const Color(0xFF00BFA5),
          'RECEIVED',
          const Color(0xFF4DB6AC),
          Icons.arrow_downward_rounded,
        ),
      _MessageType.system => (
          const Color(0xFF1E1E1E),
          const Color(0xFF555555),
          'SYSTEM',
          const Color(0xFF9E9E9E),
          Icons.info_outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: labelColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                _fmt(message.timestamp),
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            message.content,
            style: const TextStyle(
              color: Color(0xFFCFD8DC),
              fontSize: 12,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}