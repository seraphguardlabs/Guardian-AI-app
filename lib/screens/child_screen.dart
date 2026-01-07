import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:usage_stats/usage_stats.dart';
import 'package:device_apps/device_apps.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../utils/preferences_manager.dart';
import '../services/location_service.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../services/app_blocker_service.dart';
import '../services/background_monitoring_service.dart';
import '../services/time_extension_service.dart';
import '../models/restrictions_data.dart';

class ChildScreen extends StatefulWidget {
  const ChildScreen({super.key});

  @override
  State<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends State<ChildScreen> {
  static const platform = MethodChannel('com.guardian_ai/screen_time');
  static const browserChannel = MethodChannel('com.guardian_ai/browser_history');
  String _screenTime = 'Unknown';
  bool _loading = true;
  List<UsageInfo> _usageStats = [];
  Map<String, Application> _apps = {};
  List<Map<String, String>> _browserHistory = [];
  Timer? _refreshTimer;
  RestrictionsData? _restrictions;
  StreamSubscription<Map<String, dynamic>>? _wsMessageSubscription;
  StreamSubscription<Map<String, dynamic>>? _wsRestrictionsSubscription;

  @override
  void initState() {
    super.initState();
    BackgroundMonitoringService.start();
    _refreshData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshData();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.startTracking();
      _initializeWebSocket();
      _fetchRestrictions();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wsMessageSubscription?.cancel();
    _wsRestrictionsSubscription?.cancel();
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
    _sendDataViaWebSocket();
  }

  Future<void> _initializeWebSocket() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();

    if (childHash != null && childHash.isNotEmpty) {
      final wsService = Provider.of<WebSocketService>(context, listen: false);
      await wsService.connect(childHash);
      debugPrint('🔌 WebSocket connected for child: $childHash');

      _wsMessageSubscription = wsService.messages.listen((message) {
        if (message['type'] == 'restrictions_update') {
          debugPrint('🚫 Received restrictions update via WebSocket');
          _fetchRestrictions();
        }
      });

      _wsRestrictionsSubscription = wsService.restrictions.listen((message) {
        if (message['type'] == 'restrictions_update') {
          debugPrint('🚫 Received restrictions from WSS');
          final restrictedApps = message['restricted_apps'] as Map<String, dynamic>? ?? {};

          final appBlocker = Provider.of<AppBlockerService>(context, listen: false);
          appBlocker.updateRestrictions(restrictedApps);
          BackgroundMonitoringService.updateRestrictions(restrictedApps);

          if (mounted) {
            setState(() {
              _restrictions = RestrictionsData.fromJson(restrictedApps);
            });
          }
        }
      });
    } else {
      debugPrint('⚠️ No child hash found, skipping WebSocket connection');
    }
  }

  Future<void> _fetchRestrictions() async {
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefsManager.getChildHash();

    if (childHash == null || childHash.isEmpty) {
      debugPrint('⚠️ No child hash, skipping restrictions fetch');
      return;
    }

    final apiService = Provider.of<ApiService>(context, listen: false);
    final result = await apiService.fetchRestrictions(childHash);

    if (result['success'] == true && mounted) {
      final restrictions = result['restrictions'] as RestrictionsData;
      setState(() {
        _restrictions = restrictions;
      });
      debugPrint('✅ Restrictions updated: ${_restrictions!.restrictedApps.length} apps');

      final appBlocker = Provider.of<AppBlockerService>(context, listen: false);
      appBlocker.updateRestrictions(_restrictions!.restrictedApps);
      BackgroundMonitoringService.updateRestrictions(_restrictions!.restrictedApps);
    }
  }

  Future<void> _sendDataViaWebSocket() async {
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    if (!wsService.isConnected) {
      debugPrint('⚠️ WebSocket not connected, skipping data send');
      return;
    }

    await _sendScreenTimeData();
    await _sendLocationData();
    await _sendWebsiteData();
  }

  Future<void> _sendScreenTimeData() async {
    if (_usageStats.isEmpty) return;

    final wsService = Provider.of<WebSocketService>(context, listen: false);

    int totalSeconds = 0;
    final appWiseData = <String, Map<String, int>>{};

    for (var usage in _usageStats) {
      final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
      final seconds = millis ~/ 1000;
      totalSeconds += seconds;
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

    debugPrint('📱 Sent screen time: ${totalSeconds}s, ${appWiseData.length} apps');
  }

  Future<void> _sendLocationData() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final wsService = Provider.of<WebSocketService>(context, listen: false);

    if (locationService.currentPosition != null) {
      await wsService.sendLocation(
        timestamp: DateTime.now().toUtc().toIso8601String(),
        latitude: locationService.currentPosition!.latitude,
        longitude: locationService.currentPosition!.longitude,
      );

      debugPrint('📍 Sent location: ${locationService.currentPosition!.latitude}, ${locationService.currentPosition!.longitude}');
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

    debugPrint('🌐 Sent ${logs.length} website visits');
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
      bool? isPermissionGranted = await UsageStats.checkUsagePermission();
      if (isPermissionGranted == null || !isPermissionGranted) {
        await UsageStats.grantUsagePermission();
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

      List<Application> apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: true,
      );

      Map<String, Application> appMap = {
        for (var app in apps) app.packageName: app
      };

      DateTime now = DateTime.now();
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = now;

      List<UsageInfo> usageStats = await UsageStats.queryUsageStats(
        startOfDay,
        endOfDay,
      );

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
      'browser',
      'chrome',
      'firefox',
      'opera',
      'edge',
      'safari',
      'brave',
      'duck',
      'samsung internet',
      'uc browser',
      'dolphin',
      'maxthon',
      'puffin',
      'kiwi',
      'vivaldi',
      'tor',
      'duckduckgo'
    ];
    final lowerPackage = packageName.toLowerCase();
    final lowerName = appName.toLowerCase();
    return browserKeywords.any((keyword) =>
        lowerPackage.contains(keyword) || lowerName.contains(keyword));
  }

  List<UsageInfo> get _browserUsageStats {
    return _usageStats.where((usage) {
      final app = _apps[usage.packageName];
      if (app == null) return false;
      return _isBrowserApp(usage.packageName ?? '', app.appName);
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
          _browserHistory =
              result.map((item) => Map<String, String>.from(item)).toList();
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

      final chromeEpochStart = 11644473600000000;
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

  String _calculateScreenTimePercentage() {
    // Parse the screen time (e.g., "2h 15m" or "45m")
    final timeStr = _screenTime;
    final dailyLimitHours = 3.0; // Default 3 hour limit
    
    try {
      double totalHours = 0.0;
      
      // Extract hours
      final hoursMatch = RegExp(r'(\d+)h').firstMatch(timeStr);
      if (hoursMatch != null) {
        totalHours += double.parse(hoursMatch.group(1)!);
      }
      
      // Extract minutes
      final minutesMatch = RegExp(r'(\d+)m').firstMatch(timeStr);
      if (minutesMatch != null) {
        totalHours += double.parse(minutesMatch.group(1)!) / 60;
      }
      
      final percentage = ((totalHours / dailyLimitHours) * 100).clamp(0, 100).toInt();
      return '$percentage% of daily limit';
    } catch (e) {
      return '0% of daily limit';
    }
  }

  bool _hasExceededApps() {
    if (_restrictions == null || _usageStats.isEmpty) return false;
    
    for (var usage in _usageStats) {
      final packageName = usage.packageName ?? '';
      final hasLimit = _restrictions!.restrictedApps.containsKey(packageName);
      if (hasLimit) {
        final limitHours = _restrictions!.restrictedApps[packageName];
        if (limitHours != null) {
          final millis = int.tryParse(usage.totalTimeInForeground ?? '0') ?? 0;
          final usedHours = millis / 1000 / 3600;
          if (usedHours >= limitHours) {
            return true;
          }
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prefsManager = Provider.of<PreferencesManager>(context, listen: false);
    final childName = prefsManager.getChildName() ?? 'Child';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
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
          Consumer<LocationService>(
            builder: (context, locationService, child) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on, color: Colors.white, size: 12),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Location',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: locationService.isTracking ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey.shade700,
              child: const Icon(Icons.person, color: Colors.white, size: 20),
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
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF5B4A9F)))
          : RefreshIndicator(
              color: const Color(0xFF5B4A9F),
              onRefresh: _refreshData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Screen Time Card - Modern Design
                    Container(
                      height: 215,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.access_time_outlined,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _screenTime.split(' ')[0],
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4, left: 4),
                                child: Text(
                                  '/3h',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Screen Time',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _calculateScreenTimePercentage(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
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
                          const Icon(Icons.language_rounded, size: 20, color: Color(0xFF9C27B0)),
                          const SizedBox(width: 8),
                          const Text(
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
                              color: const Color(0xFF5B4A9F),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _totalBrowserTime,
                              style: const TextStyle(
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
                                    vertical: 16,
                                  ),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: const Color(0xFF2A2A2A),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: app is ApplicationWithIcon
                                          ? Image.memory(
                                              app.icon,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                            )
                                          : const Icon(
                                              Icons.language_rounded,
                                              color: Color(0xFF9C27B0),
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    app.appName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  subtitle: const Text(
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
                                      color: const Color(0xFF5B4A9F),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _formatDuration(usage.totalTimeInForeground),
                                      style: const TextStyle(
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
                    
                    // Browser History Section
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 20, color: Color(0xFF9C27B0)),
                        const SizedBox(width: 8),
                        const Text(
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
                            style: const TextStyle(
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
                                      const Icon(
                                        Icons.info_outline_rounded,
                                        size: 48,
                                        color: Color(0xFF9C27B0),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No browsing history available',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
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
                                          backgroundColor: const Color(0xFF5B4A9F),
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
                                              ? const Color(0xFF5B4A9F).withOpacity(0.3)
                                              : const Color(0xFF5B4A9F),
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
                                        style: const TextStyle(
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
                                                  : const Color(0xFF9C27B0),
                                              fontSize: 12,
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (!isErrorMessage) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatTimestamp(timestamp),
                                              style: const TextStyle(
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
                                                backgroundColor: const Color(0xFF5B4A9F),
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
                        const Text(
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
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // App Usage List
                    Card(
                      color: const Color(0xFF1A1A1A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Container(
                        height: _hasExceededApps() ? 425 : 400,
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
                                    children: const [
                                      Icon(
                                        Icons.hourglass_empty_rounded,
                                        size: 48,
                                        color: Colors.white60,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'No usage data available',
                                        style: TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(height: 8),
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
                                    color: isExceeded ? const Color(0xFF5B4A9F).withOpacity(0.3) : const Color(0xFF0F0F0F),
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
                                          color: const Color(0xFF2A2A2A),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: app is ApplicationWithIcon
                                              ? Image.memory(
                                                  app.icon,
                                                  width: 48,
                                                  height: 48,
                                                  fit: BoxFit.cover,
                                                )
                                              : const Icon(
                                                  Icons.android,
                                                  color: Color(0xFF9C27B0),
                                                ),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              app.appName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (isExceeded)
                                            const Icon(
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
                                            style: const TextStyle(
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
                                                      : const Color(0xFF9C27B0),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Limit: ${limitHours.toStringAsFixed(1)}h',
                                                  style: TextStyle(
                                                    color: isExceeded 
                                                        ? Colors.redAccent
                                                        : const Color(0xFF9C27B0),
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isExceeded
                                                  ? Colors.redAccent
                                                  : const Color(0xFF5B4A9F),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _formatDuration(usage.totalTimeInForeground),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (isExceeded) ...[
                                            const SizedBox(height: 4),
                                            TextButton.icon(
                                              onPressed: () => _showRequestTimeDialog(
                                                context,
                                                packageName: packageName,
                                                appName: app.appName,
                                              ),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                minimumSize: const Size(0, 0),
                                                backgroundColor: Colors.orangeAccent.withOpacity(0.2),
                                              ),
                                              icon: const Icon(
                                                Icons.add_alarm_rounded,
                                                size: 14,
                                                color: Colors.orangeAccent,
                                              ),
                                              label: const Text(
                                                'Request',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.orangeAccent,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
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
    );
  }
  
  void _showRequestTimeDialog(BuildContext context, {String? packageName, String? appName}) {
    final TextEditingController hoursController = TextEditingController();
    final TextEditingController reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              if (appName != null) ...[
                const Text(
                  'Requesting time for:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.apps, color: Color(0xFF9C27B0), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
              debugPrint('\n🎯 CHILD SCREEN: Send Request button clicked');
              final hoursText = hoursController.text.trim();
              final reason = reasonController.text.trim();
              
              debugPrint('🎯 Hours input: $hoursText');
              debugPrint('🎯 Reason input: $reason');
              debugPrint('🎯 Package: $packageName');
              debugPrint('🎯 App: $appName');
              
              if (hoursText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter the number of hours'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              final hours = double.tryParse(hoursText);
              if (hours == null || hours <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid number'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a reason for your request'),
                    backgroundColor: Colors.red,
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
                    backgroundColor: Colors.red,
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
                packageName: packageName,
                appName: appName,
              );
              
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('Request sent! Your parent will be notified.'),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to send request. Please try again.'),
                    backgroundColor: Colors.red,
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
    );
  }
  
  Widget _buildStatItem(BuildContext context, IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF9C27B0), size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
