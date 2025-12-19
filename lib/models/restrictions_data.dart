/// Model for app restrictions received from server
class AppRestriction {
  final String packageName;
  final double allowedHours; // 0 means fully blocked

  AppRestriction({
    required this.packageName,
    required this.allowedHours,
  });

  bool get isFullyBlocked => allowedHours == 0;

  factory AppRestriction.fromJson(String packageName, dynamic allowedHours) {
    return AppRestriction(
      packageName: packageName,
      allowedHours: (allowedHours is num) ? allowedHours.toDouble() : 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      packageName: allowedHours,
    };
  }
}

/// Restrictions data from server
class RestrictionsData {
  final Map<String, double> restrictedApps; // packageName -> allowedHours

  RestrictionsData({required this.restrictedApps});

  factory RestrictionsData.fromJson(Map<String, dynamic> json) {
    final apps = <String, double>{};
    
    json.forEach((key, value) {
      if (value is num) {
        apps[key] = value.toDouble();
      }
    });

    return RestrictionsData(restrictedApps: apps);
  }

  Map<String, dynamic> toJson() {
    return restrictedApps;
  }

  List<AppRestriction> get restrictions {
    return restrictedApps.entries
        .map((e) => AppRestriction(
              packageName: e.key,
              allowedHours: e.value,
            ))
        .toList();
  }

  /// Get restriction for a specific app
  AppRestriction? getRestriction(String packageName) {
    final hours = restrictedApps[packageName];
    if (hours == null) return null;
    
    return AppRestriction(
      packageName: packageName,
      allowedHours: hours,
    );
  }

  /// Check if an app is restricted
  bool isRestricted(String packageName) {
    return restrictedApps.containsKey(packageName);
  }

  /// Check if an app is fully blocked (0 hours)
  bool isFullyBlocked(String packageName) {
    final hours = restrictedApps[packageName];
    return hours != null && hours == 0;
  }
}
