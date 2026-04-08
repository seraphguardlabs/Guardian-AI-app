class RiskResult {
  RiskResult({
    required this.timestampMs,
    required this.sexual,
    required this.violence,
    required this.predatoryText,
    required this.overall,
  });

  final int timestampMs;
  final double sexual;
  final double violence;
  final double predatoryText;
  final double overall;

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  factory RiskResult.fromMap(Map<dynamic, dynamic> map) {
    return RiskResult(
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
      sexual: (map['sexual'] as num?)?.toDouble() ?? 0,
      violence: (map['violence'] as num?)?.toDouble() ?? 0,
      predatoryText: (map['predatoryText'] as num?)?.toDouble() ?? 0,
      overall: (map['overall'] as num?)?.toDouble() ?? 0,
    );
  }
}
