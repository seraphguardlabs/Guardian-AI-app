import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../utils/preferences_manager.dart';

class RewardTask {
  final String id;
  final String title;
  final String description;
  bool isCompleted;
  DateTime? completedAt;

  RewardTask({
    required this.id,
    required this.title,
    required this.description,
    this.isCompleted = false,
    this.completedAt,
  });

  factory RewardTask.fromJson(Map<String, dynamic> json) {
    return RewardTask(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      isCompleted: json['is_completed'] ?? false,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
    );
  }
}

class GamifiedPermissionService extends ChangeNotifier {
  List<RewardTask> _suggested = [];
  bool _isLoading = false;

  List<RewardTask> get suggestedTasks => List.unmodifiable(_suggested);
  bool get isLoading => _isLoading;

  /// Fetch suggested reward tasks from API
  Future<void> fetchSuggestedTasks() async {
    if (_suggested.isNotEmpty) return; // Don't fetch if already loaded
    
    _isLoading = true;
    notifyListeners();

    try {
      final url = Uri.parse('${Config.baseUrl}/api/mobile/time-extension-requests/suggested-tasks/');
      debugPrint('🎲 Fetching suggested tasks from $url');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok' && data['suggested_tasks'] != null) {
          final List<dynamic> tasksJson = data['suggested_tasks'];
          _suggested = tasksJson.map((json) => RewardTask.fromJson(json)).toList();
          debugPrint('✅ Loaded ${_suggested.length} suggested tasks');
        }
      } else {
        debugPrint('❌ Failed to fetch suggested tasks: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching suggested tasks: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addCustomTask(String id, String title, String description) {
    _suggested.add(RewardTask(id: id, title: title, description: description));
    notifyListeners();
  }

  /// Assign a task to a request via API. Returns true on success.
  /// Per API docs: POST /api/mobile/time-extension-requests/<request_id>/assign-task/
  /// Body: { "task_id": "play_chess" } OR { "title": "...", "description": "..." }
  Future<bool> assignTaskToRequest({
    required int requestId,
    required String? taskId, // ID from suggested tasks 
    bool isCustom = false,
    String? title,
    String? description,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await PreferencesManager.init();
      final email = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';

      final url = Uri.parse('${Config.baseUrl}/api/mobile/time-extension-requests/$requestId/assign-task/');
      
      Map<String, dynamic> body;
      if (isCustom) {
        body = {
          'title': title,
          'description': description,
        };
      } else {
        body = {
          'task_id': taskId,
        };
      }

      debugPrint('🎲 Assigning task to request $requestId: $body');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Task assigned successfully');
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        debugPrint('❌ Failed to assign task: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error assigning task: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }
  
  /// Child marks a task complete via API
  Future<bool> markTaskComplete(String childHash, String taskId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Note: The task ID here refers to the actual Task ID on the server, not the suggested task ID
      // However, for suggested tasks, the flow might be slightly different.
      // Based on docs: POST /api/mobile/child/<child_hash>/tasks/<task_id>/complete/
      
      final url = Uri.parse('${Config.baseUrl}/api/mobile/child/$childHash/tasks/$taskId/complete/');
      debugPrint('✅ Marking task $taskId as complete for child $childHash');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Child-Hash': childHash,
        },
      );
      
      if (response.statusCode == 200) {
        debugPrint('✅ Task marked complete');
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        debugPrint('❌ Failed to complete task: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error completing task: $e');
    }
    
    _isLoading = false;
    notifyListeners();
    return false;
  }
}
