import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/child.dart';
import '../services/api_service.dart';
import '../utils/preferences_manager.dart';
import 'assign_task_screen.dart';
import 'block_sites_apps_screen.dart';

class ExamModeScreen extends StatefulWidget {
  final Child child;

  const ExamModeScreen({super.key, required this.child});

  @override
  State<ExamModeScreen> createState() => _ExamModeScreenState();
}

class _ExamModeScreenState extends State<ExamModeScreen> {
  final ApiService _apiService = ApiService();

  bool _loading = true;
  bool _savingToggle = false;
  bool _examMode = false;
  List<String> _examModeApps = [];
  bool _loadingDailyLimit = true;
  double? _dailyLimitHours;

  @override
  void initState() {
    super.initState();
    _loadExamMode();
    _loadDailyLimit();
  }

  Future<void> _loadExamMode() async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.getExamMode(
      email: email,
      password: password,
      childHash: widget.child.childHash,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      setState(() {
        _examMode = data['exam_mode'] ?? false;
        _examModeApps = List<String>.from(data['exam_mode_apps'] ?? []);
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to load exam mode'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadDailyLimit() async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    try {
      final result = await _apiService.fetchDailyLimit(
        email,
        password,
        widget.child.childHash,
      );

      if (!mounted) return;

      double? fetchedDailyLimitHours;
      if (result['success'] == true) {
        final data = result['data'] as Map<String, dynamic>?;
        if (data != null) {
          // Backend returns 'daily_screen_time_limit' (and may not include the old 'daily_limit_hours')
          final value = data['daily_screen_time_limit'] ?? data['daily_limit_hours'];
          if (value is num) {
            fetchedDailyLimitHours = value.toDouble();
          }
        }
      }

      setState(() {
        _dailyLimitHours = fetchedDailyLimitHours;
        _loadingDailyLimit = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingDailyLimit = false;
      });
    }
  }

  Future<void> _toggleExamMode(bool value) async {
    if (_savingToggle) return;

    setState(() {
      _savingToggle = true;
    });

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.updateExamMode(
      email: email,
      password: password,
      childHash: widget.child.childHash,
      examMode: value,
    );

    if (!mounted) return;

    setState(() {
      _savingToggle = false;
    });

    if (result['success'] == true) {
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
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.updateExamMode(
      email: email,
      password: password,
      childHash: widget.child.childHash,
      action: 'remove_app',
      package: packageName,
    );

    if (!mounted) return;

    if (result['success'] == true) {
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

  void _showAddAppDialog() {
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
        title: const Text(
          'Select App to Block',
          style: TextStyle(color: Colors.white),
        ),
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
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.updateExamMode(
      email: email,
      password: password,
      childHash: widget.child.childHash,
      action: 'add_app',
      package: packageName,
    );

    if (!mounted) return;

    if (result['success'] == true) {
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

  String _buildDailyLimitSubtitle() {
    if (_loadingDailyLimit) {
      return 'Daily Limit : Loading...';
    }
    if (_dailyLimitHours != null && _dailyLimitHours! > 0) {
      final hours = _dailyLimitHours!;
      final text = hours == hours.roundToDouble()
          ? hours.toStringAsFixed(0)
          : hours.toStringAsFixed(1);
      return 'Daily Limit : $text hr';
    }
    return 'Daily Limit : Not set';
  }

  void _showDailyLimitDialog() {
    final controller = TextEditingController(
      text: _dailyLimitHours != null && _dailyLimitHours! > 0
          ? (_dailyLimitHours! == _dailyLimitHours!.roundToDouble()
              ? _dailyLimitHours!.toStringAsFixed(0)
              : _dailyLimitHours!.toStringAsFixed(1))
          : '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Set Daily Screen Time Limit',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the total allowed screen time per day for this child (in hours).',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Daily limit (hours)',
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: 'e.g. 3 or 4.5',
                  hintStyle: const TextStyle(color: Colors.white38),
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
                    borderSide: const BorderSide(color: Color(0xFF5B4A9F), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Leave empty to remove the daily limit.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                final text = controller.text.trim();
                double? hours;
                if (text.isNotEmpty) {
                  hours = double.tryParse(text);
                  if (hours == null || hours <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid number of hours'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }

                Navigator.pop(context);

                final prefs = Provider.of<PreferencesManager>(context, listen: false);
                final email = prefs.getParentEmail() ?? '';
                final password = prefs.getParentPassword() ?? '';

                final result = await _apiService.updateDailyLimit(
                  email,
                  password,
                  widget.child.childHash,
                  hours,
                );

                if (!mounted) return;

                if (result['success'] == true) {
                  // Reload from server so we always display the canonical value
                  await _loadDailyLimit();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        hours == null
                            ? 'Daily limit removed'
                            : 'Daily limit set to ${hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : hours.toStringAsFixed(1)} hr',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result['error'] ?? 'Failed to update daily limit'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Save', style: TextStyle(color: Color(0xFF9C27B0))),
            ),
          ],
        );
      },
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
        title: const Text(
          'Command Center',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
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
                  // Set Screen Time card
                  _CommandCard(
                    title: 'Set Screen Time',
                    subtitle: _buildDailyLimitSubtitle(),
                    onTap: _showDailyLimitDialog,
                  ),
                  const SizedBox(height: 16),

                  // Assign Task card
                  _CommandCard(
                    title: 'Assign Task',
                    subtitle: 'Create tasks for ${widget.child.firstName}',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AssignTaskScreen(child: widget.child),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Block Sites & Apps card
                  _CommandCard(
                    title: 'Block Sites & Apps',
                    subtitle: 'Manage app time limits',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BlockSitesAppsScreen(child: widget.child),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Exam Mode section header
                  const Text(
                    'Exam Mode',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // App Control card
                  _AppPermissionCard(
                    appNames: _examModeApps.map(_getAppNameFromPackage).toList(),
                    onEdit: _showAddAppDialog,
                  ),
                  const SizedBox(height: 16),

                  // Exam Mode card
                  _ExamModeCard(
                    enabled: _examMode,
                    saving: _savingToggle,
                    onChanged: _toggleExamMode,
                  ),
                ],
              ),
            ),
    );
  }
}

class _CommandCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _CommandCard({
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const Icon(Icons.edit, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AppPermissionCard extends StatelessWidget {
  final List<String> appNames;
  final VoidCallback onEdit;

  const _AppPermissionCard({
    required this.appNames,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final count = appNames.length;
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
            children: [
              const Text(
                'App Control',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
                onPressed: onEdit,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'No. of daily app control : $count Apps',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          if (appNames.isEmpty)
            const Text(
              'No apps selected yet.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: appNames
                  .map(
                    (name) => Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24, width: 0.5),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _ExamModeCard extends StatelessWidget {
  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onChanged;

  const _ExamModeCard({
    required this.enabled,
    required this.saving,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Exam Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Turn on the exam mode',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          saving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.greenAccent,
                  ),
                )
              : Switch(
                  value: enabled,
                  onChanged: onChanged,
                  activeColor: Colors.green,
                ),
        ],
      ),
    );
  }
}
