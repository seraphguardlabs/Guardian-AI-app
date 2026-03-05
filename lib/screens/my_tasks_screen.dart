import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../services/api_service.dart';
import '../services/time_extension_service.dart';
import '../services/encryption_service.dart';
import '../utils/preferences_manager.dart';
import '../utils/app_theme.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  final ApiService _apiService = ApiService();
  StreamSubscription? _wsSubscription;
  
  bool _loading = true;
  bool _updating = false;
  List<Task> _tasks = [];
  String _filter = 'all'; // 'all', 'true', 'false'
  int _totalTasks = 0;
  int _pendingTasks = 0;
  int _completedTasks = 0;

  // Screen-time reward requests (time extension requests with an assigned task)
  List<Map<String, dynamic>> _rewardRequests = [];
  bool _loadingRewards = false;
  Timer? _rewardRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _loadRewardRequests();

    // Auto-refresh reward requests every 30 seconds so newly-assigned tasks appear promptly
    _rewardRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadRewardRequests();
    });
    
    // Listen for task assignments related to time requests
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final timeService = context.read<TimeExtensionService>();
      _wsSubscription = timeService.childResponseStream.listen((data) {
        if (data['type'] == 'time_extension_response' || data['type'] == 'task_assigned') {
          debugPrint('🔄 MyTasksScreen: Received WS update, refreshing...');
          _loadTasks();
          _loadRewardRequests();
        }
      });
    });
  }

  Future<void> _loadRewardRequests() async {
    setState(() => _loadingRewards = true);
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash() ?? '';
    if (childHash.isEmpty) { setState(() => _loadingRewards = false); return; }

    final result = await _apiService.fetchChildTimeRequests(
      childHash: childHash,
      status: 'all',
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final List<Map<String, dynamic>> all =
          List<Map<String, dynamic>>.from(result['requests'] as List);
      debugPrint('⏰ Child time requests: ${all.length} total');
      for (final r in all) {
        debugPrint('   req#${r['request_id']}: status=${r['status']} taskId=${r['task_id']}');
      }
      // Show requests where status indicates a task has been assigned,
      // OR where the backend returns task_id/task_title explicitly.
      setState(() {
        _rewardRequests = all.where((r) {
          final status = (r['status'] as String? ?? '').toLowerCase();
          final hasTaskStatus = status == 'task_assigned' || status == 'task_completed';
          final hasTaskField = r['task_id'] != null || r['task_title'] != null;
          final isResolved = status == 'approved' || status == 'denied';
          return (hasTaskStatus || hasTaskField) && !isResolved;
        }).toList();
        _loadingRewards = false;
      });
      debugPrint('⏰ Reward requests shown: ${_rewardRequests.length}');
    } else {
      setState(() => _loadingRewards = false);
    }
  }

  Future<void> _completeRewardTask(Map<String, dynamic> request) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash() ?? '';
    // task_id can be int or String depending on server version
    final rawId = request['task_id'];
    final int? taskId = rawId is int
        ? rawId
        : rawId is String
            ? int.tryParse(rawId)
            : null;
    if (taskId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot complete: task ID not found'), backgroundColor: Colors.red),
      );
      return;
    }

    if (childHash.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: child profile not found'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _updating = true);

    // Call the backend API so the server marks the task as complete and
    // notifies the guardian via WebSocket. The guardian then decides
    // whether to approve the time extension.
    final result = await _apiService.completeTask(
      childHash: childHash,
      taskId: taskId,
    );

    if (!mounted) return;
    setState(() => _updating = false);

    if (result['success'] == true) {
      // Also save locally so the UI updates immediately
      await prefs.markRewardTaskLocallyDone(taskId);
      setState(() {
        request['is_task_completed'] = true;
        request['is_task_completed_locally'] = true;
      });

      // Check if the time extension was auto-approved by the server
      final autoApproved = result['time_extension_approved'];
      final message = autoApproved != null
          ? 'Task done — time extension approved! 🎉'
          : 'Task done! Your parent has been notified to approve your time.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: autoApproved != null ? AppTheme.success : AppTheme.accentPurple,
          duration: const Duration(seconds: 3),
        ),
      );

      // Refresh reward requests to reflect the new status
      _loadRewardRequests();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to complete task'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _rewardRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash() ?? '';

    debugPrint('📋 ========== MY_TASKS_SCREEN LOAD TASKS ==========');
    debugPrint('📋 Child Hash: ${childHash.isEmpty ? "EMPTY" : childHash}');
    debugPrint('📋 Filter: $_filter');

    if (childHash.isEmpty) {
      debugPrint('📋 ❌ CANNOT LOAD TASKS: Child Hash is empty');
      setState(() => _loading = false);
      return;
    }

    debugPrint('📋 ✅ Child Hash OK, calling API...');
    // Always fetch all tasks for correct counters
    final result = await _apiService.getMyTasks(
      childHash: childHash,
      completed: 'all',
    );

    debugPrint('📋 API Result success: ${result['success']}');

    if (!mounted) {
      debugPrint('📋 ⚠️ Widget not mounted, cannot update state');
      return;
    }

    if (result['success'] == true) {
      List<Task> tasks = result['tasks'] as List<Task>;
      debugPrint('📋 ✅ Received ${tasks.length} tasks from API');

      // Decrypt task titles and descriptions
      final encryptionService = EncryptionService.instance;
      debugPrint('📋 Starting decryption...');
      List<Task> decryptedTasks = tasks.map((task) {
        final decryptedTitle = encryptionService.decryptWithPrivateKey(task.title);
        final decryptedDescription = encryptionService.decryptWithPrivateKey(task.description);
        if (decryptedTitle != null || decryptedDescription != null) {
          return Task(
            id: task.id,
            title: decryptedTitle ?? task.title,
            description: decryptedDescription ?? task.description,
            isCompleted: task.isCompleted,
            completedAt: task.completedAt,
            created: task.created,
            updated: task.updated,
            assignedBy: task.assignedBy,
          );
        }
        return task;
      }).toList();

      // Calculate stats from all tasks
      int totalTasks = decryptedTasks.length;
      int pendingTasks = decryptedTasks.where((t) => !t.isCompleted).length;
      int completedTasks = decryptedTasks.where((t) => t.isCompleted).length;

      // Filter tasks for display
      List<Task> displayTasks;
      if (_filter == 'true') {
        displayTasks = decryptedTasks.where((t) => t.isCompleted).toList();
      } else if (_filter == 'false') {
        displayTasks = decryptedTasks.where((t) => !t.isCompleted).toList();
      } else {
        displayTasks = decryptedTasks;
      }

      setState(() {
        _tasks = displayTasks;
        _totalTasks = totalTasks;
        _pendingTasks = pendingTasks;
        _completedTasks = completedTasks;
        _loading = false;
      });
      debugPrint('📋 State updated: _tasks.length = ${_tasks.length}');
    } else {
      debugPrint('📋 ❌ Failed to load tasks: ${result['error']}');
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to load tasks'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _toggleTaskStatus(Task task) async {
    setState(() => _updating = true);

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final childHash = prefs.getChildHash() ?? '';

    final result = task.isCompleted
        ? await _apiService.incompleteTask(
            childHash: childHash,
            taskId: task.id,
          )
        : await _apiService.completeTask(
            childHash: childHash,
            taskId: task.id,
          );

    if (!mounted) return;

    setState(() => _updating = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                task.isCompleted ? Icons.undo : Icons.check_circle,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.isCompleted ? 'Task reopened' : 'Task completed!',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task status updated.'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    // Always reload to reflect status change
    _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Tasks',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_updating)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primary,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_loadTasks(), _loadRewardRequests()]);
        },
        color: AppTheme.accentPurple,
        backgroundColor: AppTheme.surface,
        child: Column(
        children: [
          // Stats banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                _buildStatItem('Total', _totalTasks, Colors.white),
                const SizedBox(width: 20),
                _buildStatItem('Pending', _pendingTasks, Colors.orangeAccent),
                const SizedBox(width: 20),
                _buildStatItem('Done', _completedTasks, Colors.greenAccent),
              ],
            ),
          ),

          // Screen-time reward tasks (earn time by completing assigned tasks)
          if (_rewardRequests.isNotEmpty) _buildRewardSection(),

          // Filter tabs
          Container(
            color: Colors.transparent,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Pending', 'false'),
                const SizedBox(width: 8),
                _buildFilterChip('Completed', 'true'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _tasks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.task_outlined,
                              size: 64,
                              color: Colors.white.withOpacity(0.18),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _filter == 'all'
                                  ? 'No tasks assigned yet'
                                  : _filter == 'false'
                                      ? 'No pending tasks'
                                      : 'No completed tasks',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 16,
                              ),
                            ),
                            if (_filter == 'false' && _completedTasks > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Great job! All tasks completed! 🎉',
                                style: TextStyle(
                                  color: Colors.greenAccent.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _tasks.length,
                        itemBuilder: (context, index) {
                          return _buildTaskCard(_tasks[index]);
                        },
                      ),
          ),
        ],
        ),      // Column
      ),        // RefreshIndicator
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _filter = value);
        _loadTasks();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    return GestureDetector(
      onTap: () => _toggleTaskStatus(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: task.isCompleted
              ? const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : const LinearGradient(
                  colors: [Color(0xFF23243A), Color(0xFF1A1A1A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: task.isCompleted
                ? Colors.greenAccent.withOpacity(0.3)
                : Colors.white10,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: task.isCompleted
                      ? Colors.greenAccent
                      : Colors.white54,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (task.assignedBy != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Assigned by ${task.assignedBy}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.description,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (task.isCompleted && task.completedAt != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.greenAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Completed: ${DateFormat('MMM d, h:mm a').format(task.completedAt!)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardSection() {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final locallyDone = prefs.getLocallyDoneRewardTasks();
    final completedCount = _rewardRequests.where((r) {
      final rawId = r['task_id'];
      final int? tid = rawId is int ? rawId : rawId is String ? int.tryParse(rawId) : null;
      return r['is_task_completed'] == true ||
             r['is_task_completed_locally'] == true ||
             (tid != null && locallyDone.contains(tid));
    }).length;
    final pendingCount = _rewardRequests.length - completedCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E1065),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.videogame_asset, color: Color(0xFFC4B5FD), size: 16),
              ),
              const SizedBox(width: 8),
              const Text(
                'Earn Screen Time',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              if (completedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF78350F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.5)),
                  ),
                  child: Text(
                    '$completedCount awaiting approval',
                    style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              if (pendingCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E1065),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$pendingCount to do',
                    style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ..._rewardRequests.map((req) => _buildRewardCard(req)),
          const Divider(color: Colors.white12, height: 24),
        ],
      ),
    );
  }

  Widget _buildRewardCard(Map<String, dynamic> req) {
    // Check both backend flag AND local "done" flag
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final rawIdForLocal = req['task_id'];
    final int? tidLocal = rawIdForLocal is int ? rawIdForLocal
        : rawIdForLocal is String ? int.tryParse(rawIdForLocal) : null;
    final isCompleted = req['is_task_completed'] == true ||
        req['is_task_completed_locally'] == true ||
        (tidLocal != null && prefs.isRewardTaskLocallyDone(tidLocal));
    final taskTitle = req['task_title'] as String? ?? 'Complete assigned task';
    final taskDesc = req['task_description'] as String? ?? '';
    final appDomain = req['app_domain'] as String? ?? 'App';
    final requestedHours = (req['requested_hours'] as num? ?? 0).toDouble();
    final requestedMins = (requestedHours * 60).round();
    // task_id can be int or String
    final rawId = req['task_id'];
    final int? taskId = rawId is int
        ? rawId
        : rawId is String
            ? int.tryParse(rawId)
            : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: isCompleted
            ? const LinearGradient(
                colors: [Color(0xFF78350F), Color(0xFF451A03)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF1E0A4A), Color(0xFF2E1065)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFFFBBF24).withOpacity(0.7)
              : const Color(0xFF8B5CF6).withOpacity(0.5),
          width: isCompleted ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isCompleted
                ? const Color(0xFFFBBF24).withOpacity(0.12)
                : AppTheme.accentPurple.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isCompleted ? const Color(0xFF92400E) : const Color(0xFF3B0764),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isCompleted ? Icons.hourglass_bottom : Icons.lock_clock,
                    color: isCompleted ? const Color(0xFFFBBF24) : const Color(0xFFC4B5FD),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appDomain,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Unlock +$requestedMins mins of screen time',
                        style: TextStyle(
                          color: isCompleted
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFFC4B5FD),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFF92400E)
                        : const Color(0xFF3B0764),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCompleted
                          ? const Color(0xFFFBBF24).withOpacity(0.5)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    isCompleted ? '⏳ Awaiting' : '🔒 Locked',
                    style: TextStyle(
                      color: isCompleted
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFFC4B5FD),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Progress bar ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isCompleted ? 'Task completed!' : 'Task in progress',
                      style: TextStyle(
                        color: isCompleted
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFFC4B5FD),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isCompleted ? '100%' : '0%',
                      style: TextStyle(
                        color: isCompleted
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFFC4B5FD),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: isCompleted ? 1.0 : 0.0,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isCompleted
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF8B5CF6),
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),

          // ── Task detail box ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCompleted
                      ? const Color(0xFFFBBF24).withOpacity(0.3)
                      : const Color(0xFF8B5CF6).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCompleted ? Icons.check_box : Icons.assignment_outlined,
                    color: isCompleted
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFC4B5FD),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          taskTitle,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            decoration: isCompleted ? TextDecoration.lineThrough : null,
                            decorationColor: Colors.white54,
                          ),
                        ),
                        if (taskDesc.isNotEmpty)
                          Text(
                            taskDesc,
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Action section ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: isCompleted
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF92400E).withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFFBBF24).withOpacity(0.5)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.hourglass_empty,
                            color: Color(0xFFFBBF24), size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Waiting for parent to approve your time 🎉',
                          style: TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : taskId != null
                    ? SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _updating ? null : () => _completeRewardTask(req),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            elevation: 4,
                          ),
                          icon: _updating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text(
                              "I'm Done — Mark Complete",
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '⚙️ Your parent is setting up the task…',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}