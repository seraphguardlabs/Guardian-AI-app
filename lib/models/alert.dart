import 'package:intl/intl.dart';

enum AlertSeverity { HIGH, MEDIUM, LOW }

enum ContentType { TEXT, IMAGE, BEHAVIOR }

/// Model representing a real-time alert detected by the Guardian AI system
class Alert {
  final String id;
  final DateTime timestamp;
  final int riskScore; // 0-100
  final String summary;
  final AlertSeverity severity;
  final ContentType contentType;
  final String detectedContent;
  final String childHash;
  final String childName;
  final String? sourceApp; // Package name of the app that triggered the alert

  Alert({
    required this.id,
    required this.timestamp,
    required this.riskScore,
    required this.summary,
    required this.severity,
    required this.contentType,
    required this.detectedContent,
    required this.childHash,
    required this.childName,
    this.sourceApp,
  }) : assert(
    riskScore >= 0 && riskScore <= 100,
    'riskScore must be between 0 and 100',
  );

  /// Getter for formatted time like "2:45 PM Jan 18"
  String get formattedTime {
    return DateFormat('h:mm a MMM d').format(timestamp);
  }

  /// Getter for formatted datetime like "2:45 PM Jan 18, 2024"
  String get formattedDateTime {
    return DateFormat('h:mm a MMM d, yyyy').format(timestamp);
  }

  /// Create Alert from JSON
  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String? ?? DateTime.now().toIso8601String()),
      riskScore: json['risk_score'] as int? ?? 0,
      summary: json['summary'] as String? ?? '',
      severity: _parseSeverity(json['severity'] as String? ?? 'MEDIUM'),
      contentType: _parseContentType(json['content_type'] as String? ?? 'TEXT'),
      detectedContent: json['detected_content'] as String? ?? '',
      childHash: json['child_hash'] as String? ?? '',
      childName: json['child_name'] as String? ?? '',
      sourceApp: json['source_app'] as String?,
    );
  }

  /// Convert Alert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'risk_score': riskScore,
      'summary': summary,
      'severity': severity.toString().split('.').last,
      'content_type': contentType.toString().split('.').last,
      'detected_content': detectedContent,
      'child_hash': childHash,
      'child_name': childName,
      'source_app': sourceApp,
    };
  }

  /// Parse severity string to enum
  static AlertSeverity _parseSeverity(String severity) {
    switch (severity.toUpperCase()) {
      case 'HIGH':
        return AlertSeverity.HIGH;
      case 'MEDIUM':
        return AlertSeverity.MEDIUM;
      case 'LOW':
        return AlertSeverity.LOW;
      default:
        return AlertSeverity.MEDIUM;
    }
  }

  /// Parse content type string to enum
  static ContentType _parseContentType(String contentType) {
    switch (contentType.toUpperCase()) {
      case 'TEXT':
        return ContentType.TEXT;
      case 'IMAGE':
        return ContentType.IMAGE;
      case 'BEHAVIOR':
        return ContentType.BEHAVIOR;
      default:
        return ContentType.TEXT;
    }
  }

  /// Determine severity from risk score
  static AlertSeverity determineSeverity(int riskScore) {
    if (riskScore >= 70) {
      return AlertSeverity.HIGH;
    } else if (riskScore >= 40) {
      return AlertSeverity.MEDIUM;
    } else {
      return AlertSeverity.LOW;
    }
  }

  /// Create a copy of this Alert with modified fields
  Alert copyWith({
    String? id,
    DateTime? timestamp,
    int? riskScore,
    String? summary,
    AlertSeverity? severity,
    ContentType? contentType,
    String? detectedContent,
    String? childHash,
    String? childName,
    String? sourceApp,
  }) {
    return Alert(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      riskScore: riskScore ?? this.riskScore,
      summary: summary ?? this.summary,
      severity: severity ?? this.severity,
      contentType: contentType ?? this.contentType,
      detectedContent: detectedContent ?? this.detectedContent,
      childHash: childHash ?? this.childHash,
      childName: childName ?? this.childName,
      sourceApp: sourceApp ?? this.sourceApp,
    );
  }

  @override
  String toString() {
    return 'Alert(id: $id, timestamp: $timestamp, riskScore: $riskScore, '
        'severity: $severity, childHash: $childHash)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Alert &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          childHash == other.childHash;

  @override
  int get hashCode => id.hashCode ^ childHash.hashCode;
}
