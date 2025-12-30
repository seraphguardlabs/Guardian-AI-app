class TimeExtensionRequest {
  final int requestId;
  final String childHash;
  final String childName;
  final String appDomain;
  final double requestedHours;
  final String? messageEncrypted;
  final String status; // 'pending', 'approved', 'denied', 'responded'
  final double? grantedHours;
  final DateTime created;
  final DateTime? respondedAt;
  final int? guardianId;
  final String? guardianName;
  final String? responseEncrypted;

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
  });

  factory TimeExtensionRequest.fromJson(Map<String, dynamic> json) {
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
    };
  }

  String getAppName() {
    // Extract app name from domain
    final parts = appDomain.split('.');
    if (parts.length >= 2) {
      return parts[parts.length - 1].replaceAll('android', '').trim();
    }
    return appDomain;
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
