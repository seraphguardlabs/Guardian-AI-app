import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:usage_stats/usage_stats.dart';
import 'package:device_apps/device_apps.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../utils/preferences_manager.dart';
import '../services/location_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const platform = MethodChannel('com.guardian_ai/screen_time');
  static const browserChannel = MethodChannel('com.guardian_ai/browser_history');
  String _screenTime = 'Unknown';
  bool _loading = true;
  List<UsageInfo> _usageStats = [];
  Map<String, Application> _apps = {};
  List<Map<String, String>> _browserHistory = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshData();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshData();
    });
    
    // Start location tracking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.startTracking();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
      List<Application> apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: true,
      );
      
      Map<String, Application> appMap = {
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
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardian AI'),
        backgroundColor: colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == 'logout') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Logout'),
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
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Screen Time Card
                    Card(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.primaryContainer,
                              colorScheme.secondaryContainer,
                            ],
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
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Today\'s Screen Time',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _screenTime,
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
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
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.secondaryContainer,
                                  colorScheme.tertiaryContainer,
                                ],
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
                                      color: locationService.isTracking
                                          ? colorScheme.primary
                                          : colorScheme.error,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Live Location',
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface.withOpacity(0.7),
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
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                locationService.getLocationString(),
                                                style: theme.textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'monospace',
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
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Speed: ${locationService.currentPosition!.speed.toStringAsFixed(1)} m/s',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: colorScheme.onSurfaceVariant,
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
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Accuracy: ±${locationService.currentPosition!.accuracy.toStringAsFixed(1)}m',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Live Tracking',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: Colors.green,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else ...[
                                        Text(
                                          locationService.locationStatus,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
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
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.tertiaryContainer,
                              colorScheme.secondaryContainer,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
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
                              color: colorScheme.outline.withOpacity(0.3),
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
                          Icon(Icons.language_rounded, size: 20, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Browser Activity',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _totalBrowserTime,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
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
                                      color: colorScheme.surfaceContainerHighest,
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
                                          : Icon(
                                              Icons.language_rounded,
                                              color: colorScheme.primary,
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    app.appName,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Browser app',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _formatDuration(usage.totalTimeInForeground),
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onErrorContainer,
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
                        Icon(Icons.history_rounded, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Browsing History',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_browserHistory.isNotEmpty)
                          Text(
                            '${_browserHistory.length} ${_browserHistory.length == 1 ? 'entry' : 'entries'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Container(
                        height: 300,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
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
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No browsing history available',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Enable Accessibility Service to track visited websites',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        onPressed: () async {
                                          try {
                                            await platform.invokeMethod('openAccessibilitySettings');
                                          } catch (e) {
                                            debugPrint('Error opening settings: $e');
                                          }
                                        },
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
                                    margin: const EdgeInsets.only(bottom: 8),
                                    color: isErrorMessage ? colorScheme.errorContainer.withOpacity(0.3) : null,
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
                                          ? colorScheme.errorContainer 
                                          : colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isErrorMessage ? Icons.info_outline_rounded : Icons.public_rounded,
                                      color: isErrorMessage 
                                          ? colorScheme.error 
                                          : colorScheme.primary,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
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
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: isErrorMessage 
                                              ? colorScheme.onSurface 
                                              : colorScheme.primary,
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (!isErrorMessage) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatTimestamp(timestamp),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 8),
                                        FilledButton.icon(
                                          onPressed: () async {
                                            try {
                                              await platform.invokeMethod('openAccessibilitySettings');
                                            } catch (e) {
                                              debugPrint('Error opening settings: $e');
                                            }
                                          },
                                          icon: const Icon(Icons.settings, size: 16),
                                          label: const Text('Enable Accessibility Service'),
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            minimumSize: const Size(0, 32),
                                          ),
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
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('MMM d').format(DateTime.now()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // App Usage List in scrollable box
                    Card(
                      child: Container(
                        height: 400,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
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
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No usage data available',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Grant usage access permission to see statistics',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
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

                                  return Card(
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
                                          color: colorScheme.surfaceContainerHighest,
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
                                              : Icon(
                                                  Icons.android,
                                                  color: colorScheme.primary,
                                                ),
                                        ),
                                      ),
                                      title: Text(
                                        app.appName,
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        usage.packageName ?? '',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _formatDuration(usage.totalTimeInForeground),
                                          style: theme.textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onPrimaryContainer,
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
    );
  }
  
  Widget _buildStatItem(BuildContext context, IconData icon, String value, String label) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Column(
      children: [
        Icon(icon, color: colorScheme.primary, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onTertiaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onTertiaryContainer,
          ),
        ),
      ],
    );
  }
}
