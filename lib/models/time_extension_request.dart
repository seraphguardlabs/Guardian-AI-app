/// Represents the assigned_task sub-object from the API.
class AssignedTask {
  final int id;
  final String title;
  final String description;
  final bool isCompleted;
  final DateTime? completedAt;

  AssignedTask({
    required this.id,
    required this.title,
    required this.description,
    this.isCompleted = false,
    this.completedAt,
  });

  factory AssignedTask.fromJson(Map<String, dynamic> json) {
    return AssignedTask(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      isCompleted: json['is_completed'] ?? false,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'is_completed': isCompleted,
    'completed_at': completedAt?.toIso8601String(),
  };
}

class TimeExtensionRequest {
  final int requestId;
  final String childHash;
  final String childName;
  final String appDomain;
  final double requestedHours;
  final String? messageEncrypted;
  final String status; // 'pending', 'task_assigned', 'approved', 'denied', 'responded'
  final double? grantedHours;
  final DateTime created;
  final DateTime? respondedAt;
  final int? guardianId;
  final String? guardianName;
  final String? responseEncrypted;
  
  // Gamified properties – populated from the nested `assigned_task` object
  final AssignedTask? assignedTask;
  
  // Legacy flat fields for backward-compat (derived from assignedTask or raw JSON)
  final String? taskId;
  final String? taskTitle;
  final String? taskDescription;
  final bool isTaskCompleted;

  TimeExtensionRequest({
    required this.requestId,
    required this.childHash,
    required this.childName,
    required this.appDomain,
    required this.requestedHours,
    this.messageEncrypted,
    required this.status,
    this.grantedHours,
    required this.created,
    this.respondedAt,
    this.guardianId,
    this.guardianName,
    this.responseEncrypted,
    this.assignedTask,
    this.taskId,
    this.taskTitle,
    this.taskDescription,
    this.isTaskCompleted = false,
  });

  factory TimeExtensionRequest.fromJson(Map<String, dynamic> json) {
    // Parse the nested assigned_task object when present
    AssignedTask? assignedTask;
    if (json['assigned_task'] != null && json['assigned_task'] is Map) {
      assignedTask = AssignedTask.fromJson(
          Map<String, dynamic>.from(json['assigned_task'] as Map));
    }

    // Derive flat task fields from nested object or legacy flat fields
    final taskId = assignedTask?.id.toString() ?? json['task_id']?.toString();
    final taskTitle = assignedTask?.title ?? json['task_title'] as String?;
    final taskDescription = assignedTask?.description ?? json['task_description'] as String?;
    final isTaskCompleted = assignedTask?.isCompleted ?? json['is_task_completed'] ?? false;

    return TimeExtensionRequest(
      requestId: json['request_id'] ?? 0,
      childHash: json['child_hash'] ?? '',
      childName: json['child_name'] ?? 'Unknown',
      appDomain: json['app_domain'] ?? '',
      requestedHours: (json['requested_hours'] ?? 0.0).toDouble(),
      messageEncrypted: json['message_encrypted'],
      status: json['status'] ?? 'pending',
      grantedHours: json['granted_hours'] != null 
          ? (json['granted_hours'] as num).toDouble() 
          : null,
      created: DateTime.parse(json['created'] ?? DateTime.now().toIso8601String()),
      respondedAt: json['responded_at'] != null 
          ? DateTime.parse(json['responded_at']) 
          : null,
      guardianId: json['guardian_id'],
      guardianName: json['guardian_name'],
      responseEncrypted: json['response_encrypted'],
      assignedTask: assignedTask,
      taskId: taskId,
      taskTitle: taskTitle,
      taskDescription: taskDescription,
      isTaskCompleted: isTaskCompleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'request_id': requestId,
      'child_hash': childHash,
      'child_name': childName,
      'app_domain': appDomain,
      'requested_hours': requestedHours,
      'message_encrypted': messageEncrypted,
      'status': status,
      'granted_hours': grantedHours,
      'created': created.toIso8601String(),
      'responded_at': respondedAt?.toIso8601String(),
      'guardian_id': guardianId,
      'guardian_name': guardianName,
      'response_encrypted': responseEncrypted,
      if (assignedTask != null) 'assigned_task': assignedTask!.toJson(),
    };
  }

  String getAppName() {
    if (appDomain.isEmpty) return 'Unknown app';

    final parts = appDomain.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Unknown app';

    String candidate;
    if (parts.length >= 2) {
      final last = parts.last.toLowerCase();
      // If last segment is a common TLD, use the one before it
      const tlds = ['com', 'org', 'net', 'io', 'app'];
      if (tlds.contains(last)) {
        candidate = parts[parts.length - 2];
      } else {
        candidate = parts.last;
      }
    } else {
      candidate = parts.first;
    }

    // Clean up typical android/package suffixes and symbols
    candidate = candidate.replaceAll('android', '');
    candidate = candidate.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), ' ').trim();
    if (candidate.isEmpty) {
      return appDomain;
    }

    return candidate[0].toUpperCase() + candidate.substring(1);
  }

  String getFormattedTime() {
    final now = DateTime.now();
    final difference = now.difference(created);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
