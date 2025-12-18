import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../services/data_sync_service.dart';
import '../models/websocket_data.dart';

/// Example widget showing how to use WebSocket and DataSync services
class WebSocketExample extends StatefulWidget {
  const WebSocketExample({super.key});

  @override
  State<WebSocketExample> createState() => _WebSocketExampleState();
}

class _WebSocketExampleState extends State<WebSocketExample> {
  @override
  void initState() {
    super.initState();
    _initializeWebSocket();
  }

  Future<void> _initializeWebSocket() async {
    // Get the child hash from your preferences or state
    const childHash = 'YOUR_CHILD_HASH_HERE';
    
    // Get WebSocket service from provider
    final wsService = context.read<WebSocketService>();
    
    // Connect to WebSocket
    await wsService.connect(childHash);
    
    // Listen to incoming messages
    wsService.messages.listen((message) {
      debugPrint('📨 Received message: ${message['type']}');
      
      // Handle different message types
      switch (message['type']) {
        case 'connection_established':
          debugPrint('✅ Connected to server');
          break;
        case 'ack':
          debugPrint('✅ Server acknowledged: ${message['message_type']}');
          break;
        case 'error':
          debugPrint('❌ Server error: ${message['message']}');
          break;
      }
    });
  }

  Future<void> _sendScreenTimeExample() async {
    final wsService = context.read<WebSocketService>();
    
    // Example: Send screen time data
    await wsService.sendScreenTime(
      date: DateTime.now().toIso8601String().split('T')[0],
      totalScreenTime: 7200, // 2 hours in seconds
      appWiseData: {
        'com.whatsapp': {'09': 1200, '10': 800},
        'com.youtube': {'09': 600},
      },
    );
  }

  Future<void> _sendLocationExample() async {
    final wsService = context.read<WebSocketService>();
    
    // Example: Send location data
    await wsService.sendLocation(
      timestamp: DateTime.now().toUtc().toIso8601String(),
      latitude: 28.6139,
      longitude: 77.2090,
    );
  }

  Future<void> _sendSiteAccessExample() async {
    final wsService = context.read<WebSocketService>();
    
    // Example: Send website access logs
    await wsService.sendSiteAccess(
      logs: [
        {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'url': 'https://example.com',
          'accessed': true,
        },
        {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'url': 'https://blocked-site.com',
          'accessed': false,
        },
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebSocket Example'),
      ),
      body: Consumer<WebSocketService>(
        builder: (context, wsService, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection Status
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connection Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              wsService.isConnected
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: wsService.isConnected
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              wsService.status.name.toUpperCase(),
                              style: TextStyle(
                                color: wsService.isConnected
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (wsService.bufferedMessageCount > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Buffered Messages: ${wsService.bufferedMessageCount}',
                            style: const TextStyle(color: Colors.orange),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Send Data Buttons
                ElevatedButton.icon(
                  onPressed: _sendScreenTimeExample,
                  icon: const Icon(Icons.phone_android),
                  label: const Text('Send Screen Time'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _sendLocationExample,
                  icon: const Icon(Icons.location_on),
                  label: const Text('Send Location'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _sendSiteAccessExample,
                  icon: const Icon(Icons.web),
                  label: const Text('Send Site Access'),
                ),
                const SizedBox(height: 16),

                // Retry Connection
                if (!wsService.isConnected)
                  ElevatedButton.icon(
                    onPressed: () => wsService.retry(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Connection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
