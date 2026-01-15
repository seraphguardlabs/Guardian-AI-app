import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/child.dart';
import '../services/api_service.dart';
import '../utils/preferences_manager.dart';

class BlockSitesAppsScreen extends StatefulWidget {
  final Child child;

  const BlockSitesAppsScreen({super.key, required this.child});

  @override
  State<BlockSitesAppsScreen> createState() => _BlockSitesAppsScreenState();
}

class _BlockSitesAppsScreenState extends State<BlockSitesAppsScreen> {
  final ApiService _apiService = ApiService();

  bool _loading = true;
  bool _saving = false;
  Map<String, double> _restrictedApps = {};
  List<Map<String, dynamic>> _restrictedAppsDetailed = [];
  List<Map<String, dynamic>> _availableApps = [];

  @override
  void initState() {
    super.initState();
    _loadRestrictions();
    _loadAvailableApps();
  }

  Future<void> _loadRestrictions() async {
    setState(() {
      _loading = true;
    });

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.getAppRestrictions(
      email: email,
      password: password,
      childHash: widget.child.childHash,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      final rawRestricted = data['restricted_apps'] as Map<String, dynamic>? ?? {};
      final detailed = (data['restricted_apps_detailed'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      final parsedRestricted = <String, double>{};
      rawRestricted.forEach((key, value) {
        final v = value;
        if (v is num) {
          parsedRestricted[key.toString()] = v.toDouble();
        }
      });

      setState(() {
        _restrictedApps = parsedRestricted;
        _restrictedAppsDetailed = detailed;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
      });

      final error = result['error']?.toString() ?? 'Failed to load restrictions';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadAvailableApps() async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    debugPrint('📥 Loading available apps for app limits...');
    final result = await _apiService.fetchAppUsage(
      email,
      password,
      widget.child.childHash,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      final apps = (data['apps'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      debugPrint('✅ Loaded ${apps.length} apps for Add App Limit');

      setState(() {
        _availableApps = apps;
      });
    } else {
      debugPrint('❌ Failed to load available apps for limits: ${result['error']}');
    }
  }

  Future<void> _setRestriction(String packageName, double hours, {String? appName}) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    setState(() {
      _saving = true;
    });

    final isUpdate = _restrictedApps.containsKey(packageName);

    final result = await _apiService.updateRestrictions(
      email: email,
      password: password,
      childHash: widget.child.childHash,
      action: isUpdate ? 'update' : 'add',
      package: packageName,
      hours: hours,
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
    });

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
      await _loadRestrictions();
    } else {
      final error = result['error']?.toString() ?? 'Failed to update restriction';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeRestriction(String packageName, {String? appName}) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    setState(() {
      _saving = true;
    });

    final result = await _apiService.updateRestrictions(
      email: email,
      password: password,
      childHash: widget.child.childHash,
      action: 'remove',
      package: packageName,
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
    });

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${appName ?? packageName} restriction removed',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _loadRestrictions();
    } else {
      final error = result['error']?.toString() ?? 'Failed to remove restriction';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showAddRestrictionDialog() async {
    final hoursController = TextEditingController();

    if (_availableApps.isEmpty) {
      // Try to load the latest app list from the server (apps sent from child device)
      await _loadAvailableApps();

      if (_availableApps.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No app usage data available yet from the child device'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    String? selectedPackage;
    String? selectedName;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Add App Limit',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: selectedPackage,
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Select App',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
                isExpanded: true,
                items: _availableApps.map((app) {
                  final pkg = (app['domain'] ?? app['package'] ?? '').toString();
                  final name = (app['name'] ?? pkg).toString();
                  final iconUrl = app['icon_url']?.toString();
                  if (pkg.isEmpty) return null;
                  return DropdownMenuItem<String>(
                    value: pkg,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (iconUrl != null && iconUrl.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              iconUrl,
                              width: 20,
                              height: 20,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.apps, size: 18, color: Colors.white);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).whereType<DropdownMenuItem<String>>().toList(),
                onChanged: (value) {
                  setStateDialog(() {
                    selectedPackage = value;
                    if (value != null) {
                      final app = _availableApps.firstWhere(
                        (a) => (a['domain'] ?? a['package']).toString() == value,
                        orElse: () => {},
                      );
                      selectedName = (app['name'] ?? '').toString();
                    } else {
                      selectedName = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: hoursController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Daily Limit (hours)',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: 'e.g., 2.0 or 1.5',
                  hintStyle: TextStyle(color: Colors.white30),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Examples: 2.0 = 2 hours, 1.5 = 1h 30m, 0.5 = 30m',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () async {
                final hoursText = hoursController.text.trim();

                if (selectedPackage == null || hoursText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select an app and enter a time limit'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final hours = double.tryParse(hoursText);
                if (hours == null || hours <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid number of hours'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                await _setRestriction(selectedPackage!, hours, appName: selectedName);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRestrictionDialog(Map<String, dynamic> app) {
    final package = (app['package'] ?? app['domain'] ?? '').toString();
    final name = (app['name'] ?? '').toString();
    final existingHours = (app['hours_limit'] ?? app['hours']) is num
        ? ((app['hours_limit'] ?? app['hours']) as num).toDouble()
        : _restrictedApps[package];

    final hoursController = TextEditingController(
      text: existingHours != null ? existingHours.toString() : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          name.isNotEmpty ? name : package,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: hoursController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Daily Limit (hours)',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'e.g., 2.0 or 1.5',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Set to 0 or remove to unblock completely',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _removeRestriction(package, appName: name.isNotEmpty ? name : null);
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final hoursText = hoursController.text.trim();
              final hours = double.tryParse(hoursText);

              if (hours == null || hours <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid number of hours'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(context);
              await _setRestriction(package, hours, appName: name.isNotEmpty ? name : null);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildRestrictedAppsSection() {
    if (_restrictedApps.isEmpty && _restrictedAppsDetailed.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFF071A2E), Color(0xFF021012)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Text(
          'No app limits set yet. Use the button below to add limits for distracting apps.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    }

    final items = _restrictedAppsDetailed.isNotEmpty
        ? _restrictedAppsDetailed
        : _restrictedApps.entries
            .map((e) => {
                  'package': e.key,
                  'name': e.key,
                  'hours_limit': e.value,
                })
            .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF071A2E), Color(0xFF021012)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Blocked Apps',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white12),
            itemBuilder: (context, index) {
              final app = items[index];
              final name = (app['name'] ?? app['package'] ?? app['domain'] ?? '').toString();
              final package = (app['package'] ?? app['domain'] ?? '').toString();
              final hours = (app['hours_limit'] ?? app['hours']) is num
                  ? ((app['hours_limit'] ?? app['hours']) as num).toDouble()
                  : _restrictedApps[package];

              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  name.isNotEmpty ? name : package,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: hours != null
                    ? Text(
                        'Limit: $hours h/day',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      )
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
                  onPressed: () => _showEditRestrictionDialog(app),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSitesPlaceholderSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF071A2E), Color(0xFF021012)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Blocked Websites',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Site blocking controls are coming soon. For now, you can review site activity from the dashboard.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Block Sites & Apps',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orange,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRestrictionDialog(),
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add),
        label: const Text('Add App Limit'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.child.firstName.isNotEmpty
                        ? "${widget.child.firstName}'s restrictions"
                        : 'App & site restrictions',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRestrictedAppsSection(),
                  const SizedBox(height: 16),
                  _buildSitesPlaceholderSection(),
                ],
              ),
            ),
    );
  }
}
