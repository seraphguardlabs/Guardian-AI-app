import 'dart:convert';

class ContentAnalysisResult {
  final int riskScore;
  final Map<String, double> categories;
  final String summary;

  ContentAnalysisResult({
    required this.riskScore,
    required this.categories,
    required this.summary,
  });

  factory ContentAnalysisResult.safe() {
    return ContentAnalysisResult(
      riskScore: 0,
      categories: {
        'explicit': 0.0,
        'violence': 0.0,
        'predatory': 0.0,
        'suggestive': 0.0,
      },
      summary: 'No risks detected.',
    );
  }

  factory ContentAnalysisResult.fromJson(Map<String, dynamic> json) {
    return ContentAnalysisResult(
      riskScore: json['risk_score'] as int? ?? 0,
      categories: (json['categories'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, (e as num).toDouble()),
          ) ??
          {},
      summary: json['summary'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'risk_score': riskScore,
        'categories': categories,
        'summary': summary,
      };
}
