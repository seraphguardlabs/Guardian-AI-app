import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../services/api_service.dart';
import '../services/encryption_service.dart';
import '../utils/preferences_manager.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  final ApiService _apiService = ApiService();
  
  bool _loading = true;
  bool _updating = false;
  List<Task> _tasks = [];
  String _filter = 'all'; // 'all', 'true', 'false'
  int _totalTasks = 0;
  int _pendingTasks = 0;
  int _completedTasks = 0;

  @override
  void initState() {
    super.initState();
    _loadTasks();
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
          backgroundColor: Colors.red,
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
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task status updated.'),
          backgroundColor: Colors.green,
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
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
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
                  color: Color(0xFF1A3C8B),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Stats banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A3C8B), Color(0xFF0D1F4A)],
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
          // Task list
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF1A3C8B)),
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
      ),
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
          color: isSelected ? const Color(0xFF1A3C8B) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF1A3C8B) : Colors.white24,
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
                  colors: [Color(0xFF1A3C8B), Color(0xFF0D1F4A)],
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
}
