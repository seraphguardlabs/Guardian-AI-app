# WebSocket Integration Guide - Flutter App

## Overview

The Guardian AI Flutter app now supports **real-time data synchronization** via WebSocket connections, with automatic HTTP fallback for reliability. Data is sent instantly as it's collected, similar to multiplayer games.

## Architecture

```
┌─────────────────────┐
│   Flutter App       │
│                     │
│  ┌──────────────┐   │
│  │ DataSyncService│◄─── Unified interface
│  └───────┬──────┘   │
│          │          │
│    ┌─────▼────┐     │
│    │WebSocket │     │ ◄─── Preferred (real-time)
│    │Service   │     │
│    └──────────┘     │
│          │          │
│    ┌─────▼────┐     │
│    │   HTTP   │     │ ◄─── Fallback (reliable)
│    │ Service  │     │
│    └──────────┘     │
└─────────────────────┘
         │
         ▼
  wss://seraphguardlabs.com
```

## Installation

### 1. Dependencies Added

Already added to `pubspec.yaml`:
```yaml
dependencies:
  web_socket_channel: ^3.0.1
```

Run to install:
```bash
flutter pub get
```

### 2. Files Created

- `lib/services/websocket_service.dart` - WebSocket connection management
- `lib/services/data_sync_service.dart` - Unified sync service (WebSocket + HTTP)
- `lib/models/websocket_data.dart` - Data models for messages
- `lib/utils/websocket_example.dart` - Usage examples

## Quick Start

### Basic Usage

```dart
import 'package:provider/provider.dart';
import 'services/websocket_service.dart';

// 1. Get the service from provider
final wsService = context.read<WebSocketService>();

// 2. Connect with child hash
await wsService.connect('YOUR_CHILD_HASH');

// 3. Send data in real-time
await wsService.sendScreenTime(
  date: '2025-12-18',
  totalScreenTime: 3600,
  appWiseData: {
    'com.whatsapp': {'14': 1200, '15': 800},
  },
);

await wsService.sendLocation(
  timestamp: DateTime.now().toUtc().toIso8601String(),
  latitude: 28.6139,
  longitude: 77.2090,
);

await wsService.sendSiteAccess(
  logs: [
    {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'url': 'https://example.com',
      'accessed': true,
    },
  ],
);
```

### Using DataSyncService (Recommended)

The `DataSyncService` automatically handles WebSocket with HTTP fallback:

```dart
import 'package:provider/provider.dart';
import 'services/data_sync_service.dart';
import 'models/websocket_data.dart';

// Get the service
final dataSyncService = DataSyncService(
  webSocketService: context.read<WebSocketService>(),
  apiService: context.read<ApiService>(),
);

// Initialize with child hash
await dataSyncService.initialize('YOUR_CHILD_HASH');

// Send data - automatically uses WebSocket or falls back to HTTP
await dataSyncService.sendScreenTime(
  date: '2025-12-18',
  totalScreenTime: 7200,
  appWiseData: {'com.app': {'14': 3600}},
);

// Check connection status
if (dataSyncService.isConnected) {
  print('Connected via WebSocket');
} else {
  print('Using HTTP fallback');
}
```

## Features

### 1. **Automatic Reconnection**
- Exponential backoff (1s, 2s, 4s, 8s, 16s)
- Max 5 retry attempts before HTTP fallback
- Maintains connection during app lifecycle

### 2. **Message Buffering**
- Messages buffered when disconnected
- Auto-sent when connection restored
- Prevents data loss

### 3. **Heartbeat/Ping**
- Sends ping every 30 seconds
- Detects dead connections
- Auto-reconnects if needed

### 4. **HTTP Fallback**
- Automatic switch to HTTP if WebSocket fails
- Maintains data flow reliability
- Seamless user experience

### 5. **Status Monitoring**
- Real-time connection status
- Buffered message count
- Error notifications

## Connection States

```dart
enum WebSocketStatus {
  disconnected,  // Not connected
  connecting,    // Initial connection attempt
  connected,     // Active WebSocket connection
  reconnecting,  // Attempting to reconnect
  failed,        // Connection failed, using HTTP
}
```

## Listening to Status Changes

```dart
class MyWidget extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(
      builder: (context, wsService, child) {
        return Column(
          children: [
            Text('Status: ${wsService.status.name}'),
            Text('Buffered: ${wsService.bufferedMessageCount}'),
            if (wsService.isConnected)
              Icon(Icons.cloud_done, color: Colors.green)
            else
              Icon(Icons.cloud_off, color: Colors.red),
          ],
        );
      },
    );
  }
}
```

## Data Models

### Screen Time
```dart
ScreenTimeData(
  date: '2025-12-18',
  totalScreenTime: 7200, // seconds
  appWiseData: {
    'com.whatsapp': {
      '09': 1200,  // hour -> seconds
      '10': 800,
    },
  },
)
```

### Location
```dart
LocationData(
  timestamp: '2025-12-18T10:30:00Z',
  latitude: 28.6139,
  longitude: 77.2090,
)
```

### Site Access
```dart
SiteAccessLog(
  timestamp: '2025-12-18T10:30:00Z',
  url: 'https://example.com',
  accessed: true, // false if blocked
)
```

## Real-Time Usage Pattern

### Continuous Data Streaming

```dart
// In your app monitoring service
class AppMonitoringService {
  final WebSocketService _wsService;
  Timer? _syncTimer;
  
  void startRealTimeSync(String childHash) {
    _wsService.connect(childHash);
    
    // Send data every 5 seconds (real-time)
    _syncTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _collectAndSendData();
    });
  }
  
  Future<void> _collectAndSendData() async {
    // Collect current screen time
    final screenTimeData = await _getScreenTimeData();
    await _wsService.sendScreenTime(
      date: screenTimeData.date,
      totalScreenTime: screenTimeData.totalScreenTime,
      appWiseData: screenTimeData.appWiseData,
    );
    
    // Collect current location
    final location = await _getLocation();
    if (location != null) {
      await _wsService.sendLocation(
        timestamp: DateTime.now().toUtc().toIso8601String(),
        latitude: location.latitude,
        longitude: location.longitude,
      );
    }
    
    // Collect website visits
    final sites = await _getRecentWebsiteVisits();
    if (sites.isNotEmpty) {
      await _wsService.sendSiteAccess(logs: sites);
    }
  }
}
```

## Error Handling

```dart
try {
  final success = await wsService.sendScreenTime(...);
  
  if (!success) {
    // Message was buffered, will retry later
    print('Message buffered for later');
  }
} catch (e) {
  // Handle error
  print('Error sending data: $e');
}
```

## Best Practices

### 1. **Initialize Early**
```dart
// In your app's initialization
void initState() {
  super.initState();
  final childHash = prefsManager.getSelectedChildHash();
  if (childHash != null) {
    context.read<WebSocketService>().connect(childHash);
  }
}
```

### 2. **Clean Up**
```dart
@override
void dispose() {
  // WebSocketService handles cleanup automatically
  super.dispose();
}
```

### 3. **Monitor Connection**
```dart
// Show connection indicator in UI
Widget _buildConnectionIndicator() {
  return Consumer<WebSocketService>(
    builder: (context, ws, _) {
      return Row(
        children: [
          Icon(
            ws.isConnected ? Icons.wifi : Icons.wifi_off,
            color: ws.isConnected ? Colors.green : Colors.grey,
          ),
          Text(ws.status.name),
        ],
      );
    },
  );
}
```

### 4. **Batch Data Efficiently**
```dart
// Instead of sending many small messages
for (var site in websites) {
  await wsService.sendSiteAccess(logs: [site]); // ❌ Inefficient
}

// Send in batches
await wsService.sendSiteAccess(logs: websites); // ✅ Better
```

## Testing

### Test WebSocket Connection
```dart
// In debug mode
void testConnection() async {
  final wsService = context.read<WebSocketService>();
  
  await wsService.connect('test_child_hash');
  
  // Wait for connection
  await Future.delayed(Duration(seconds: 2));
  
  // Send test data
  await wsService.sendLocation(
    timestamp: DateTime.now().toUtc().toIso8601String(),
    latitude: 0.0,
    longitude: 0.0,
  );
  
  print('Connection status: ${wsService.status}');
  print('Buffered messages: ${wsService.bufferedMessageCount}');
}
```

## Troubleshooting

### Connection Failed
```
❌ WebSocket: Connection failed
```
**Solution:** Check network, verify child hash, ensure server is running

### Messages Buffered
```
💾 WebSocket: Message buffered (5 total)
```
**Solution:** Normal when disconnected, will auto-send on reconnect

### Max Reconnection Attempts
```
❌ WebSocket: Max reconnection attempts reached
```
**Solution:** App will use HTTP fallback automatically

## Production Checklist

- ✅ WebSocket URL uses `wss://` (secure)
- ✅ Child hash validated before connecting
- ✅ Error handling in place
- ✅ HTTP fallback configured
- ✅ Connection status shown in UI
- ✅ Data buffering enabled
- ✅ Heartbeat mechanism active

## WebSocket vs HTTP Comparison

| Feature | WebSocket | HTTP |
|---------|-----------|------|
| **Speed** | ⚡ Instant | ⏱️ Request/Response |
| **Real-time** | ✅ Yes | ❌ No |
| **Reliability** | ⚠️ Can disconnect | ✅ Stable |
| **Data sync** | 🔄 Continuous | 📦 Batch |
| **Battery** | 🔋 Efficient | 🔋 More drain |

## Summary

Your Flutter app now has:
1. ✅ Real-time WebSocket connection
2. ✅ Automatic HTTP fallback
3. ✅ Message buffering and retry
4. ✅ Connection status monitoring
5. ✅ Auto-reconnection with exponential backoff
6. ✅ Heartbeat mechanism
7. ✅ Comprehensive data models

Everything is ready to use! Just connect with your child hash and start sending data in real-time.
