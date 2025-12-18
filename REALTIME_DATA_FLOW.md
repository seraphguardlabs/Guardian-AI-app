# Real-Time WebSocket Data Flow

## Summary

Your Flutter app now sends **all monitoring data in real-time** via WebSocket, similar to how multiplayer games send player positions continuously.

---

## 📡 What Gets Sent in Real-Time

### 1. **Screen Time Data** (Every 10 seconds)
```json
{
  "type": "screen_time",
  "data": {
    "date": "2025-12-18",
    "total_screen_time": 7200,
    "app_wise_data": {
      "com.whatsapp": {
        "14": 1200,
        "15": 800
      },
      "com.youtube": {
        "14": 600
      },
      "com.instagram": {
        "15": 1800
      }
    }
  }
}
```

**Frequency:** Every 10 seconds  
**Contains:**
- Current date
- Total screen time in seconds
- Per-app breakdown by hour
- Updates continuously as child uses apps

---

### 2. **Location Data** (Every 30 seconds)
```json
{
  "type": "location",
  "data": {
    "timestamp": "2025-12-18T10:30:00Z",
    "latitude": 28.6139,
    "longitude": 77.2090
  }
}
```

**Frequency:** Every 30 seconds  
**Contains:**
- Current UTC timestamp
- GPS latitude coordinate
- GPS longitude coordinate
- Real-time tracking of child's movement

---

### 3. **Website Access Logs** (Every 15 seconds)
```json
{
  "type": "site_access",
  "data": {
    "logs": [
      {
        "timestamp": "2025-12-18T10:30:00Z",
        "url": "https://youtube.com",
        "accessed": true
      },
      {
        "timestamp": "2025-12-18T10:31:00Z",
        "url": "https://blocked-site.com",
        "accessed": false
      },
      {
        "timestamp": "2025-12-18T10:32:00Z",
        "url": "https://google.com",
        "accessed": true
      }
    ]
  }
}
```

**Frequency:** Every 15 seconds  
**Contains:**
- Array of recent website visits
- Timestamp of each visit
- Full URL accessed
- Whether access was allowed or blocked

---

## 🔄 Real-Time Update Cycle

```
Time    Screen Time    Location    Websites    Total Updates/Min
─────────────────────────────────────────────────────────────────
0:00    ✅ Send        ✅ Send     ✅ Send           3
0:10    ✅ Send        -           -                 1
0:15    -              -           ✅ Send           1
0:20    ✅ Send        -           -                 1
0:30    ✅ Send        ✅ Send     ✅ Send           3
0:40    ✅ Send        -           -                 1
0:45    -              -           ✅ Send           1
0:50    ✅ Send        -           -                 1
1:00    ✅ Send        ✅ Send     ✅ Send           3

Total: ~12 updates per minute
```

---

## 🎮 Multiplayer Game-Like Architecture

Just like multiplayer games send player positions constantly:

### **Game Example:**
```javascript
// Game sends player position every 100ms
setInterval(() => {
  websocket.send({
    type: 'player_position',
    x: player.x,
    y: player.y,
    rotation: player.rotation
  });
}, 100);
```

### **Your App:**
```dart
// App sends monitoring data every 10-30 seconds
Timer.periodic(Duration(seconds: 10), (timer) {
  websocket.sendScreenTime(
    date: currentDate,
    totalScreenTime: screenTime,
    appWiseData: appUsage
  );
});

Timer.periodic(Duration(seconds: 30), (timer) {
  websocket.sendLocation(
    timestamp: now,
    latitude: lat,
    longitude: lng
  );
});
```

**Key Similarity:** Continuous, automatic data streaming without user interaction.

---

## 📊 Data Volume Estimation

### Per Minute
- Screen time updates: **6** (every 10s)
- Location updates: **2** (every 30s)
- Website logs: **4** (every 15s)
- **Total: ~12 messages/minute**

### Per Hour
- Screen time updates: **360**
- Location updates: **120**
- Website logs: **240**
- **Total: ~720 messages/hour**

### Per Day (Active 12 hours)
- Screen time updates: **4,320**
- Location updates: **1,440**
- Website logs: **2,880**
- **Total: ~8,640 messages/day**

---

## 🔌 Connection Management

### WebSocket Connection
```
wss://seraphguardlabs.com/ws/ingest/{child_hash}/
```

### Connection Flow
```
1. App starts
   ↓
2. Connect to WebSocket with child_hash
   ↓
3. Server sends "connection_established"
   ↓
4. Start periodic data collection
   ↓
5. Send data automatically every 10-30s
   ↓
6. Receive "ack" for each message
   ↓
7. If connection lost → Buffer messages
   ↓
8. Auto-reconnect with exponential backoff
   ↓
9. If reconnect fails → Use HTTP fallback
```

---

## ✅ Server Acknowledgments

For every message sent, server responds:

```json
{
  "type": "ack",
  "message_type": "screen_time",
  "status": "success",
  "result": {
    "stored": true,
    "created": false,
    "date": "2025-12-18"
  }
}
```

This confirms:
- ✅ Message received
- ✅ Data validated
- ✅ Stored in database
- ✅ Ready for parent dashboard

---

## 🔐 What Child Hash Is Used For

The `child_hash` in the WebSocket URL identifies which child's data is being sent:

```dart
// When parent logs in and selects "John"
final childHash = "abc123def456"; // John's unique hash

// WebSocket connects with John's hash
await wsService.connect("abc123def456");

// All data is now associated with John
wsService.sendScreenTime(...); // ✅ Stored under John
wsService.sendLocation(...);    // ✅ Stored under John
wsService.sendSiteAccess(...);  // ✅ Stored under John
```

---

## 📱 How to Use in Your App

### 1. Initialize on Login
```dart
// In your login/child selection screen
final childHash = selectedChild.childHash;

// Start real-time collector
final collector = RealTimeDataCollector(
  webSocketService: context.read<WebSocketService>(),
  childHash: childHash,
);

await collector.start();
```

### 2. Monitor Status
```dart
// Show connection status in dashboard
Consumer<WebSocketService>(
  builder: (context, ws, _) {
    return Row(
      children: [
        Icon(
          ws.isConnected ? Icons.cloud_done : Icons.cloud_off,
          color: ws.isConnected ? Colors.green : Colors.red,
        ),
        Text(ws.isConnected ? 'Live' : 'Offline'),
      ],
    );
  },
)
```

### 3. Stop on Logout
```dart
// When logging out
collector.stop();
await wsService._disconnect();
```

---

## 🆚 WebSocket vs HTTP Comparison

### Traditional HTTP (Old Method)
```
❌ Send data every 15 minutes
❌ Large batch payload
❌ Delayed updates on dashboard
❌ Higher latency
✅ More reliable
```

### WebSocket (New Method)
```
✅ Send data every 10-30 seconds
✅ Small individual messages
✅ Instant updates on dashboard
✅ Lower latency
⚠️ Requires connection management
```

### Hybrid (Your Implementation)
```
✅ WebSocket for real-time (preferred)
✅ HTTP for fallback (reliability)
✅ Automatic switching
✅ Message buffering
✅ Best of both worlds
```

---

## 🎯 Real-Time Dashboard Updates

Parent's dashboard will show:

### Before (HTTP only)
```
Screen Time: 2 hours (updated 15 mins ago)
Location: Home (updated 15 mins ago)
Last Website: youtube.com (updated 15 mins ago)
```

### After (WebSocket)
```
Screen Time: 2 hours 3 mins (live) 🟢
Location: Moving to school (live) 🟢
Last Website: google.com (3 seconds ago) 🟢
```

**Everything updates in real-time** like watching a live stream of the child's device activity.

---

## 🚀 Quick Integration Checklist

- ✅ `web_socket_channel` dependency added
- ✅ WebSocketService created
- ✅ DataSyncService created
- ✅ Data models defined
- ✅ Real-time collector implemented
- ✅ Provider registered in main.dart
- ✅ HTTP fallback configured
- ✅ Auto-reconnection enabled
- ✅ Message buffering active

**Status: Ready to use! 🎉**

---

## 📝 Example Usage in Dashboard

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
    _startRealTimeMonitoring();
  }
  
  Future<void> _startRealTimeMonitoring() async {
    final prefsManager = context.read<PreferencesManager>();
    final childHash = prefsManager.getSelectedChildHash();
    
    if (childHash != null) {
      _collector = RealTimeDataCollector(
        webSocketService: context.read<WebSocketService>(),
        childHash: childHash,
      );
      
      await _collector!.start();
      print('🚀 Real-time monitoring started');
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
          // Connection indicator
          Consumer<WebSocketService>(
            builder: (context, ws, _) {
              return Padding(
                padding: EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Icon(
                      ws.isConnected ? Icons.wifi : Icons.wifi_off,
                      color: ws.isConnected ? Colors.green : Colors.grey,
                    ),
                    SizedBox(width: 4),
                    Text(
                      ws.isConnected ? 'LIVE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 12,
                        color: ws.isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Text('Data streaming in real-time...'),
      ),
    );
  }
}
```

---

## 🎉 You're All Set!

Your Flutter app now:
1. ✅ Connects to WebSocket on app start
2. ✅ Sends screen time every 10 seconds
3. ✅ Sends location every 30 seconds
4. ✅ Sends website logs every 15 seconds
5. ✅ Auto-reconnects if connection lost
6. ✅ Falls back to HTTP if needed
7. ✅ Buffers messages during disconnection
8. ✅ Shows connection status in UI

**Everything updates in real-time, just like multiplayer games! 🎮**
