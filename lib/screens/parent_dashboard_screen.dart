import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../services/time_extension_service.dart';
import '../models/time_extension_request.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final ApiService _apiService = ApiService();
  List<Child> _children = [];
  Child? _selectedChild;
  bool _isLoading = true;
  bool _isLoadingData = false;
  String? _errorMessage;
  Map<String, dynamic>? _metrics;
  Map<String, dynamic>? _screenTime;
  Map<String, dynamic>? _appUsage;
  Map<String, dynamic>? _locations;
  Map<String, dynamic>? _siteAccess;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _apiService.fetchChildren(email, password);

    if (result['success'] == true) {
      setState(() {
        _children = result['children'] as List<Child>;
        if (_children.isNotEmpty) {
          _selectedChild = _children[0];
        }
        _isLoading = false;
      });
      if (_selectedChild != null) {
        _loadChildData(_selectedChild!.childHash);
      }
    } else {
      setState(() {
        _errorMessage = result['error'] ?? 'Failed to load children';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadChildData(String childHash) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    setState(() => _isLoadingData = true);

    final results = await Future.wait([
      _apiService.fetchChildMetrics(email, password, childHash),
      _apiService.fetchScreenTime(email, password, childHash),
      _apiService.fetchAppUsage(email, password, childHash),
      _apiService.fetchLocations(email, password, childHash, limit: 50),
      _apiService.fetchSiteAccess(email, password, childHash, filter: 'all', limit: 50),
    ]);

    setState(() {
      _metrics = results[0]['success'] == true ? results[0]['data'] : null;
      _screenTime = results[1]['success'] == true ? results[1]['data'] : null;
      _appUsage = results[2]['success'] == true ? results[2]['data'] : null;
      _locations = results[3]['success'] == true ? results[3]['data'] : null;
      _siteAccess = results[4]['success'] == true ? results[4]['data'] : null;
      _isLoadingData = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        actions: [
          if (_selectedChild != null)
            IconButton(
              icon: const Icon(Icons.access_time, color: Colors.white),
              onPressed: () {
                // Connect to time extension WebSocket before showing requests
                final timeExtService = Provider.of<TimeExtensionService>(context, listen: false);
                timeExtService.connect();
                
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: true,
                  enableDrag: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => _buildTimeExtensionBottomSheet(),
                );
              },
              tooltip: 'Time Extension Requests',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey.shade700,
              child: _selectedChild?.profileImageUrl != null
                  ? ClipOval(
                      child: Image.network(
                        'https://seraphguardlabs.com${_selectedChild!.profileImageUrl}',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.person, color: Colors.white);
                        },
                      ),
                    )
                  : const Icon(Icons.person, color: Colors.white),
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
              decoration: BoxDecoration(
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
                    child: _selectedChild?.profileImageUrl != null
                        ? ClipOval(
                            child: Image.network(
                              'https://seraphguardlabs.com${_selectedChild!.profileImageUrl}',
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.person, color: Colors.white, size: 32);
                              },
                            ),
                          )
                        : const Icon(Icons.person, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Parent Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70),
              title: const Text('Logout', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context); // Close drawer
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.purple),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 60,
                        color: Colors.red.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 16, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadChildren,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                )
              : _children.isEmpty
                  ? const Center(
                      child: Text(
                        'No children found',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with child name
                          Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedChild != null
                                      ? "${_selectedChild!.firstName}'s Dashboard"
                                      : "Dashboard",
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_metrics?['metrics']?['latest_location'] != null)
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Location',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),

                          if (_selectedChild != null) ...[
                            if (_isLoadingData)
                              const Padding(
                                padding: EdgeInsets.all(40.0),
                                child: Center(
                                  child: CircularProgressIndicator(color: Colors.purple),
                                ),
                              )
                            else ...[
                              // Main metrics cards
                              if (_metrics != null) _buildMetricsCard(),
                              const SizedBox(height: 16),

                              // Weekly Activity Section
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  'Weekly Activity',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Screen Time Trends
                              if (_screenTime != null) _buildScreenTimeCard(),
                              const SizedBox(height: 16),

                              // Top Apps
                              if (_appUsage != null) _buildAppUsageCard(),
                              const SizedBox(height: 16),

                              // Recent Locations
                              if (_locations != null) _buildLocationsCard(),
                              const SizedBox(height: 16),

                              // Site Access
                              if (_siteAccess != null) _buildSiteAccessCard(),
                              const SizedBox(height: 20),
                            ],
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _buildMetricsCard() {
    final metrics = _metrics!['metrics'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF5B4A9F),
              Color(0xFF4A3280),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.phone_android,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                Spacer(),
                Text(
                  '/3h',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              metrics['total_screen_time_formatted'],
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white,
                decorationThickness: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Screen Time',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '${((metrics['total_screen_time_seconds'] ?? 0) / 10800 * 100).toStringAsFixed(0)}% of daily limit',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenTimeCard() {
    final summary = _screenTime!['summary'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Screen Time Trends',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Last 7 Days',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),
            _buildInfoRow('Total', summary['total_formatted'], Colors.purple),
            _buildInfoRow('Daily Average', summary['average_formatted'], Colors.blue),
            _buildInfoRow('Peak Day', '${summary['max_formatted']} on ${summary['max_date']}', Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildAppUsageCard() {
    final apps = _appUsage!['apps'] as List;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Top Apps', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => _showAllApps(apps),
                  icon: const Icon(Icons.list, size: 18),
                  label: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...apps.take(5).map((app) => _buildAppItem(app)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppItem(Map<String, dynamic> app) {
    final totalSeconds = app['total_seconds'] ?? 0;
    final maxSeconds = _appUsage!['apps'].isNotEmpty 
        ? (_appUsage!['apps'][0]['total_seconds'] ?? 1) 
        : 1;
    final percentage = totalSeconds / maxSeconds;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // App Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Color(0xFF2A2A2A),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: app['icon_url'] != null
                      ? Image.network(
                          app['icon_url'],
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(Icons.android, color: Colors.white54, size: 24);
                          },
                        )
                      : Icon(Icons.android, color: Colors.white54, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              // App Name and Package
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app['name'] ?? app['domain'],
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app['domain'],
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Usage Time
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.purple.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  app['formatted'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade300,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Set Limit Button
              IconButton(
                icon: Icon(Icons.timer_outlined, size: 20, color: Colors.white54),
                tooltip: 'Set Daily Limit',
                onPressed: () => _showSetLimitDialog(app),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Animated horizontal bar graph
          Row(
            children: [
              const SizedBox(width: 56), // Align with app name
              Expanded(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(begin: 0, end: percentage),
                  builder: (context, value, child) {
                    return Stack(
                      children: [
                        // Background bar
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        // Animated progress bar
                        FractionallySizedBox(
                          widthFactor: value,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.purple.shade400,
                                  Colors.purple.shade600,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purple.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Percentage indicator
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(begin: 0, end: app['percentage'] ?? 0),
                builder: (context, value, child) {
                  return Text(
                    '${value.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white54,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAllApps(List apps) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'All Apps',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        return _buildAppItem(apps[index]);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSetLimitDialog(Map<String, dynamic> app) {
    final TextEditingController hoursController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Color(0xFF2A2A2A),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: app['icon_url'] != null
                    ? Image.network(
                        app['icon_url'],
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(Icons.android, color: Colors.white54);
                        },
                      )
                    : Icon(Icons.android, color: Colors.white54),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    app['name'] ?? app['domain'],
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  Text(
                    'Set Daily Time Limit',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current usage: ${app['daily_average_formatted']} per day',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hoursController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Daily Limit (hours)',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'e.g., 2.0 or 1.5',
                hintStyle: TextStyle(color: Colors.white30),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.purple),
                ),
                suffixText: 'hours/day',
                suffixStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Examples: 2.0 = 2 hours, 1.5 = 1 hour 30 min, 0.5 = 30 min',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final hoursText = hoursController.text.trim();
              if (hoursText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a time limit'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              final hours = double.tryParse(hoursText);
              if (hours == null || hours <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Please enter a valid number'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              Navigator.pop(context);
              await _setAppRestriction(app['domain'], hours, app['name']);
            },
            icon: const Icon(Icons.check),
            label: const Text('Set Limit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setAppRestriction(String packageName, double hours, String? appName) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    if (_selectedChild == null) return;

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Setting limit for ${appName ?? packageName}...'),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    final result = await _apiService.updateRestrictions(
      email: email,
      password: password,
      childHash: _selectedChild!.childHash,
      action: 'add',
      package: packageName,
      hours: hours,
    );

    // Dismiss loading snackbar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${appName ?? packageName} limited to $hours hour${hours == 1.0 ? '' : 's'} per day',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: ${result['error'] ?? 'Unknown error'}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildLocationsCard() {
    final locations = _locations!['locations'] as List;
    final summary = _locations!['summary'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Locations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${summary['total_count']} tracked',
                    style: TextStyle(color: Colors.green, fontSize: 11),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            ...locations.take(5).map((loc) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 18, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${loc['latitude'].toStringAsFixed(4)}, ${loc['longitude'].toStringAsFixed(4)}',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSiteAccessCard() {
    final logs = _siteAccess!['logs'] as List;
    final summary = _siteAccess!['summary'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Site Access',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${summary['blocked_count']} blocked',
                        style: TextStyle(color: Colors.red, fontSize: 11),
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${summary['accessed_count']} ok',
                        style: TextStyle(color: Colors.green, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),
            ...logs.take(5).map((log) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Icon(
                    log['accessed'] ? Icons.check_circle : Icons.block,
                    size: 16,
                    color: log['accessed'] ? Colors.green : Colors.red,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log['domain'],
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return DateFormat('HH:mm').format(timestamp);
    } else if (difference.inDays < 7) {
      return DateFormat('EEE HH:mm').format(timestamp);
    } else {
      return DateFormat('MMM d, HH:mm').format(timestamp);
    }
  }

  Widget _buildTimeExtensionBottomSheet() {
    final timeExtService = Provider.of<TimeExtensionService>(context);
    
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.access_time, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Time Extension Requests',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Consumer<TimeExtensionService>(
                        builder: (context, service, child) {
                          return Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: service.isConnected && service.isAuthenticated
                                      ? Colors.greenAccent 
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                service.isConnected && service.isAuthenticated
                                    ? 'Connected • ${service.pendingRequests.length} pending' 
                                    : 'Offline',
                                style: TextStyle(
                                  color: service.isConnected && service.isAuthenticated
                                      ? Colors.greenAccent.withOpacity(0.8)
                                      : Colors.white60,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  onPressed: () {
                    timeExtService.requestPendingUpdates();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Request List
          Expanded(
            child: timeExtService.pendingRequests.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: Colors.white24,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No pending requests',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: timeExtService.pendingRequests.length,
                    itemBuilder: (context, index) {
                      final request = timeExtService.pendingRequests[index];
                      return _buildRequestCard(request, timeExtService);
                    },
                  ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(TimeExtensionRequest request, TimeExtensionService service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Child name and time
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    request.childName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.childName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      request.getFormattedTime(),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // App info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.apps, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.getAppName(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        request.appDomain,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B4A9F).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF5B4A9F).withOpacity(0.3)),
                  ),
                  child: Text(
                    '+${request.requestedHours}h',
                    style: const TextStyle(
                      color: Color(0xFFB8A4E8),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final success = await service.respondToRequest(
                      requestId: request.requestId,
                      action: 'deny',
                    );
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Request denied'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Deny'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.2),
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.red.withOpacity(0.3)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final success = await service.respondToRequest(
                      requestId: request.requestId,
                      action: 'approve',
                      grantedHours: request.requestedHours,
                    );
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Granted ${request.requestedHours}h extra time'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B4A9F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatBottomSheet() {
    final TextEditingController messageController = TextEditingController();
    final chatService = Provider.of<ChatService>(context, listen: false);
    final childHash = _selectedChild?.childHash ?? '';
    
    // Connect to WebSocket only once when opened (don't call on every rebuild)
    // The connection is already established when the bottom sheet is shown
    // See _showChatBottomSheet() method
    
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.child_care, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedChild != null 
                          ? '${_selectedChild!.firstName} ${_selectedChild!.lastName}'
                          : 'Chat',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Consumer<ChatService>(
                        builder: (context, chatService, child) {
                          return Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: chatService.isConnected 
                                      ? Colors.greenAccent 
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                chatService.isConnected 
                                    ? 'E2E Encrypted • Connected' 
                                    : 'E2E Encrypted • Offline',
                                style: TextStyle(
                                  color: chatService.isConnected 
                                      ? Colors.greenAccent.withOpacity(0.8)
                                      : Colors.white60,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Messages area
          Expanded(
            child: Consumer<ChatService>(
              builder: (context, chatService, child) {
                if (chatService.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF5B4A9F),
                    ),
                  );
                }
                
                if (chatService.messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.white60, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Send a message to start the conversation',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }
                
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  reverse: true,
                  itemCount: chatService.messages.length,
                  itemBuilder: (context, index) {
                    final message = chatService.messages[chatService.messages.length - 1 - index];
                    final displayText = message.messageDecrypted ?? '[Encrypted]';
                    
                    return Align(
                      alignment: message.isFromParent 
                          ? Alignment.centerRight 
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        decoration: BoxDecoration(
                          gradient: message.isFromParent
                              ? const LinearGradient(
                                  colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                                )
                              : null,
                          color: message.isFromParent ? null : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatTime(message.timestamp),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Input area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF0F0F0F),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () async {
                        if (messageController.text.trim().isNotEmpty && _selectedChild != null) {
                          final message = messageController.text.trim();
                          messageController.clear();
                          
                          final success = await chatService.sendMessage(
                            _selectedChild!.childHash,
                            message,
                          );
                          
                          if (!success && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('⚠️ Failed to send message. No encryption key found for child.'),
                                backgroundColor: Colors.red,
                                duration: Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      },
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
