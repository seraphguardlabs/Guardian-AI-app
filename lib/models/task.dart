class Task {
  final int id;
  final String title;
  final String description;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime created;
  final DateTime? updated;
  final String? assignedBy;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.isCompleted,
    this.completedAt,
    required this.created,
    this.updated,
    this.assignedBy,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      isCompleted: json['is_completed'] as bool,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      created: DateTime.parse(json['created'] as String),
      updated: json['updated'] != null
          ? DateTime.parse(json['updated'] as String)
          : null,
      assignedBy: json['assigned_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'is_completed': isCompleted,
      'completed_at': completedAt?.toIso8601String(),
      'created': created.toIso8601String(),
      'updated': updated?.toIso8601String(),
      'assigned_by': assignedBy,
    };
  }
}
