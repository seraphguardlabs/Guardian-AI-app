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

  Map<String, dynamic> toJson() => {
        'risk_score': riskScore,
        'categories': categories,
        'summary': summary,
      };
}
