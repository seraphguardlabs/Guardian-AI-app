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
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    debugPrint('📋 ========== MY_TASKS_SCREEN LOAD TASKS ==========');
    debugPrint('📋 Child Hash: ${childHash.isEmpty ? "EMPTY" : childHash}');
    debugPrint('📋 Email: ${email.isEmpty ? "EMPTY" : email}');
    debugPrint('📋 Password: ${password.isEmpty ? "EMPTY" : "[${password.length} chars]"}');
    debugPrint('📋 Filter: $_filter');

    if (childHash.isEmpty || email.isEmpty || password.isEmpty) {
      debugPrint('📋 ❌ CANNOT LOAD TASKS:');
      debugPrint('📋    - Child Hash empty: ${childHash.isEmpty}');
      debugPrint('📋    - Email empty: ${email.isEmpty}');
      debugPrint('📋    - Password empty: ${password.isEmpty}');
      setState(() => _loading = false);
      return;
    }

    debugPrint('📋 ✅ Credentials OK, calling API...');
    final result = await _apiService.getMyTasks(
      childHash: childHash,
      email: email,
      password: password,
      completed: _filter,
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
        // Try to decrypt title and description
        final decryptedTitle = encryptionService.decryptWithPrivateKey(task.title);
        final decryptedDescription = encryptionService.decryptWithPrivateKey(task.description);
        
        // If decryption succeeds, create new task with decrypted data
        // If decryption fails (returns null), keep the original (could be plaintext)
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
        return task; // Return original if no decryption needed
      }).toList();
      
      debugPrint('📋 ✅ Decryption complete. Setting state with ${decryptedTasks.length} tasks');
      setState(() {
        _tasks = decryptedTasks;
        _totalTasks = result['total_tasks'] as int;
        _pendingTasks = result['pending_tasks'] as int;
        _completedTasks = result['completed_tasks'] as int;
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
    final password = prefs.getChildPassword() ?? ''; // Empty string if not set

    final result = task.isCompleted
        ? await _apiService.incompleteTask(
            childHash: childHash,
            password: password,
            taskId: task.id,
          )
        : await _apiService.completeTask(
            childHash: childHash,
            password: password,
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
              Text(result['message'] ?? 'Task updated'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
      _loadTasks();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to update task'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                  color: Colors.orange,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Stats banner
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _buildStatItem('Total', _totalTasks, Colors.blue),
                const SizedBox(width: 20),
                _buildStatItem('Pending', _pendingTasks, Colors.orange),
                const SizedBox(width: 20),
                _buildStatItem('Done', _completedTasks, Colors.green),
              ],
            ),
          ),

          // Filter tabs
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                    child: CircularProgressIndicator(color: Colors.orange),
                  )
                : _tasks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.task_outlined,
                              size: 64,
                              color: Colors.white.withOpacity(0.3),
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
                                  color: Colors.green.withOpacity(0.7),
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
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 12,
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5B4A9F) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF5B4A9F) : Colors.white30,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    return GestureDetector(
      onTap: () => _toggleTaskStatus(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: task.isCompleted
                ? Colors.green.withOpacity(0.3)
                : Colors.white10,
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
                      ? Colors.green
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
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Completed: ${DateFormat('MMM d, h:mm a').format(task.completedAt!)}',
                          style: const TextStyle(
                            color: Colors.green,
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
