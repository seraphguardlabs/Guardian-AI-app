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
    final rawCats = json['categories'];
    final categories = <String, double>{};
    if (rawCats is Map) {
      for (final entry in rawCats.entries) {
        categories[entry.key.toString()] =
            (entry.value as num?)?.toDouble() ?? 0.0;
      }
    }
    return ContentAnalysisResult(
      riskScore: ((json['risk_score'] as num?)?.toInt() ?? 0).clamp(0, 100),
      categories: categories,
      summary: json['summary'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'risk_score': riskScore,
        'categories': categories,
        'summary': summary,
      };
}
