import 'package:flutter/foundation.dart';

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
}

class GamifiedPermissionService extends ChangeNotifier {
  final List<RewardTask> _suggested = [
    RewardTask(id: 'play_chess', title: 'Play Chess', description: 'Engage in a game of chess'),
    RewardTask(id: 'exercise', title: 'Exercise for 20 minutes', description: 'Do some light stretching or cardio'),
    RewardTask(id: 'read', title: 'Read Newspaper', description: 'Read at least three major articles'),
  ];

  List<RewardTask> get suggestedTasks => List.unmodifiable(_suggested);

  void addCustomTask(String id, String title, String description) {
    _suggested.add(RewardTask(id: id, title: title, description: description));
    notifyListeners();
  }

  /// Assign a task to a request (stub). Returns true on success.
  Future<bool> assignTaskToRequest({required String requestId, required String taskId, bool isCustom = false, String? title, String? description}) async {
    // This is a local stub. In the full app this would call the backend API.
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  /// Child marks a task complete
  void markTaskComplete(String taskId) {
    final t = _suggested.firstWhere((s) => s.id == taskId, orElse: () => throw ArgumentError('Task not found'));
    t.isCompleted = true;
    t.completedAt = DateTime.now();
    notifyListeners();
  }
}
