import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/time_extension_request.dart';
import '../services/gamified_permission_service.dart';
import '../utils/app_theme.dart';

class AssignTaskDialog extends StatefulWidget {
  final TimeExtensionRequest request;

  const AssignTaskDialog({super.key, required this.request});

  @override
  State<AssignTaskDialog> createState() => _AssignTaskDialogState();
}

class _AssignTaskDialogState extends State<AssignTaskDialog> {
  String? _selectedTaskId;
  bool _isCustom = false;
  final TextEditingController _customTitleController = TextEditingController();
  final TextEditingController _customDescController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamifiedPermissionService>().fetchSuggestedTasks();
    });
  }

  @override
  void dispose() {
    _customTitleController.dispose();
    _customDescController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GamifiedPermissionService>(
      builder: (context, service, _) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Assign Reward Task', style: TextStyle(color: Colors.white)),
          content: service.isLoading && service.suggestedTasks.isEmpty
              ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
              : SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select a task for the child to complete before getting screen time.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        
                        // Suggested Tasks
                        ...service.suggestedTasks.map((task) => RadioListTile<String>(
                          title: Text(task.title, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(task.description, style: const TextStyle(color: Colors.white54)),
                          value: task.id,
                          groupValue: _isCustom ? null : _selectedTaskId,
                          onChanged: (value) {
                            setState(() {
                              _selectedTaskId = value;
                              _isCustom = false;
                            });
                          },
                          activeColor: const Color(0xFF5B4A9F),
                          contentPadding: EdgeInsets.zero,
                        )),
                        
                        // Custom Task Option
                        RadioListTile<String>(
                          title: const Text('Custom Task', style: TextStyle(color: Colors.white)),
                          value: 'custom',
                          groupValue: _isCustom ? 'custom' : null,
                          onChanged: (value) {
                            setState(() {
                              _isCustom = true;
                              _selectedTaskId = null;
                            });
                          },
                          activeColor: const Color(0xFF5B4A9F),
                          contentPadding: EdgeInsets.zero,
                        ),
                        
                        if (_isCustom) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _customTitleController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Task Title',
                              labelStyle: const TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.white24),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Color(0xFF5B4A9F)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _customDescController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Description',
                              labelStyle: const TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.white24),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Color(0xFF5B4A9F)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: service.isLoading 
                  ? null 
                  : () async {
                      if (!_isCustom && _selectedTaskId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a task')),
                        );
                        return;
                      }
                      
                      if (_isCustom && _customTitleController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a task title')),
                        );
                        return;
                      }

                      final success = await service.assignTaskToRequest(
                        requestId: widget.request.requestId,
                        taskId: _isCustom ? null : _selectedTaskId,
                        isCustom: _isCustom,
                        title: _customTitleController.text,
                        description: _customDescController.text,
                      );

                      if (success && mounted) {
                        Navigator.pop(context, true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Task assigned successfully'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B4A9F),
                disabledBackgroundColor: Colors.grey,
              ),
              child: service.isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Assign'),
            ),
          ],
        );
      },
    );
  }
}
