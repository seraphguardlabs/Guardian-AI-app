/// Configuration constants for Guardian AI app

class Config {
  // Risk score threshold below which screenshots are deleted automatically
  static const int screenshotDeletionRiskThreshold = 30; // percent

  // Risk score threshold for text threat detection alerts
  static const int textThreatRiskThreshold = 60; // percent

  // ── Network ────────────────────────────────────────────────────────────────
  /// Single source of truth for the backend domain.
  /// Change this one value to point the entire app at a different server.
  static const String baseDomain = 'seraphguardlabs.com';

  /// HTTPS base URL derived from [baseDomain].
  static const String baseUrl = 'https://$baseDomain';

  /// WSS base URL derived from [baseDomain].
  static const String wsBaseUrl = 'wss://$baseDomain';

  // ── WebSocket paths (mirrors WEBSOCKET_APP_GUIDE.md pattern) ───────────
  static const String _childWsBase = '/ws/child/';
  static const String _childWsPath = '/time-extension/';
  static const String _guardianWsPath = '/ws/guardian/time-extension/';

  /// Full guardian WebSocket URL.
  static String get guardianWsUrl => '$wsBaseUrl$_guardianWsPath';

  /// Full child WebSocket URL for a given [childHash].
  static String childWsUrl(String childHash) =>
      '$wsBaseUrl$_childWsBase$childHash$_childWsPath';
}
