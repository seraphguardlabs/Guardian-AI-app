import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Extension Request',
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

// ── Connection state ─────────────────────────────────────────────────────────

enum ConnectionStatus { disconnected, connecting, connected, error }

// ── Main screen ───────────────────────────────────────────────────────────────

class WebSocketScreen extends StatefulWidget {
  const WebSocketScreen({super.key});

  @override
  State<WebSocketScreen> createState() => _WebSocketScreenState();
}

class _WebSocketScreenState extends State<WebSocketScreen>
    with SingleTickerProviderStateMixin {
  static const String _wsBase = 'ws://seraphguardlabs.com/ws/child/';
  static const String _wsPath = '/time-extension/';

  // Input controllers – child hash drives the URL; others drive the payload
  final TextEditingController _childHashCtrl  = TextEditingController();
  final TextEditingController _appDomainCtrl  = TextEditingController();
  final TextEditingController _hoursCtrl      = TextEditingController();
  final TextEditingController _guardianIdCtrl = TextEditingController();

  /// Full WebSocket URL built from the child-hash field
  String get _wsUrl => '$_wsBase${_childHashCtrl.text.trim()}$_wsPath';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _errorMessage;

  final List<_Message> _messages = [];
  final ScrollController _scrollController = ScrollController();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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
    // Rebuild UI on every keystroke so payload preview stays live
    _childHashCtrl.addListener(_rebuild);
    _appDomainCtrl.addListener(_rebuild);
    _hoursCtrl.addListener(_rebuild);
    _guardianIdCtrl.addListener(_rebuild);
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
    _guardianIdCtrl.dispose();
    super.dispose();
  }

  // ── WebSocket helpers ────────────────────────────────────────────────────

  void _connect() {
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      return;
    }

    if (_childHashCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the Child Hash before connecting.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _status = ConnectionStatus.connecting;
      _errorMessage = null;
    });

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      _channel!.ready.then((_) {
        if (mounted) {
          setState(() => _status = ConnectionStatus.connected);
          _addMessage(_Message.system('Connected to server'));
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _status = ConnectionStatus.error;
            _errorMessage = e.toString();
          });
          _addMessage(_Message.system('Connection failed: $e'));
        }
      });

      _subscription = _channel!.stream.listen(
        (data) {
          _addMessage(_Message.received(data.toString()));
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _status = ConnectionStatus.error;
              _errorMessage = error.toString();
            });
            _addMessage(_Message.system('Error: $error'));
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
        _status = ConnectionStatus.error;
        _errorMessage = e.toString();
      });
      _addMessage(_Message.system('Exception: $e'));
    }
  }

  void _disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _subscription = null;
    if (mounted) {
      setState(() => _status = ConnectionStatus.disconnected);
      _addMessage(_Message.system('Disconnected'));
    }
  }

  void _sendPayload() {
    if (_status != ConnectionStatus.connected || _channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not connected. Please connect first.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final domain     = _appDomainCtrl.text.trim();
    final hours       = int.tryParse(_hoursCtrl.text.trim());
    final guardianId  = int.tryParse(_guardianIdCtrl.text.trim());

    if (domain.isEmpty || hours == null || guardianId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Fill in App Domain, Requested Hours, and Guardian ID.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final payload = {
      "type": "time_extension_request",
      "data": {
        "app_domain": domain,
        "requested_hours": hours,
        "message_encrypted": "base64_encrypted_message_here",
        "guardian_id": guardianId,
      },
    };

    final prettyJson = const JsonEncoder.withIndent('  ').convert(payload);
    _channel!.sink.add(jsonEncode(payload));
    _addMessage(_Message.sent(prettyJson));
  }

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

  // ── Helpers ──────────────────────────────────────────────────────────────

  Color get _statusColor => switch (_status) {
        ConnectionStatus.connected => const Color(0xFF4CAF50),
        ConnectionStatus.connecting => const Color(0xFFFFB300),
        ConnectionStatus.error => const Color(0xFFF44336),
        ConnectionStatus.disconnected => const Color(0xFF9E9E9E),
      };

  String get _statusLabel => switch (_status) {
        ConnectionStatus.connected => 'Connected',
        ConnectionStatus.connecting => 'Connecting…',
        ConnectionStatus.error => 'Error',
        ConnectionStatus.disconnected => 'Disconnected',
      };

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text(
          'Time Extension Request',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear messages',
            icon:
                const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
            onPressed: _clearMessages,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Input fields
            _InputsCard(
              childHashCtrl:  _childHashCtrl,
              appDomainCtrl:  _appDomainCtrl,
              hoursCtrl:      _hoursCtrl,
              guardianIdCtrl: _guardianIdCtrl,
              connectionActive: _status == ConnectionStatus.connected ||
                  _status == ConnectionStatus.connecting,
            ),
            const SizedBox(height: 16),

            // Status card
            _StatusCard(
              status: _status,
              statusColor: _statusColor,
              statusLabel: _statusLabel,
              wsUrl: _wsUrl,
              errorMessage: _errorMessage,
              pulseAnimation: _pulseAnimation,
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _status == ConnectionStatus.connected
                              ? const Color(0xFF333355)
                              : const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _status == ConnectionStatus.connected ||
                            _status == ConnectionStatus.connecting
                        ? _disconnect
                        : _connect,
                    icon: Icon(
                      _status == ConnectionStatus.connected
                          ? Icons.link_off
                          : Icons.link,
                    ),
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
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _status == ConnectionStatus.connected
                              ? const Color(0xFF00BFA5)
                              : const Color(0xFF2A2A2A),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                      disabledBackgroundColor: const Color(0xFF2A2A2A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
            const SizedBox(height: 16),

            // Payload preview – updates live as user types
            _PayloadPreview(
              appDomain:     _appDomainCtrl.text.trim(),
              requestedHours: int.tryParse(_hoursCtrl.text.trim()),
              guardianId:    int.tryParse(_guardianIdCtrl.text.trim()),
            ),
            const SizedBox(height: 16),

            // Message log
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF12122A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2A2A4A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.terminal,
                              size: 16, color: Color(0xFF9E9EFF)),
                          const SizedBox(width: 8),
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
                                'No messages yet.\nConnect and send a request.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _messages.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) =>
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

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.statusColor,
    required this.statusLabel,
    required this.wsUrl,
    required this.errorMessage,
    required this.pulseAnimation,
  });

  final ConnectionStatus status;
  final Color statusColor;
  final String statusLabel;
  final String wsUrl;
  final String? errorMessage;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: pulseAnimation,
                builder: (context, child) => Opacity(
                  opacity: status == ConnectionStatus.connecting
                      ? pulseAnimation.value
                      : 1.0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            wsUrl,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Payload preview ───────────────────────────────────────────────────────────

class _PayloadPreview extends StatelessWidget {
  final String appDomain;
  final int? requestedHours;
  final int? guardianId;

  const _PayloadPreview({
    required this.appDomain,
    required this.requestedHours,
    required this.guardianId,
  });

  @override
  Widget build(BuildContext context) {
    final livePayload = {
      "type": "time_extension_request",
      "data": {
        "app_domain":        appDomain.isEmpty      ? '<app_domain>'       : appDomain,
        "requested_hours":  requestedHours         ?? '<requested_hours>',
        "message_encrypted": "base64_encrypted_message_here",
        "guardian_id":      guardianId             ?? '<guardian_id>',
      },
    };
    final pretty = const JsonEncoder.withIndent('  ').convert(livePayload);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.data_object, size: 15, color: Color(0xFFFFB300)),
              SizedBox(width: 6),
              Text(
                'Payload Preview',
                style: TextStyle(
                  color: Color(0xFFFFB300),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pretty,
            style: const TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 11.5,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inputs card ───────────────────────────────────────────────────────────────

class _InputsCard extends StatelessWidget {
  const _InputsCard({
    required this.childHashCtrl,
    required this.appDomainCtrl,
    required this.hoursCtrl,
    required this.guardianIdCtrl,
    required this.connectionActive,
  });

  final TextEditingController childHashCtrl;
  final TextEditingController appDomainCtrl;
  final TextEditingController hoursCtrl;
  final TextEditingController guardianIdCtrl;
  /// When true, child hash field is locked (connection is live)
  final bool connectionActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, size: 15, color: Color(0xFF9E9EFF)),
              SizedBox(width: 6),
              Text(
                'Request Parameters',
                style: TextStyle(
                  color: Color(0xFF9E9EFF),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Child hash — locked while connected
          _field(
            controller: childHashCtrl,
            label: 'Child Hash',
            hint: 'e.g. RGI3l1IbHya5t6YT',
            enabled: !connectionActive,
            prefixText: 'child/',
          ),
          const SizedBox(height: 10),
          // App domain + hours on one row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _field(
                  controller: appDomainCtrl,
                  label: 'App Domain',
                  hint: 'e.g. youtube.com',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _field(
                  controller: hoursCtrl,
                  label: 'Requested Hours',
                  hint: '2',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _field(
            controller: guardianIdCtrl,
            label: 'Guardian ID',
            hint: 'e.g. 4',
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool enabled = true,
    String? prefixText,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        prefixStyle: const TextStyle(color: Colors.white38, fontSize: 11),
        labelStyle: const TextStyle(color: Color(0xFF9E9EFF), fontSize: 12),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0F0F1A),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6C63FF)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1A1A1A)),
        ),
      ),
    );
  }
}

// ── Message model ─────────────────────────────────────────────────────────────

enum _MessageType { sent, received, system }

class _Message {
  final String content;
  final _MessageType type;
  final DateTime timestamp;

  _Message.sent(this.content)
      : type = _MessageType.sent,
        timestamp = DateTime.now();
  _Message.received(this.content)
      : type = _MessageType.received,
        timestamp = DateTime.now();
  _Message.system(this.content)
      : type = _MessageType.system,
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
                style:
                    const TextStyle(color: Colors.white24, fontSize: 10),
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
