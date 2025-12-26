import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
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
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/login');
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadChildren,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _children.isEmpty
                  ? const Center(
                      child: Text(
                        'No children found',
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Child',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<Child>(
                                isExpanded: true,
                                value: _selectedChild,
                                icon: const Icon(Icons.arrow_drop_down),
                                items: _children.map((Child child) {
                                  return DropdownMenuItem<Child>(
                                    value: child,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundImage: child.profileImageUrl != null
                                              ? NetworkImage(
                                                  'https://seraphguardlabs.com${child.profileImageUrl}',
                                                )
                                              : null,
                                          child: child.profileImageUrl == null
                                              ? Text(
                                                  child.firstName[0].toUpperCase(),
                                                  style: const TextStyle(fontSize: 14),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '${child.firstName} ${child.lastName}',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (Child? newValue) {
                                  setState(() {
                                    _selectedChild = newValue;
                                  });
                                  if (newValue != null) {
                                    _loadChildData(newValue.childHash);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_selectedChild != null) ...[
                            if (_isLoadingData)
                              const Center(child: CircularProgressIndicator())
                            else ...[
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      // Metrics Overview
                                      if (_metrics != null) _buildMetricsCard(),
                                      const SizedBox(height: 16),
                                      // Screen Time
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
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _buildMetricsCard() {
    final metrics = _metrics!['metrics'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(Icons.access_time, 'Screen Time', metrics['total_screen_time_formatted']),
                _buildMetricItem(Icons.apps, 'Apps Used', '${metrics['unique_apps_used']}'),
                _buildMetricItem(Icons.block, 'Blocked', '${metrics['site_access']['total_blocked']}'),
              ],
            ),
            if (metrics['latest_location'] != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Latest Location', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(metrics['latest_location']['address'] ?? 'Unknown location'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.blue),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildScreenTimeCard() {
    final summary = _screenTime!['summary'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Screen Time', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildInfoRow('Total', summary['total_formatted']),
            _buildInfoRow('Daily Average', summary['average_formatted']),
            _buildInfoRow('Peak Day', '${summary['max_formatted']} on ${summary['max_date']}'),
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
            const Text('Top Apps', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...apps.take(5).map((app) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  Expanded(child: Text(app['name'] ?? app['domain'])),
                  Text('${app['formatted']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationsCard() {
    final locations = _locations!['locations'] as List;
    final summary = _locations!['summary'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recent Locations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${summary['total_count']} locations tracked', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ...locations.take(5).map((loc) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 16),
                  const SizedBox(width: 8),
                  Text('${loc['latitude'].toStringAsFixed(4)}, ${loc['longitude'].toStringAsFixed(4)}'),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Site Access', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Blocked: ${summary['blocked_count']}', style: const TextStyle(color: Colors.red)),
                Text('Accessed: ${summary['accessed_count']}', style: const TextStyle(color: Colors.green)),
              ],
            ),
            const SizedBox(height: 16),
            ...logs.take(5).map((log) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Icon(
                    log['accessed'] ? Icons.check_circle : Icons.block,
                    size: 16,
                    color: log['accessed'] ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(log['domain'], overflow: TextOverflow.ellipsis)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
