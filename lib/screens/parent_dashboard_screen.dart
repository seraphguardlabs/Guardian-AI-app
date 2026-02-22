import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../services/time_extension_service.dart';
import '../services/encryption_service.dart';
import '../models/time_extension_request.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';
import 'weekly_activity_screen.dart';
import 'location_map_screen.dart';
import '../widgets/weekly_activity_chart.dart';
import '../widgets/app_bottom_nav.dart';
import 'exam_mode_screen.dart';
import 'block_sites_apps_screen.dart';
import 'assign_task_screen.dart';
import '../services/realtime_alert_service.dart';
import '../models/alert.dart';
import 'alert_detail_screen.dart';
import 'risk_alerts_screen.dart';
import '../services/realtime_alert_service.dart';
import '../models/alert.dart';
import 'alert_detail_screen.dart';
import 'risk_alerts_screen.dart';
import 'geofence_management_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen>
  with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  List<Child> _children = [];
  Child? _selectedChild;
  bool _isLoading = true;
  bool _isLoadingData = false;
  bool _weeklyActivityExpanded = false;
  Map<String, dynamic>? _metrics;
  Map<String, dynamic>? _screenTime;
  Map<String, dynamic>? _appUsage;
  Map<String, dynamic>? _locations;
  Map<String, dynamic>? _siteAccess;
  Map<String, dynamic>? _todayScreenTime; // Today's actual screen time data
  double? _dailyLimitHours; // Global daily screen time limit in hours
  late final PageController _metricsPageController;
  late final AnimationController _loadingPulseController;
  double _metricsPage = 0;
  bool _examMode = false;
  List<String> _examModeApps = [];
  bool _loadingExamMode = false;
  StreamSubscription<TimeExtensionRequest>? _newRequestSubscription;
  final RealtimeAlertService _alertService = RealtimeAlertService();
  StreamSubscription<Alert>? _alertSubscription;
  List<Alert> _activeAlerts = [];

  @override
  void initState() {
    super.initState();
    _metricsPageController = PageController(viewportFraction: 0.9);
    _loadingPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _metricsPageController.addListener(() {
      if (!mounted) return;
      setState(() {
        _metricsPage = _metricsPageController.page ?? 0;
      });
    });
    
    // Upload public key to server when parent dashboard is opened
    _uploadPublicKey();
    
    _loadChildren();
    
    _startBackgroundMonitoring();
    
    // Listen for new time extension requests
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      prefs.setViewMode('parent');
      prefs.setLastRoute('/parent_dashboard');
      
      final timeExtService = Provider.of<TimeExtensionService>(context, listen: false);
      _newRequestSubscription = timeExtService.newRequestStream.listen((request) {
        _showNewRequestNotification(request);
      });
      
      _loadActiveAlerts();
    });
  }
  
  @override
  void dispose() {
    _metricsPageController.dispose();
    _loadingPulseController.dispose();
    _newRequestSubscription?.cancel();
    _alertSubscription?.cancel();
    super.dispose();
  }
  
  Future<void> _uploadPublicKey() async {
    debugPrint('🔐 Parent Dashboard: Uploading public key to server...');
    if (EncryptionService.instance.hasKeys) {
      final success = await EncryptionService.instance.uploadPublicKeyToServer();
      if (success) {
        debugPrint('✅ Parent Dashboard: Public key uploaded successfully');
      } else {
        debugPrint('❌ Parent Dashboard: Failed to upload public key');
      }
    } else {
      debugPrint('⚠️ Parent Dashboard: No encryption keys available');
    }
  }

  Future<void> _loadChildren() async {
    debugPrint('🔄 Parent Dashboard: Loading children...');
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    setState(() {
      _isLoading = true;
    });

    final result = await _apiService.fetchChildren(email, password);
    debugPrint('📥 Parent Dashboard: Fetch children result: ${result['success']}');

    if (result['success'] == true) {
      setState(() {
        _children = result['children'] as List<Child>;
        if (_children.isNotEmpty) {
          _selectedChild = _children[0];
        }
        _isLoading = false;
      });
      debugPrint('✅ Parent Dashboard: Loaded ${_children.length} children');
      for (var child in _children) {
        debugPrint('   - ${child.firstName} ${child.lastName}');
      }
      if (_selectedChild != null) {
        _loadChildData(_selectedChild!.childHash);
        _loadExamMode(_selectedChild!.childHash);
      }
    } else {
      debugPrint('❌ Parent Dashboard: Failed to load children: ${result['error']}');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadExamMode(String childHash) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.getExamMode(
      email: email,
      password: password,
      childHash: childHash,
    );

    if (result['success'] == true && mounted) {
      final data = result['data'] as Map<String, dynamic>;
      setState(() {
        _examMode = data['exam_mode'] ?? false;
        _examModeApps = List<String>.from(data['exam_mode_apps'] ?? []);
      });
      debugPrint('✅ Exam mode loaded: $_examMode, Apps: ${_examModeApps.length}');
    }
  }

  Future<void> _toggleExamMode(bool value) async {
    if (_selectedChild == null) return;

    setState(() {
      _loadingExamMode = true;
    });

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.updateExamMode(
      email: email,
      password: password,
      childHash: _selectedChild!.childHash,
      examMode: value,
    );

    setState(() {
      _loadingExamMode = false;
    });

    if (result['success'] == true && mounted) {
      final data = result['data'] as Map<String, dynamic>;
      setState(() {
        _examMode = data['exam_mode'] ?? false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                _examMode ? Icons.school : Icons.check_circle,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(_examMode ? 'Exam mode enabled' : 'Exam mode disabled'),
            ],
          ),
          backgroundColor: _examMode ? Colors.orange : Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to toggle exam mode: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadChildData(String childHash) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    setState(() => _isLoadingData = true);

    // Get today's date for fetching current screen time
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final results = await Future.wait([
      _apiService.fetchChildMetrics(email, password, childHash),
      _apiService.fetchScreenTime(email, password, childHash, startDate: today, endDate: today), // Today only
      _apiService.fetchAppUsage(email, password, childHash),
      _apiService.fetchLocations(email, password, childHash, limit: 50),
      _apiService.fetchSiteAccess(email, password, childHash, filter: 'all', limit: 50),
      _apiService.fetchDailyLimit(email, password, childHash),
    ]);

    setState(() {
      _metrics = results[0]['success'] == true ? results[0]['data'] : null;
      _screenTime = results[1]['success'] == true ? results[1]['data'] : null;
      _appUsage = results[2]['success'] == true ? results[2]['data'] : null;
      _locations = results[3]['success'] == true ? results[3]['data'] : null;
      _siteAccess = results[4]['success'] == true ? results[4]['data'] : null;

      // Global daily limit: use server value when available, otherwise default to 8 hours
      double? fetchedDailyLimitHours;
      if (results.length > 5 && results[5]['success'] == true) {
        final dailyLimitData = results[5]['data'] as Map<String, dynamic>?;
        if (dailyLimitData != null) {
          // Backend returns 'daily_screen_time_limit' (and may not include the old 'daily_limit_hours')
          final value = dailyLimitData['daily_screen_time_limit'] ??
              dailyLimitData['daily_limit_hours'];
          if (value is num) {
            fetchedDailyLimitHours = value.toDouble();
          }
        }
      }

      // If the server does not provide a positive limit, fall back to 8 hours
      if (fetchedDailyLimitHours != null && fetchedDailyLimitHours > 0) {
        _dailyLimitHours = fetchedDailyLimitHours;
      } else {
        _dailyLimitHours = 8.0;
      }
      debugPrint('🕒 Parent dashboard daily limit hours: $_dailyLimitHours');
      
      // Extract today's screen time from trend data
      if (_screenTime != null && _screenTime!['trend'] != null) {
        final trend = _screenTime!['trend'] as List;
        if (trend.isNotEmpty) {
          // The API returns trend data, today should be the first/last entry
          final todayData = trend.firstWhere(
            (item) => item['date'] == today,
            orElse: () => null,
          );
          if (todayData != null) {
            _todayScreenTime = {
              'screen_time_formatted': todayData['formatted'],
              'screen_time_seconds': todayData['total_seconds'],
            };
            debugPrint('📊 Today screen time: ${_todayScreenTime!['screen_time_formatted']} (${_todayScreenTime!['screen_time_seconds']}s)');
          }
        }
      }
      
      _isLoadingData = false;
    });
  }

  void _showAddChildDialog() {
    debugPrint('📝 Parent Dashboard: Showing Add Child dialog');
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final dateOfBirthController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add Child',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                // First Name Field
                TextFormField(
                  controller: firstNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'First Name',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF0F0F0F),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2B4C8F), width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter first name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Last Name Field
                TextFormField(
                  controller: lastNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Last Name',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.person, color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF0F0F0F),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2B4C8F), width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter last name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Date of Birth Field
                TextFormField(
                  controller: dateOfBirthController,
                  style: const TextStyle(color: Colors.white),
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Date of Birth',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.calendar_today, color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF0F0F0F),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2B4C8F), width: 2),
                    ),
                  ),
                  onTap: () async {
                    debugPrint('📅 Parent Dashboard: Date picker tapped');
                    final DateTime? picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFF2B4C8F),
                              onPrimary: Colors.white,
                              surface: Color(0xFF1A1A1A),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      dateOfBirthController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                      debugPrint('📅 Parent Dashboard: Date selected: ${dateOfBirthController.text}');
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please select date of birth';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    debugPrint('👆 Parent Dashboard: Add Child button pressed');
                    if (formKey.currentState!.validate()) {
                      debugPrint('✅ Parent Dashboard: Form validated');
                      Navigator.pop(dialogContext);
                      
                      // Show loading
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
                              Text('Adding child...'),
                            ],
                          ),
                          backgroundColor: Color(0xFF2B4C8F),
                          duration: Duration(seconds: 10),
                        ),
                      );

                      // Get credentials from preferences
                      final prefs = Provider.of<PreferencesManager>(context, listen: false);
                      final email = prefs.getParentEmail() ?? '';
                      final password = prefs.getParentPassword() ?? '';
                      
                      debugPrint('📤 Parent Dashboard: Adding child with credentials:');
                      debugPrint('   Email: $email');
                      debugPrint('   First Name: ${firstNameController.text.trim()}');
                      debugPrint('   Last Name: ${lastNameController.text.trim()}');
                      debugPrint('   DOB: ${dateOfBirthController.text.trim()}');

                      // Call API
                      final result = await _apiService.addChild(
                        email,
                        password,
                        firstNameController.text.trim(),
                        lastNameController.text.trim(),
                        dateOfBirthController.text.trim(),
                      );

                      debugPrint('📥 Parent Dashboard: Add child API result: $result');
                      
                      // Hide loading snackbar
                      if (mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      }

                      if (result['success'] == true && mounted) {
                        debugPrint('✅ Parent Dashboard: Child added successfully!');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result['message'] ?? 'Child added successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        // Only reload the children list, not all dashboard data
                        debugPrint('🔄 Parent Dashboard: Fetching updated children list...');
                        final prefs = Provider.of<PreferencesManager>(context, listen: false);
                        final email = prefs.getParentEmail() ?? '';
                        final password = prefs.getParentPassword() ?? '';
                        final childrenResult = await _apiService.fetchChildren(email, password);
                        if (childrenResult['success'] == true && mounted) {
                          setState(() {
                            _children = childrenResult['children'] as List<Child>;
                            if (_children.isNotEmpty) {
                              _selectedChild = _children[0];
                            }
                          });
                          debugPrint('✅ Parent Dashboard: Children list updated, total: ${_children.length}');
                          for (var child in _children) {
                            debugPrint('   - ${child.firstName} ${child.lastName} (${child.childHash})');
                          }
                        } else {
                          debugPrint('❌ Parent Dashboard: Failed to update children list: \\${childrenResult['error']}');
                        }
                      } else if (mounted) {
                        debugPrint('❌ Parent Dashboard: Failed to add child: ${result['error']}');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result['error'] ?? 'Failed to add child'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } else {
                      debugPrint('❌ Parent Dashboard: Form validation failed');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B4C8F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Add Child',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    debugPrint('👆 Parent Dashboard: Cancel button pressed');
                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChildSwitcher() {
    if (_children.isEmpty) {
      _showAddChildDialog();
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Switch Child',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ..._children.map((child) {
                  final isSelected = _selectedChild?.childHash == child.childHash;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF2B4C8F).withOpacity(0.18) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: const Color(0xFF2B4C8F), width: 2)
                          : null,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: isSelected ? const Color(0xFF2B4C8F) : Colors.grey.shade700,
                        child: child.profileImageUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  'https://seraphguardlabs.com${child.profileImageUrl}',
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.person, color: Colors.white);
                                  },
                                ),
                              )
                            : const Icon(Icons.person, color: Colors.white),
                      ),
                      title: Text(
                        child.firstName,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF2B4C8F) : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Color(0xFF2B4C8F))
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        if (_selectedChild?.childHash != child.childHash) {
                          setState(() {
                            _selectedChild = child;
                          });
                          _loadActiveAlerts();
                          _loadChildData(child.childHash);
                          _loadExamMode(child.childHash);
                        }
                      },
                    ),
                  );
                }).toList(),
                const Divider(color: Colors.white12, height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF5B4A9F), width: 2),
                    ),
                    child: const Icon(Icons.add, color: Color(0xFF5B4A9F)),
                  ),
                  title: const Text(
                    'Add Child',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddChildDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMenuFeatureComingSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title is coming soon'),
        backgroundColor: const Color(0xFF5B4A9F),
      ),
    );
  }

  Future<void> _handleLogout() async {
    Navigator.pop(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
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
  }

  void _startBackgroundMonitoring() {
    // Note: Background monitoring is handled on the child device
    // Parent dashboard only receives alerts from child devices via WebSocket/API
    if (_selectedChild != null) {
      debugPrint('🚀 Parent Dashboard: Monitoring alerts for ${_selectedChild!.firstName}');
    }
  }

  Future<void> _loadActiveAlerts() async {
    if (_selectedChild == null) return;
    
    try {
      final selectedChild = _selectedChild; // Capture to avoid null safety issues
      if (selectedChild == null) return;
      
      // Fetch recent alerts for this child
      final alerts = await _alertService.getRecentAlerts(
        childHash: selectedChild.childHash,
        limit: 10,
      );
      
      setState(() {
        _activeAlerts = alerts;
      });
      
      debugPrint('✅ Loaded ${alerts.length} recent alerts for ${selectedChild.firstName}');
      
      // Subscribe to new alerts from the service
      _alertSubscription?.cancel();
      _alertSubscription = _alertService.alertStream.listen((Alert alert) {
        if (alert.childHash == selectedChild.childHash) {
          if (mounted) {
            setState(() {
              _activeAlerts.insert(0, alert);
              // Keep only recent alerts
              if (_activeAlerts.length > 10) {
                _activeAlerts = _activeAlerts.sublist(0, 10);
              }
            });
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Error loading active alerts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showLoading = _isLoading || (_selectedChild != null && _isLoadingData);
    final Widget dashboardContent;
    if (showLoading) {
      dashboardContent = _buildLoadingState(key: const ValueKey('loading'));
    } else if (_selectedChild != null) {
      dashboardContent = Column(
        key: const ValueKey('content'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_metrics != null) _buildMetricsSection(),
          const SizedBox(height: 16),

          Consumer<TimeExtensionService>(
            builder: (context, timeExtService, _) {
              return _buildPendingRequestsSection(timeExtService);
            },
          ),
          const SizedBox(height: 16),

          if (_screenTime != null) _buildScreenTimeCard(),
          const SizedBox(height: 16),

          if (_appUsage != null) _buildAppUsageCard(),
          const SizedBox(height: 16),

          // Always show locations card (handles empty state internally)
          _buildLocationsCard(),
          const SizedBox(height: 16),

          if (_siteAccess != null) _buildSiteAccessCard(),
          const SizedBox(height: 16),
        ],
      );
    } else {
      dashboardContent = _buildEmptyState(key: const ValueKey('empty'));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 96,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF050608),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 26),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  ),
                ),
                const Spacer(),
                if (_children.isNotEmpty)
                  GestureDetector(
                    onTap: _showChildSwitcher,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.grey.shade700,
                          child: _selectedChild?.profileImageUrl != null
                              ? ClipOval(
                                  child: Image.network(
                                    'https://seraphguardlabs.com${_selectedChild!.profileImageUrl}',
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(Icons.person, color: Colors.white);
                                    },
                                  ),
                                )
                              : const Icon(Icons.person, color: Colors.white),
                        ),
                        Positioned(
                          right: -1,
                          bottom: -1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4F92),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF050608),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF050608),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF101722), Color(0xFF050608)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    child: _selectedChild?.profileImageUrl != null
                        ? ClipOval(
                            child: Image.network(
                              'https://seraphguardlabs.com${_selectedChild!.profileImageUrl}',
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.person, color: Colors.white, size: 26);
                              },
                            ),
                          )
                        : const Icon(Icons.person, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedChild != null
                        ? "${_selectedChild!.firstName}'s profile"
                        : 'Parent profile',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildDrawerMenuItem(
              icon: Icons.insights_outlined,
              label: 'Growth Trends',
              onTap: () {
                Navigator.pop(context);
                _showMenuFeatureComingSoon('Growth Trends');
              },
            ),
            _buildDrawerMenuItem(
              icon: Icons.headset_mic_outlined,
              label: 'Support',
              onTap: () {
                Navigator.pop(context);
                _showMenuFeatureComingSoon('Support');
              },
            ),
            _buildDrawerMenuItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                Navigator.pop(context);
                _showMenuFeatureComingSoon('Settings');
              },
            ),
            _buildDrawerMenuItem(
              icon: Icons.notifications_none_outlined,
              label: 'Notifications',
              onTap: () {
                Navigator.pop(context);
                _showMenuFeatureComingSoon('Notifications');
              },
            ),
            _buildDrawerMenuItem(
              icon: Icons.info_outline,
              label: 'Information',
              onTap: () {
                Navigator.pop(context);
                _showMenuFeatureComingSoon('Information');
              },
            ),
            const Divider(color: Colors.white12, height: 24),
            _buildDrawerMenuItem(
              icon: Icons.logout,
              label: 'Logout',
              isDestructive: true,
              onTap: _handleLogout,
            ),
            const SizedBox(height: 16),
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
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with child name and location status
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
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
                      ],
                    ),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Location indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF101722),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: (_metrics?['metrics']?['latest_location'] != null)
                                        ? const Color(0xFF317AF7)
                                        : Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Safe Today indicator
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF101722),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/images/safe_today_icon.png',
                                width: 24,
                                height: 24,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 24,
                                    height: 24,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: dashboardContent,
              ),
            ],
          ),
        ),
      ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 2,
        onTap: _handleBottomNavTap,
        isParent: true,
      ),
    );
  }

  Widget _buildLoadingState({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSkeletonCard(
            height: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonLine(width: 140, height: 14),
                const SizedBox(height: 16),
                _buildSkeletonLine(width: 220, height: 12),
                const SizedBox(height: 12),
                _buildSkeletonLine(width: 180, height: 12),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSkeletonCard(
            height: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonLine(width: 160, height: 12),
                const SizedBox(height: 14),
                _buildSkeletonLine(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: 240, height: 10),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSkeletonCard(
            height: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonLine(width: 120, height: 12),
                const SizedBox(height: 14),
                _buildSkeletonLine(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: 180, height: 10),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSkeletonCard(
            height: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonLine(width: 140, height: 12),
                const SizedBox(height: 14),
                _buildSkeletonLine(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: 220, height: 10),
                const SizedBox(height: 8),
                _buildSkeletonLine(width: 200, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1420),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1B2433)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.people_alt_outlined, color: Colors.white70, size: 28),
            SizedBox(height: 12),
            Text(
              'No child profile selected',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Choose a child to load dashboard insights and controls.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard({required double height, required Widget child}) {
    return AnimatedBuilder(
      animation: _loadingPulseController,
      builder: (context, _) {
        final base = const Color(0xFF0F1624);
        final highlight = const Color(0xFF1B263B);
        final fill = Color.lerp(base, highlight, _loadingPulseController.value) ?? base;
        return Container(
          height: height,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1B2433)),
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildSkeletonLine({required double width, required double height}) {
    return AnimatedBuilder(
      animation: _loadingPulseController,
      builder: (context, _) {
        final base = const Color(0xFF1C2638);
        final highlight = const Color(0xFF24324A);
        final fill = Color.lerp(base, highlight, _loadingPulseController.value) ?? base;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }

  void _handleBottomNavTap(int index) {
    if (index == 2) {
      // Already on dashboard, do nothing
      return;
    }

    // Handle Alerts (index 1)
    if (index == 1 && _selectedChild != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RiskAlertsScreen(
            childHash: _selectedChild!.childHash,
            childName: _selectedChild!.fullName,
          ),
        ),
      );
      return;
    }

    // Use the Activities (index 3) button to open Exam Mode.
    if (index == 3 && _selectedChild != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ExamModeScreen(child: _selectedChild!),
        ),
      );
      return;
    }

    // Show coming soon dialog for the remaining tabs.
    final titles = [
      'Chat',
      'Rewards',
      'Dashboard',
      'Activities',
      'Profile',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF5B4A9F).withOpacity(0.3),
                    const Color(0xFF4A3280).withOpacity(0.3),
                  ],
                ),
              ),
              child: const Icon(
                Icons.rocket_launch_outlined,
                size: 50,
                color: Color(0xFF5B4A9F),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              titles[index],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Coming Soon',
              style: TextStyle(
                color: Color(0xFF5B4A9F),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'We\'re working hard to bring you this feature. Stay tuned!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(
                color: Color(0xFF5B4A9F),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerMenuItem({
    required IconData icon,
    required String label,
    bool selected = false,
    bool isDestructive = false,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final Color circleColor = selected
        ? const Color(0xFF1E3A8A)
        : const Color(0xFF151515);

    final Color iconColor = selected
        ? Colors.white
        : isDestructive
            ? const Color(0xFFF97373)
            : Colors.white70;

    final TextStyle textStyle = TextStyle(
      color: isDestructive
          ? const Color(0xFFF97373)
          : Colors.white,
      fontSize: 14,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: InkWell
        (
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: textStyle,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingRequestsSection(TimeExtensionService service) {
    // Filter requests to current child and pending status
    final filteredRequests = _selectedChild != null
        ? service.pendingRequests
            .where((req) =>
                req.childHash == _selectedChild!.childHash &&
                (req.status == 'pending' || req.status.isEmpty))
            .toList()
        : service.pendingRequests
            .where((req) => req.status == 'pending' || req.status.isEmpty)
            .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pending Requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  '${filteredRequests.length} pending',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredRequests.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: const [
                  Icon(Icons.check_circle_outline, color: Colors.white54, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No pending time extension requests',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
            )
          else
            ...filteredRequests
                .take(3)
                .map((req) => _buildRequestCard(req, service))
                .toList(),
        ],
      ),
    );
  }

  Widget _buildMetricsSection() {
    final cards = <Widget>[_buildMetricsCard()];

    // Additional insight cards
    cards.add(_buildTopAppsTodayCard());
    cards.add(_buildRiskSignalsCard());
    cards.add(_buildActiveAlertsCard());
    cards.add(_buildWellBeingScoreCard());
    cards.add(_buildChildCertificatesCard());

    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _metricsPageController,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final left = index == 0 ? 20.0 : 10.0;
              final right = index == cards.length - 1 ? 20.0 : 10.0;
              return Padding(
                padding: EdgeInsets.only(left: left, right: right),
                child: cards[index],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(cards.length, (index) {
            final isActive = (_metricsPage - index).abs() < 0.5;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 6,
              width: isActive ? 22 : 8,
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
            );
          }),
        ),
      ],
    );
  }

  // --- Metrics / insights cards ---

  Widget _buildTopAppsTodayCard() {
    final apps = (_appUsage?['apps'] as List?) ?? [];
    final topApps = apps.take(3).toList();

    return _buildMetricsBaseCard(
      gradientColors: const [Color(0xFF2E1065), Color(0xFF4C1D95)],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconTile(
                  assetPath: 'assets/images/top_apps_icon.png',
                  backgroundColor: Colors.white.withOpacity(0.18),
                ),
                const Spacer(),
                Text(
                  topApps.isEmpty ? '-' : topApps.length.toString(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Text(
              'Top Apps Today',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            if (topApps.isEmpty)
              const Text(
                'No app usage data yet',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: topApps.map((app) {
                  final name = (app['name'] ?? app['domain'] ?? 'App').toString();
                  final iconUrl = app['icon_url']?.toString();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (iconUrl != null && iconUrl.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              iconUrl,
                              width: 18,
                              height: 18,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.apps, size: 16, color: Colors.white);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskSignalsCard() {
    // Calculate actual risk level based on alerts
    String riskLevel = 'No Data';
    Color riskLevelColor = Colors.white;
    
    if (_activeAlerts.isNotEmpty) {
      final highAlertCount = _activeAlerts.where((a) => a.severity == AlertSeverity.HIGH).length;
      final totalAlerts = _activeAlerts.length;
      final highPercentage = (highAlertCount / totalAlerts) * 100;
      
      if (highPercentage >= 61) {
        riskLevel = 'High';
        riskLevelColor = const Color(0xFFFF4F92);
      } else if (highPercentage >= 31) {
        riskLevel = 'Medium';
        riskLevelColor = Colors.orange;
      } else {
        riskLevel = 'Low';
        riskLevelColor = Colors.blue;
      }
    }
    
    // Calculate change percent (for now using a placeholder)
    const changePercent = '+23%';
    const changeLabel = '18.6%';

    return _buildMetricsBaseCard(
      gradientColors: const [Color(0xFF6A3A19), Color(0xFF9B4A1C)],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconTile(
                  assetPath: 'assets/images/risk_signals_icon.png',
                  backgroundColor: Colors.white.withOpacity(0.18),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildPillBadge(
                      riskLevel.toUpperCase(),
                      backgroundColor: riskLevel == 'No Data' ? Colors.white : riskLevelColor.withOpacity(0.2),
                      textColor: riskLevel == 'No Data' ? const Color(0xFF6A3A19) : riskLevelColor,
                      horizontalPadding: 14,
                      verticalPadding: 4,
                    ),
                    const SizedBox(height: 8),
                    _buildPillBadge(
                      changeLabel,
                      backgroundColor: Colors.black.withOpacity(0.24),
                      textColor: Colors.white,
                      fontSize: 11,
                      horizontalPadding: 10,
                      verticalPadding: 3,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Text(
              'Risk Signals',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '$changePercent since last month',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAlertsCard() {
    final totalAlerts = _activeAlerts.length;
    final criticalCount = _activeAlerts.where((a) => a.severity == AlertSeverity.HIGH).length;
    final warningCount = _activeAlerts.where((a) => a.severity == AlertSeverity.MEDIUM || a.severity == AlertSeverity.LOW).length;

    return _buildMetricsBaseCard(
      gradientColors: const [Color(0xFF5C101B), Color(0xFF8A182A)],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconTile(
                  assetPath: 'assets/images/active_alerts_icon.png',
                  backgroundColor: Colors.white.withOpacity(0.18),
                ),
                const Spacer(),
                Text(
                  '$totalAlerts',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Text(
              'Active Alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            if (totalAlerts == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No alerts detected today',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              )
            else
              Column(
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      if (criticalCount > 0)
                        _buildPillBadge(
                          '$criticalCount Critical (HIGH)',
                          backgroundColor: const Color(0xFFFF4C4C),
                          textColor: Colors.white,
                        ),
                      if (warningCount > 0)
                        _buildPillBadge(
                          '$warningCount Warning (MEDIUM + LOW)',
                          backgroundColor: Colors.white.withOpacity(0.20),
                          textColor: Colors.white,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ..._activeAlerts.take(3).map((alert) {
                    final severity = alert.severity;
                    final badgeColor = severity == AlertSeverity.HIGH
                        ? const Color(0xFFFF4C4C)
                        : severity == AlertSeverity.MEDIUM
                            ? const Color(0xFFFFA500)
                            : const Color(0xFF2B4C8F);
                    
                    final timeAgo = _formatTimeAgo(alert.timestamp);
                    final severityText = severity.toString().split('.').last;
                    
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AlertDetailScreen(alert: alert),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  severityText,
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alert.summary.length > 60
                                          ? '${alert.summary.substring(0, 60)}...'
                                          : alert.summary,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          alert.childName,
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          timeAgo,
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.white60,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
  Widget _buildWellBeingScoreCard() {
    // Placeholder wellbeing statuses; can be wired to real metrics later
    final wellbeingRows = const [
      ['Physical Activity', 'Good'],
      ['Sleep Quality', 'Excellent'],
      ['Mood', 'Positive'],
    ];

    return _buildMetricsBaseCard(
      gradientColors: const [Color(0xFF066642), Color(0xFF0B8A55)],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconTile(
                  assetPath: 'assets/images/wellbeing_icon.png',
                  backgroundColor: Colors.white.withOpacity(0.18),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: wellbeingRows
                        .map(
                          (row) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _buildWellbeingRow(row[0], row[1]),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Well being Score',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Real-time Well being Score',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildCertificatesCard() {
    return _buildMetricsBaseCard(
      gradientColors: const [Color(0xFF1B2D73), Color(0xFF283C9A)],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIconTile(
                  assetPath: 'assets/images/certificates_icon.png',
                  backgroundColor: Colors.white.withOpacity(0.18),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Text(
              'Child Certificates',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.8)),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: () {
                  // TODO: wire up certificate upload flow
                },
                child: const Text(
                  'Upload',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Small helpers for metrics cards ---

  Widget _buildMetricsBaseCard({
    required List<Color> gradientColors,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -70,
            left: -70,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                shape: BoxShape.circle,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildIconTile({
    required String assetPath,
    required Color backgroundColor,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildPillBadge(
    String label, {
    Color backgroundColor = const Color(0x33FFFFFF),
    Color textColor = Colors.white,
    double fontSize = 12,
    double horizontalPadding = 10,
    double verticalPadding = 5,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildWellbeingRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard() {
    // Use today's screen time from _todayScreenTime which is fetched from /screen-time/ endpoint
    String dailyFormatted = '--';
    double dailySeconds = 0.0;
    
    if (_todayScreenTime != null) {
      dailyFormatted = _todayScreenTime!['screen_time_formatted'] ?? '--';
      dailySeconds = (_todayScreenTime!['screen_time_seconds'] ?? 0).toDouble();
      debugPrint('✅ Using today\'s screen time: $dailyFormatted ($dailySeconds seconds)');
    } else if (_metrics != null) {
      // Fallback to metrics endpoint if today's data not available
      final metrics = _metrics!['metrics'];
      debugPrint('⚠️ No today screen time data, falling back to metrics');
      
      if (metrics['today_screen_time_formatted'] != null && metrics['today_screen_time_formatted'] != '--') {
        dailyFormatted = metrics['today_screen_time_formatted'];
        dailySeconds = (metrics['today_screen_time_seconds'] ?? 0).toDouble();
      } else if (metrics['daily_average_formatted'] != null) {
        dailyFormatted = metrics['daily_average_formatted'];
        dailySeconds = (metrics['daily_average_seconds'] ?? 0).toDouble();
      }
    }
    
    // Use global daily limit from API when available; otherwise fall back to 8 hours
    final effectiveDailyLimitHours = (_dailyLimitHours != null && _dailyLimitHours! > 0)
        ? _dailyLimitHours!
        : 8.0;

    String percentOfLimit = '--';
    double progress = 0.0;
    final limitSeconds = effectiveDailyLimitHours * 3600;
    if (limitSeconds > 0) {
      percentOfLimit =
          ((dailySeconds / limitSeconds) * 100).clamp(0, 999).toStringAsFixed(0);
      progress = (dailySeconds / limitSeconds).clamp(0.0, 1.0);
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3C8B), Color(0xFF0D1F4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D1F4A).withOpacity(0.45),
            blurRadius: 25,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Decorative circle - top right
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Decorative circle - bottom left
            Positioned(
              bottom: -70,
              left: -70,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Screen time icon
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/images/screen_time_icon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Time display with limit
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: dailyFormatted,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                TextSpan(
                                  text: '/${effectiveDailyLimitHours % 1 == 0 ? effectiveDailyLimitHours.toInt().toString() : effectiveDailyLimitHours.toStringAsFixed(1)}h',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white.withOpacity(0.5),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Screen Time',
                    style: TextStyle(
                      fontSize: 22,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$percentOfLimit% of daily limit',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklySummaryCard() {
    final summary = _screenTime!['summary'];
    final average = summary['average_formatted'] ?? '--';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF244969), Color(0xFF122438)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Average',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            average,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Screen time per day',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenTimeCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _weeklyActivityExpanded = !_weeklyActivityExpanded;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101722),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Weekly Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _weeklyActivityExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _weeklyActivityExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const Text(
                  'Tap to view weekly screen time trends',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: WeeklyActivityChart(child: _selectedChild!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppUsageCard() {
    final apps = _appUsage!['apps'] as List;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'App Usage Details',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF101010),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: apps.take(5).map((app) => _buildAppItem(app)).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => _showAllApps(apps),
              child: const Text(
                'Load Earlier Activities',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppItem(Map<String, dynamic> app) {
    // Use average daily seconds instead of total
    final totalSeconds = app['daily_average_seconds'] ?? app['total_seconds'] ?? 0;
    final maxSeconds = _appUsage!['apps'].isNotEmpty 
      ? (_appUsage!['apps'][0]['daily_average_seconds'] ?? _appUsage!['apps'][0]['total_seconds'] ?? 1) 
        : 1;
    final percentage = totalSeconds / maxSeconds;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF222222), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2A2A2A),
                ),
                child: ClipOval(
                  child: app['icon_url'] != null && app['icon_url'].toString().isNotEmpty
                      ? Image.network(
                          app['icon_url'],
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.apps, color: Colors.white, size: 18);
                          },
                        )
                      : const Icon(Icons.apps, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app['name'] ?? app['domain'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app['category'] ?? app['domain'],
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                app['daily_average_formatted'] ?? app['formatted'] ?? '--',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 700),
                  tween: Tween<double>(begin: 0, end: percentage.clamp(0.0, 1.0)),
                  builder: (context, value, child) {
                    return Stack(
                      children: [
                        Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFF242424),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: value,
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF48B3FF),
                                  const Color(0xFF3E6BFF),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(percentage * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
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
    final rawLocations = (_locations?['locations'] as List?) ?? [];
    final locations = rawLocations
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final summary = _locations?['summary'] as Map<String, dynamic>? ?? {'total_count': 0};

    // Derive last-updated time from the latest timestamp, if present.
    DateTime? lastUpdated;
    if (locations.isNotEmpty && locations.first['timestamp'] is String) {
      try {
        lastUpdated = DateTime.parse(locations.first['timestamp'] as String).toLocal();
      } catch (_) {}
    }

    String lastUpdatedLabel = 'No data yet';
    if (lastUpdated != null) {
      lastUpdatedLabel = DateFormat('MMM d, h:mm a').format(lastUpdated!);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LocationMapScreen(
                locations: locations,
                lastUpdated: lastUpdated,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF101010),
            borderRadius: BorderRadius.circular(18),
            border: locations.isEmpty
                ? Border.all(color: Colors.white12, width: 1)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last updated: $lastUpdatedLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Geofencing Button
                      IconButton(
                        icon: const Icon(Icons.share_location_outlined, color: Colors.blueAccent),
                        tooltip: 'Manage Geofences',
                        onPressed: () {
                          if (_selectedChild != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GeofenceManagementScreen(
                                  child: _selectedChild!,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: locations.isEmpty 
                              ? Colors.grey.withOpacity(0.2)
                              : Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          locations.isEmpty
                            ? 'No data'
                            : '${summary['total_count']} tracked',
                          style: TextStyle(
                            color: locations.isEmpty ? Colors.grey : Colors.green,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (locations.isEmpty)
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          color: Colors.white30,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No location data available',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap to view map',
                          style: TextStyle(color: Colors.white24, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Text(
                  'Tap to view recent location path on map.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
            ],
          ),
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
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(18),
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
                              Builder(
                                builder: (context) {
                                  final filteredCount = _selectedChild != null
                                      ? service.pendingRequests
                                          .where((req) => req.childHash == _selectedChild!.childHash)
                                          .length
                                      : service.pendingRequests.length;
                                  return Text(
                                    service.isConnected && service.isAuthenticated
                                        ? 'Connected • $filteredCount pending' 
                                        : 'Offline',
                                    style: TextStyle(
                                      color: service.isConnected && service.isAuthenticated
                                          ? Colors.greenAccent.withOpacity(0.8)
                                          : Colors.white60,
                                      fontSize: 11,
                                    ),
                                  );
                                },
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
            child: Builder(
              builder: (context) {
                // Filter requests by selected child
                final filteredRequests = _selectedChild != null
                    ? timeExtService.pendingRequests
                        .where((req) => req.childHash == _selectedChild!.childHash)
                        .toList()
                    : timeExtService.pendingRequests;
                
                return filteredRequests.isEmpty
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
                              _selectedChild != null
                                  ? 'No pending requests from ${_selectedChild!.firstName}'
                                  : 'No pending requests',
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
                        itemCount: filteredRequests.length,
                        itemBuilder: (context, index) {
                          final request = filteredRequests[index];
                          return _buildRequestCard(request, timeExtService);
                        },
                      );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(TimeExtensionRequest request, TimeExtensionService service) {
    String? messageText;
    if (request.messageEncrypted != null && request.messageEncrypted!.isNotEmpty) {
      // Try to decrypt with guardian private key; fall back to raw text
      final encryptionService = EncryptionService.instance;
      final decrypted = encryptionService.decryptWithPrivateKey(request.messageEncrypted!);
      messageText = decrypted ?? request.messageEncrypted;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar, title, time, status chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2A2A2A),
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request From ${request.childName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4B6E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          
          // App info
          Text(
            'App: ${request.getAppName()}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          if (request.appDomain.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              request.appDomain,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Requested: ${(request.requestedHours * 60).round()} mins extra',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          if (messageText != null && messageText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Message: $messageText',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await _showGrantTimeDialog(context, request, service);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Approve',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: OutlinedButton(
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
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFE4E6),
                    foregroundColor: const Color(0xFFBE123C),
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(fontWeight: FontWeight.w600),
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

  Future<void> _showGrantTimeDialog(BuildContext context, TimeExtensionRequest request, TimeExtensionService service) async {
    final hoursController = TextEditingController(text: request.requestedHours.toString());
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.add_alarm, color: Color(0xFF5B4A9F)),
            const SizedBox(width: 8),
            const Text(
              'Grant Extra Time',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Grant extra time to ${request.childName} for:',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
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
                    child: Text(
                      request.getAppName(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hours to grant:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: hoursController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter hours (e.g., 1.5)',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F0F0F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.schedule, color: Color(0xFF5B4A9F)),
                suffixText: 'hours',
                suffixStyle: const TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildQuickTimeButton(context, hoursController, 0.5),
                const SizedBox(width: 8),
                _buildQuickTimeButton(context, hoursController, 1.0),
                const SizedBox(width: 8),
                _buildQuickTimeButton(context, hoursController, 2.0),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
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
              
              final success = await service.respondToRequest(
                requestId: request.requestId,
                action: 'approve',
                grantedHours: hours,
              );
              
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 8),
                        Text('Granted ${hours}h to ${request.childName}'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to grant time. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Grant Time'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B4A9F),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTimeButton(BuildContext context, TextEditingController controller, double hours) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () {
          controller.text = hours.toString();
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF5B4A9F),
          side: const BorderSide(color: Color(0xFF5B4A9F)),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Text('${hours}h', style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  void _showExamModeDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _examMode
                        ? [Colors.orange, Colors.deepOrange]
                        : [const Color(0xFF5B4A9F), const Color(0xFF4A3280)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _examMode ? Icons.school : Icons.school_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Exam Mode',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                    border: _examMode
                        ? Border.all(color: Colors.orange.withOpacity(0.5), width: 2)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _examMode ? 'Exam Mode Active' : 'Exam Mode Inactive',
                              style: TextStyle(
                                color: _examMode ? Colors.orange : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _examMode
                                  ? 'All selected apps are currently blocked'
                                  : 'Enable to block distracting apps during study time',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _loadingExamMode
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.orange,
                              ),
                            )
                          : Switch(
                              value: _examMode,
                              onChanged: (value) async {
                                setDialogState(() {});
                                await _toggleExamMode(value);
                                setDialogState(() {});
                              },
                              activeColor: Colors.orange,
                            ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.block, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Apps to Block (${_examModeApps.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_examModeApps.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'No apps selected.\nAdd apps to block during exam mode.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  ...List.generate(_examModeApps.length, (index) {
                    final packageName = _examModeApps[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.android, color: Color(0xFF9C27B0), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _getAppNameFromPackage(packageName),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                            onPressed: () async {
                              await _removeAppFromExamMode(packageName);
                              setDialogState(() {});
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddAppToExamModeDialog(setDialogState),
                    icon: const Icon(Icons.add),
                    label: const Text('Add App to Block'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF5B4A9F),
                      side: const BorderSide(color: Color(0xFF5B4A9F)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  String _getAppNameFromPackage(String packageName) {
    final appNames = {
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.snapchat.android': 'Snapchat',
      'com.google.android.youtube': 'YouTube',
      'com.facebook.katana': 'Facebook',
      'com.whatsapp': 'WhatsApp',
      'com.twitter.android': 'Twitter/X',
      'com.facebook.orca': 'Messenger',
    };
    return appNames[packageName] ?? packageName.split('.').last;
  }

  Future<void> _removeAppFromExamMode(String packageName) async {
    if (_selectedChild == null) return;

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.updateExamMode(
      email: email,
      password: password,
      childHash: _selectedChild!.childHash,
      action: 'remove_app',
      package: packageName,
    );

    if (result['success'] == true && mounted) {
      final data = result['data'] as Map<String, dynamic>;
      setState(() {
        _examModeApps = List<String>.from(data['exam_mode_apps'] ?? []);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('App removed from exam mode'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showAddAppToExamModeDialog(StateSetter parentSetState) {
    final commonApps = {
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.snapchat.android': 'Snapchat',
      'com.google.android.youtube': 'YouTube',
      'com.facebook.katana': 'Facebook',
      'com.whatsapp': 'WhatsApp',
      'com.twitter.android': 'Twitter/X',
      'com.facebook.orca': 'Messenger',
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Select App to Block', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: commonApps.entries.map((entry) {
              final isAlreadyAdded = _examModeApps.contains(entry.key);
              return ListTile(
                leading: const Icon(Icons.android, color: Color(0xFF9C27B0)),
                title: Text(entry.value, style: const TextStyle(color: Colors.white)),
                trailing: isAlreadyAdded
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.add_circle_outline, color: Colors.white70),
                enabled: !isAlreadyAdded,
                onTap: isAlreadyAdded
                    ? null
                    : () async {
                        Navigator.pop(context);
                        await _addAppToExamMode(entry.key);
                        parentSetState(() {});
                      },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Future<void> _addAppToExamMode(String packageName) async {
    if (_selectedChild == null) return;

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.updateExamMode(
      email: email,
      password: password,
      childHash: _selectedChild!.childHash,
      action: 'add_app',
      package: packageName,
    );

    if (result['success'] == true && mounted) {
      final data = result['data'] as Map<String, dynamic>;
      setState(() {
        _examModeApps = List<String>.from(data['exam_mode_apps'] ?? []);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('${_getAppNameFromPackage(packageName)} added to exam mode'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showNewRequestNotification(TimeExtensionRequest request) {
    if (!mounted) return;
    
    // Show snackbar notification
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF5B4A9F), width: 2),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B4A9F),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.access_time,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'New Time Extension Request',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${request.childName} wants ${request.requestedHours}h more for ${request.appDomain}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            if (request.messageEncrypted != null && request.messageEncrypted!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Request includes a message',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: const Color(0xFF5B4A9F),
          onPressed: () {
            // Scroll to pending requests section
          },
        ),
      ),
    );
  }
}
