import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/child.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../utils/preferences_manager.dart';

class AssignTaskScreen extends StatefulWidget {
  final Child child;

  const AssignTaskScreen({super.key, required this.child});

  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  final ApiService _apiService = ApiService();
  
  bool _loading = true;
  bool _saving = false;
  List<Task> _tasks = [];
  String _filter = 'all'; // 'all', 'true', 'false'

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.getChildTasks(
      email: email,
      password: password,
      childHash: widget.child.childHash,
      completed: _filter,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      List<Task> tasks = result['tasks'] as List<Task>;
      
      // Replace encrypted titles/descriptions with unencrypted ones from local storage
      List<Task> displayTasks = tasks.map((task) {
        final metadata = prefs.getTaskMetadataById(task.id);
        if (metadata != null) {
          // We have unencrypted metadata, use it
          return Task(
            id: task.id,
            title: metadata['title'] as String? ?? task.title,
            description: metadata['description'] as String? ?? task.description,
            isCompleted: task.isCompleted,
            completedAt: task.completedAt,
            created: task.created,
            updated: task.updated,
            assignedBy: task.assignedBy,
          );
        }
        return task; // Return original if no metadata found
      }).toList();
      
      setState(() {
        _tasks = displayTasks;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to load tasks'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showCreateTaskDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Assign New Task',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Task Title',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'e.g., Complete homework',
                    hintStyle: TextStyle(color: Colors.white30),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Detailed instructions...',
                    hintStyle: TextStyle(color: Colors.white30),
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
                if (titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a task title'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (descriptionController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a description'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                await _createTask(
                  titleController.text.trim(),
                  descriptionController.text.trim(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B4A9F),
              ),
              child: const Text('Assign Task'),
            ),
          ],
        ),
    );
  }

  Future<void> _createTask(String title, String description) async {
    setState(() => _saving = true);

    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail() ?? '';
    final password = prefs.getParentPassword() ?? '';

    final result = await _apiService.createTask(
      email: email,
      password: password,
      childHash: widget.child.childHash,
      title: title,
      description: description,
    );

    if (!mounted) return;

    setState(() => _saving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('Task assigned to ${widget.child.firstName}'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
      _loadTasks();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to create task'),
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
        title: Text(
          'Assign Tasks - ${widget.child.firstName}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        onPressed: _showCreateTaskDialog,
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
      body: Column(
        children: [
          // Filter tabs
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: task.isCompleted ? Colors.green.withOpacity(0.3) : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                color: task.isCompleted ? Colors.green : Colors.white54,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
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
    );
  }
}
