import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:usage_stats/usage_stats.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../utils/preferences_manager.dart';
import '../utils/app_theme.dart';
import '../services/location_service.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../services/app_blocker_service.dart';
import '../services/background_monitoring_service.dart';
import '../services/time_extension_service.dart';
import '../models/restrictions_data.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  static const platform = MethodChannel('com.guardian_ai/screen_time');
  static const browserChannel = MethodChannel('com.guardian_ai/browser_history');
  String _screenTime = 'Unknown';
  bool _loading = true;
  List<UsageInfo> _usageStats = [];
  Map<String, AppInfo> _apps = {};
  List<Map<String, String>> _browserHistory = [];
  Timer? _refreshTimer;
  RestrictionsData? _restrictions;
  StreamSubscription<Map<String, dynamic>>? _wsMessageSubscription;
  Position? _lastSentPosition;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entranceFade = CurvedAnimation(parent: _entranceController, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic));
    
    // Start background monitoring service
    BackgroundMonitoringService.start();
    
    _refreshData();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshData();
    });
    
    // Start location tracking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.startTracking();
      
      // Initialize WebSocket connection
      _initializeWebSocket();
      
      // Fetch restrictions
      _fetchRestrictions();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsMessageSubscription?.cancel();
    _entranceController.dispose();
    // Stop location tracking
    final locationService = Provider.of<LocationService>(context, listen: false);
    locationService.stopTracking();
    super.dispose();
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _getScreenTime(),
      _initUsageStats(),
      _getBrowserHistory(),
    ]);
    
    // Animate entrance after first data load
    if (!_entranceController.isCompleted) {
      _entranceController.forward();
    }
    
    // Send data via WebSocket after collecting
    _sendDataViaWebSocket();
  }
  
  Future<void> _initializeWebSocket() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();
    
    if (childHash != null && childHash.isNotEmpty) {
      final wsService = Provider.of<WebSocketService>(context, listen: false);
      await wsService.connect(childHash);
      debugPrint('= WebSocket connected for child: $childHash');
      
      // Listen for incoming messages from server
      _wsMessageSubscription = wsService.messages.listen((message) {
        if (message['type'] == 'restrictions_update') {
          debugPrint('=ܽ Received restrictions update via WebSocket');
          _fetchRestrictions();
        }
      });
      
    } else {
      debugPrint('Gn+ No child hash found, skipping WebSocket connection');
    }
  }
  
  Future<void> _fetchRestrictions() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();
    
    if (childHash == null || childHash.isEmpty) {
      debugPrint('Gn+ No child hash, skipping restrictions fetch');
      return;
    }
    
    final apiService = Provider.of<ApiService>(context, listen: false);
    // Use the mobile restricted-apps endpoint so this screen sees the same
    // app limits configured in the Block Sites & Apps screen.
    final result = await apiService.getAppRestrictions(
      email: prefsManager.getParentEmail() ?? '',
      password: prefsManager.getParentPassword() ?? '',
      childHash: childHash,
    );
    
    if (result['success'] == true && mounted) {
      final data = result['data'] as Map<String, dynamic>;
      final rawRestricted = data['restricted_apps'] as Map<String, dynamic>? ?? {};
      final restrictions = RestrictionsData.fromJson(rawRestricted);
      setState(() {
        _restrictions = restrictions;
      });
      debugPrint('G Restrictions updated: ${_restrictions!.restrictedApps.length} apps');
      
      // Update app blocker service
      final appBlocker = Provider.of<AppBlockerService>(context, listen: false);
      appBlocker.updateRestrictions(_restrictions!.restrictedApps);
      
      // Update background monitoring service
      BackgroundMonitoringService.updateRestrictions(_restrictions!.restrictedApps);
    }
  }
  
  Future<void> _sendDataViaWebSocket() async {
    final wsService = Provider.of<WebSocketService>(context, listen: false);
    
    if (!wsService.isConnected) {
      debugPrint('Gn+ WebSocket not connected, skipping data send');
      return;
    }
    
    // Send screen time data
    await _sendScreenTimeData();
    
    // Send location data
    await _sendLocationData();
    
    // Send website access data
    await _sendWebsiteData();
  }
  
  Future<void> _sendScreenTimeData() async {
    if (_usageStats.isEmpty) return;
    
    final wsService = Provider.of<WebSocketService>(context, listen: false);
    
    // Calculate total screen time in seconds
    int totalSeconds = 0;
    final appWiseData = <String, Map<String, int>>{};
    
    for (var usage in _usageStats) {
      final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
      final seconds = millis ~/ 1000;
      totalSeconds += seconds;
      
      // Get current hour for hourly breakdown
      final hour = DateTime.now().hour.toString().padLeft(2, '0');
      
      final packageName = usage.packageName ?? 'unknown';
      appWiseData[packageName] = {hour: seconds};
    }
    
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    await wsService.sendScreenTime(
      date: dateStr,
      totalScreenTime: totalSeconds,
      appWiseData: appWiseData,
    );
    
    debugPrint('= Sent screen time: ${totalSeconds}s, ${appWiseData.length} apps');
  }
  
  Future<void> _sendLocationData() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    final currentPosition = locationService.currentPosition;
    if (currentPosition != null) {
      // Check if we have moved at least 5 meters since last update
      if (_lastSentPosition != null) {
        double distance = Geolocator.distanceBetween(
          _lastSentPosition!.latitude,
          _lastSentPosition!.longitude,
          currentPosition.latitude,
          currentPosition.longitude,
        );

        if (distance < 5.0) {
          debugPrint('= (Old) Location update skipped: Only moved ${distance.toStringAsFixed(2)}m');
          return;
        }
      }

      await wsService.sendLocation(
        timestamp: DateTime.now().toUtc().toIso8601String(),
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
      );

      _lastSentPosition = currentPosition;
      debugPrint('= (Old) Sent location: ${currentPosition.latitude}, ${currentPosition.longitude}');
    }
  }
  
  Future<void> _sendWebsiteData() async {
    if (_browserHistory.isEmpty) return;
    
    final wsService = Provider.of<WebSocketService>(context, listen: false);
    
    final logs = _browserHistory.map((entry) {
      return {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'url': entry['url'] ?? '',
        'accessed': true,
      };
    }).toList();
    
    await wsService.sendSiteAccess(logs: logs);
    
    debugPrint('= Sent ${logs.length} website visits');
  }

  Future<void> _getScreenTime() async {
    String screenTime;
    try {
      final String result = await platform.invokeMethod('getScreenTime');
      screenTime = result;
    } on PlatformException catch (e) {
      screenTime = "Failed to get screen time: '${e.message}'.";
    }

    if (!mounted) return;

    setState(() {
      _screenTime = screenTime;
      _loading = false;
    });
  }

  Future<void> _initUsageStats() async {
    try {
      // Check if permission is granted
      bool? isPermissionGranted = await UsageStats.checkUsagePermission();
      if (isPermissionGranted == null || !isPermissionGranted) {
        await UsageStats.grantUsagePermission();
        // Check again after user comes back
        isPermissionGranted = await UsageStats.checkUsagePermission();
        if (isPermissionGranted == null || !isPermissionGranted) {
          if (mounted) {
            setState(() {
              _loading = false;
            });
          }
          return;
        }
      }

      // Get installed apps for names and icons
      List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: true, withIcon: true);
      
      Map<String, AppInfo> appMap = {
        for (var app in apps) app.packageName: app
      };

      // Query usage stats for today
      DateTime now = DateTime.now();
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = now;

      List<UsageInfo> usageStats = await UsageStats.queryUsageStats(
        startOfDay,
        endOfDay,
      );

      // Filter out apps with 0 usage and sort by time
      usageStats = usageStats
          .where((info) => 
              double.parse(info.totalTimeInForeground ?? '0') > 0 &&
              appMap.containsKey(info.packageName))
          .toList();
      
      usageStats.sort((a, b) {
        double timeA = double.parse(a.totalTimeInForeground ?? '0');
        double timeB = double.parse(b.totalTimeInForeground ?? '0');
        return timeB.compareTo(timeA);
      });

      if (mounted) {
        setState(() {
          _usageStats = usageStats;
          _apps = appMap;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching usage stats: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatDuration(String? timeInMillisStr) {
    if (timeInMillisStr == null) return '0m';
    int millis = int.tryParse(timeInMillisStr) ?? 0;
    Duration duration = Duration(milliseconds: millis);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String get _totalUsageTime {
    if (_usageStats.isEmpty) return '0m';
    int totalMillis = 0;
    for (var usage in _usageStats) {
      totalMillis += int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
    }
    return _formatDuration(totalMillis.toString());
  }

  bool _isBrowserApp(String packageName, String appName) {
    final browserKeywords = [
      'browser', 'chrome', 'firefox', 'opera', 'edge', 'safari', 'brave',
      'duck', 'samsung internet', 'uc browser', 'dolphin', 'maxthon',
      'puffin', 'kiwi', 'vivaldi', 'tor', 'duckduckgo'
    ];
    final lowerPackage = packageName.toLowerCase();
    final lowerName = appName.toLowerCase();
    return browserKeywords.any((keyword) => 
      lowerPackage.contains(keyword) || lowerName.contains(keyword)
    );
  }

  List<UsageInfo> get _browserUsageStats {
    return _usageStats.where((usage) {
      final app = _apps[usage.packageName];
      if (app == null) return false;
      return _isBrowserApp(usage.packageName ?? '', app.name);
    }).toList();
  }

  String get _totalBrowserTime {
    if (_browserUsageStats.isEmpty) return '0m';
    int totalMillis = 0;
    for (var usage in _browserUsageStats) {
      totalMillis += int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
    }
    return _formatDuration(totalMillis.toString());
  }

  Future<void> _getBrowserHistory() async {
    try {
      final List<dynamic> result = await browserChannel.invokeMethod('getBrowserHistory');
      if (mounted) {
        setState(() {
          _browserHistory = result.map((item) => Map<String, String>.from(item)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching browser history: $e');
      if (mounted) {
        setState(() {
          _browserHistory = [];
        });
      }
    }
  }

  String _formatTimestamp(String timestampStr) {
    try {
      final timestamp = int.tryParse(timestampStr) ?? 0;
      if (timestamp == 0) return 'Unknown';
      
      // Chrome timestamps are in microseconds since 1601, convert to milliseconds since epoch
      final chromeEpochStart = 11644473600000000; // Microseconds
      final millisSinceEpoch = (timestamp - chromeEpochStart) ~/ 1000;
      
      final date = DateTime.fromMillisecondsSinceEpoch(millisSinceEpoch);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      
      return DateFormat('MMM d').format(date);
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childName = prefsManager.getChildName() ?? 'Child';
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A).withOpacity(0.8),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Text(
          "$childName's Dashboard",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                const Text(
                  'Location',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Consumer<WebSocketService>(
                  builder: (context, wsService, child) {
                    return PulsingDot(
                      color: wsService.isConnected ? Colors.green : Colors.grey,
                      size: 8,
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey.shade700,
              child: const Icon(Icons.person, color: Colors.white),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF1A1A1A),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(Icons.person, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "$childName's Dashboard",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.white70),
              title: const Text('Refresh Data', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _refreshData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70),
              title: const Text('Logout', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Logout', style: TextStyle(color: Colors.white)),
                    content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B4A9F),
                        ),
                        child: const Text('Logout', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && mounted) {
                  final prefsManager = context.read<PreferencesManager>();
                  await prefsManager.clearAll();
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                }
              },
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/mountain.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF5B4A9F)))
            : FadeTransition(
                opacity: _entranceFade,
                child: SlideTransition(
                  position: _entranceSlide,
                  child: RefreshIndicator(
                    color: const Color(0xFF5B4A9F),
                    onRefresh: _refreshData,
                    child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Screen Time Card
                    Card(
                      color: const Color(0xFF1A1A1A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Today\'s Screen Time',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _screenTime,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Location Tracking Card
                    Consumer<LocationService>(
                      builder: (context, locationService, child) {
                        return Card(
                          color: const Color(0xFF1A1A1A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      locationService.isTracking
                                          ? Icons.my_location_rounded
                                          : Icons.location_off_rounded,
                                      size: 32,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Live Location',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      if (locationService.currentPosition != null) ...[
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.place_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                locationService.getLocationString(),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'monospace',
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.speed_rounded,
                                              size: 16,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Speed: ${locationService.currentPosition!.speed.toStringAsFixed(1)} m/s',
                                              style: TextStyle(
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.radar_rounded,
                                              size: 16,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Accuracy: -${locationService.currentPosition!.accuracy.toStringAsFixed(1)}m',
                                              style: TextStyle(
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            PulsingDot(
                                              color: Colors.greenAccent,
                                              size: 10,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Live Tracking',
                                              style: TextStyle(
                                                color: Colors.greenAccent,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else ...[
                                        Text(
                                          locationService.locationStatus,
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    
                    // App Usage Summary Card
                    if (_usageStats.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                              context,
                              Icons.apps_rounded,
                              '${_usageStats.length}',
                              'Apps Used',
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white24,
                            ),
                            _buildStatItem(
                              context,
                              Icons.access_time_rounded,
                              _totalUsageTime,
                              'Total Time',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Browser Usage Section
                    if (_browserUsageStats.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.language_rounded, size: 20, color: Color(0xFF9C27B0)),
                          const SizedBox(width: 8),
                          Text(
                            'Browser Activity',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Color(0xFF5B4A9F),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _totalBrowserTime,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        color: const Color(0xFF1A1A1A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _browserUsageStats.length,
                            itemBuilder: (context, index) {
                              final usage = _browserUsageStats[index];
                              final app = _apps[usage.packageName];
                              
                              if (app == null) return const SizedBox.shrink();

                              return Card(
                                color: const Color(0xFF0F0F0F),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Color(0xFF2A2A2A),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: app.icon != null
                                          ? Image.memory(
                                              app.icon!,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                            )
                                          : Icon(
                                              Icons.language_rounded,
                                              color: Color(0xFF9C27B0),
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    app.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Browser app',
                                    style: TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color(0xFF5B4A9F),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _formatDuration(usage.totalTimeInForeground),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Browser History Section - Always show
                    Row(
                      children: [
                        Icon(Icons.history_rounded, size: 20, color: Color(0xFF9C27B0)),
                        const SizedBox(width: 8),
                        Text(
                          'Browsing History',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        if (_browserHistory.isNotEmpty)
                          Text(
                            '${_browserHistory.length} ${_browserHistory.length == 1 ? 'entry' : 'entries'}',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFF1A1A1A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Container(
                        height: 300,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _browserHistory.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 48,
                                        color: Color(0xFF9C27B0),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No browsing history available',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Enable Accessibility Service to track visited websites',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          try {
                                            await platform.invokeMethod('openAccessibilitySettings');
                                          } catch (e) {
                                            debugPrint('Error opening settings: $e');
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(0xFF5B4A9F),
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.settings, size: 18),
                                        label: const Text('Enable Accessibility Service'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: _browserHistory.length,
                                itemBuilder: (context, index) {
                                  final site = _browserHistory[index];
                                  final title = site['title'] ?? 'Unknown';
                                  final url = site['url'] ?? '';
                                  final timestamp = site['timestamp'] ?? '';
                                  
                                  final isErrorMessage = title.contains('Failed') || 
                                                         title.contains('Permission') ||
                                                         title.contains('Debug');
                                  
                                  return Card(
                                    color: const Color(0xFF0F0F0F),
                                    margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isErrorMessage 
                                          ? Color(0xFF5B4A9F).withOpacity(0.3)
                                          : Color(0xFF5B4A9F),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isErrorMessage ? Icons.info_outline_rounded : Icons.public_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        url,
                                        style: TextStyle(
                                          color: isErrorMessage 
                                              ? Colors.white 
                                              : Color(0xFF9C27B0),
                                          fontSize: 12,
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (!isErrorMessage) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatTimestamp(timestamp),
                                          style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 8),
                                        ElevatedButton.icon(
                                          onPressed: () async {
                                            try {
                                              await platform.invokeMethod('openAccessibilitySettings');
                                            } catch (e) {
                                              debugPrint('Error opening settings: $e');
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Color(0xFF5B4A9F),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            minimumSize: const Size(0, 32),
                                          ),
                                          icon: const Icon(Icons.settings, size: 16),
                                          label: const Text('Enable Accessibility Service'),
                                        ),
                                      ],
                                    ],
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // App Usage List Header
                    Row(
                      children: [
                        Text(
                          'App Usage',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('MMM d').format(DateTime.now()),
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // App Usage List in scrollable box
                    Card(
                      color: const Color(0xFF1A1A1A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Container(
                        height: 400,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _usageStats.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.hourglass_empty_rounded,
                                        size: 48,
                                        color: Colors.white60,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No usage data available',
                                        style: TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Grant usage access permission to see statistics',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: _usageStats.length,
                                itemBuilder: (context, index) {
                                  final usage = _usageStats[index];
                                  final app = _apps[usage.packageName];
                                  
                                  if (app == null) return const SizedBox.shrink();

                                  // Check if this app has a time limit
                                  final packageName = usage.packageName ?? '';
                                  final hasLimit = _restrictions?.restrictedApps.containsKey(packageName) ?? false;
                                  final limitHours = hasLimit ? _restrictions!.restrictedApps[packageName] : null;
                                  
                                  // Calculate time used in hours
                                  final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
                                  final usedHours = millis / 1000 / 3600;
                                  
                                  // Check if limit is exceeded
                                  final isExceeded = hasLimit && limitHours != null && usedHours >= limitHours;

                                  return Card(
                                    color: isExceeded ? Color(0xFF5B4A9F).withOpacity(0.3) : Color(0xFF0F0F0F),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      leading: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: Color(0xFF2A2A2A),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: app.icon != null
                                              ? Image.memory(
                                                  app.icon!,
                                                  width: 48,
                                                  height: 48,
                                                  fit: BoxFit.cover,
                                                )
                                              : Icon(
                                                  Icons.android,
                                                  color: Color(0xFF9C27B0),
                                                ),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              app.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (isExceeded)
                                            Icon(
                                              Icons.block_rounded,
                                              size: 16,
                                              color: Colors.redAccent,
                                            ),
                                        ],
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            usage.packageName ?? '',
                                            style: TextStyle(
                                              color: Colors.white60,
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (hasLimit && limitHours != null) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.timer_outlined,
                                                  size: 14,
                                                  color: isExceeded 
                                                      ? Colors.redAccent
                                                      : Color(0xFF9C27B0),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Limit: ${limitHours.toStringAsFixed(1)}h',
                                                  style: TextStyle(
                                                    color: isExceeded 
                                                        ? Colors.redAccent
                                                        : Color(0xFF9C27B0),
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isExceeded
                                              ? Colors.redAccent
                                              : Color(0xFF5B4A9F),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _formatDuration(usage.totalTimeInForeground),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRequestTimeDialog(context),
        backgroundColor: const Color(0xFF5B4A9F),
        icon: const Icon(Icons.access_time, color: Colors.white),
        label: const Text(
          'Request Time',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
  
  void _showRequestTimeDialog(BuildContext context) {
    final TextEditingController hoursController = TextEditingController();
    final TextEditingController reasonController = TextEditingController();
    String? selectedPackageName;
    String? selectedAppName;
    final timeExtService = context.read<TimeExtensionService>();
    
    showDialog(
      context: context,
      builder: (context) => ChangeNotifierProvider.value(
        value: timeExtService,
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.access_time, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Request Extra Time',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select app (optional):',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text(
                      'All apps (general request)',
                      style: TextStyle(color: Colors.white30),
                    ),
                    value: selectedPackageName,
                    dropdownColor: const Color(0xFF2A2A2A),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'All apps (general request)',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      ..._usageStats.take(10).map((usage) {
                        final app = _apps[usage.packageName];
                        final appName = app?.name ?? usage.packageName ?? 'Unknown';
                        return DropdownMenuItem<String>(
                          value: usage.packageName,
                          child: Row(
                            children: [
                              if (app != null && app.icon != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    app.icon!,
                                    width: 24,
                                    height: 24,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                const Icon(Icons.android, size: 24, color: Colors.white54),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  appName,
                                  style: const TextStyle(color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedPackageName = value;
                        if (value != null) {
                          final app = _apps[value];
                          selectedAppName = app?.name ?? value;
                        } else {
                          selectedAppName = null;
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'How many extra hours do you need?',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hoursController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g., 1.5',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.timer, color: Colors.white54),
                  suffixText: 'hours',
                  suffixStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason for request:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Tell your parent why you need extra time...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Consumer<TimeExtensionService>(
                builder: (context, service, child) {
                  final statusText = service.childWsStatusMessage ?? 'Not connected';
                  final responseText = service.lastChildWsResponse ?? 'No response yet';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: service.childWsConnected
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Time Extension WS: $statusText',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Server response: $responseText',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final hoursText = hoursController.text.trim();
              final reason = reasonController.text.trim();
              
              if (hoursText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter the number of hours'),
                    backgroundColor: AppTheme.error,
                  ),
                );
                return;
              }
              
              final hours = double.tryParse(hoursText);
              if (hours == null || hours <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid number'),
                    backgroundColor: AppTheme.error,
                  ),
                );
                return;
              }
              
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason for your request'),
                    backgroundColor: AppTheme.error,
                  ),
                );
                return;
              }
              
              Navigator.pop(context);
              
              // Get child hash from preferences
              final prefsManager = context.read<PreferencesManager>();
              final childHash = prefsManager.getChildHash();
              
              if (childHash == null || childHash.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Error: Child profile not found'),
                    backgroundColor: AppTheme.error,
                  ),
                );
                return;
              }
              
              // Send request with encryption
              final timeExtService = context.read<TimeExtensionService>();
              
              // Show loading indicator
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Encrypting and sending request...'),
                      ],
                    ),
                    backgroundColor: Color(0xFF5B4A9F),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
              
              final success = await timeExtService.createRequest(
                childHash: childHash,
                requestedHours: hours,
                reason: reason,
                packageName: selectedPackageName,
                appName: selectedAppName,
              );
              
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Request sent! Your parent will be notified.'),
                        ),
                      ],
                    ),
                    backgroundColor: AppTheme.success,
                    duration: const Duration(seconds: 3),
                  ),
                );
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to send request. Please try again.'),
                    backgroundColor: AppTheme.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B4A9F),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Send Request',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
  
  Widget _buildStatItem(BuildContext context, IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Color(0xFF9C27B0), size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
