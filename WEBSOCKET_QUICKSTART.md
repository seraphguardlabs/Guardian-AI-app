# 🚀 WebSocket Quick Start - 60 Second Guide

## 1️⃣ Connect (2 lines of code)
```dart
final wsService = context.read<WebSocketService>();
await wsService.connect('YOUR_CHILD_HASH');
```

## 2️⃣ Send Screen Time
```dart
await wsService.sendScreenTime(
  date: '2025-12-18',
  totalScreenTime: 3600,
  appWiseData: {
    'com.whatsapp': {'14': 1200},
  },
);
```

## 3️⃣ Send Location
```dart
await wsService.sendLocation(
  timestamp: DateTime.now().toUtc().toIso8601String(),
  latitude: 28.6139,
  longitude: 77.2090,
);
```

## 4️⃣ Send Website Access
```dart
await wsService.sendSiteAccess(
  logs: [
    {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'url': 'https://example.com',
      'accessed': true,
    }
  ],
);
```

## 5️⃣ Monitor Status
```dart
Consumer<WebSocketService>(
  builder: (context, ws, _) {
    return Text(ws.isConnected ? '🟢 LIVE' : '🔴 OFFLINE');
  },
)
```

---

## ⚡ Auto Mode (Even Easier!)

```dart
// Start automatic real-time collection
final collector = RealTimeDataCollector(
  webSocketService: context.read<WebSocketService>(),
  childHash: 'YOUR_CHILD_HASH',
);

await collector.start();
// Done! Data sends automatically every 10-30 seconds
```

---

## 📊 What Gets Sent

| Data Type | Frequency | Info |
|-----------|-----------|------|
| Screen Time | 10s | Total time + app breakdown |
| Location | 30s | GPS coordinates |
| Websites | 15s | Visited URLs + blocked status |

---

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| Not connecting | Check child hash |
| Messages buffered | Normal when offline, auto-sends later |
| Connection failed | HTTP fallback activates automatically |

---

## 📱 Complete Integration Example

```dart
class DashboardScreen extends StatefulWidget {
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  RealTimeDataCollector? _collector;
  
  @override
  void initState() {
    super.initState();
    _startRealTime();
  }
  
  void _startRealTime() async {
    final childHash = context.read<PreferencesManager>().getSelectedChildHash();
    if (childHash != null) {
      _collector = RealTimeDataCollector(
        webSocketService: context.read<WebSocketService>(),
        childHash: childHash,
      );
      await _collector!.start();
    }
  }
  
  @override
  void dispose() {
    _collector?.stop();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard'),
        actions: [
          Consumer<WebSocketService>(
            builder: (context, ws, _) => Icon(
              ws.isConnected ? Icons.wifi : Icons.wifi_off,
              color: ws.isConnected ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
      body: Center(child: Text('Real-time monitoring active')),
    );
  }
}
```

---

## ✅ That's It!

Your app now sends all data in real-time via WebSocket!

**Need more details?** See:
- `WEBSOCKET_FLUTTER_GUIDE.md` - Complete guide
- `REALTIME_DATA_FLOW.md` - What gets sent
- `WEBSOCKET_INTEGRATION_SUMMARY.md` - Full summary
