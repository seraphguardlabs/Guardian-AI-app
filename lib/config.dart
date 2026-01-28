/// Configuration constants for Guardian AI app

class Config {
  // Risk score threshold below which screenshots are deleted automatically
  static const int screenshotDeletionRiskThreshold = 30; // percent

  // Risk score threshold for text threat detection alerts
  static const int textThreatRiskThreshold = 60; // percent
}
