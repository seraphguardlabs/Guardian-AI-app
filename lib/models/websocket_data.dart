/// Model classes for WebSocket data transmission

class ScreenTimeData {
  final String date;
  final int totalScreenTime; // in seconds
  final Map<String, Map<String, int>> appWiseData; // packageName -> hour -> seconds
  final int? timezoneOffsetMinutes; // Local offset from UTC in minutes
  final String? timezoneName;

  ScreenTimeData({
    required this.date,
    required this.totalScreenTime,
    required this.appWiseData,
    this.timezoneOffsetMinutes,
    this.timezoneName,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'total_screen_time': totalScreenTime,
      'app_wise_data': appWiseData,
      if (timezoneOffsetMinutes != null) 'timezone_offset_minutes': timezoneOffsetMinutes,
      if (timezoneName != null) 'timezone_name': timezoneName,
    };
  }

  factory ScreenTimeData.fromJson(Map<String, dynamic> json) {
    final appWiseData = <String, Map<String, int>>{};
    final rawAppData = json['app_wise_data'] as Map<String, dynamic>? ?? {};
    
    rawAppData.forEach((packageName, hourData) {
      final hourMap = <String, int>{};
      (hourData as Map<String, dynamic>).forEach((hour, seconds) {
        hourMap[hour] = seconds as int;
      });
      appWiseData[packageName] = hourMap;
    });

    return ScreenTimeData(
      date: json['date'] as String,
      totalScreenTime: json['total_screen_time'] as int,
      appWiseData: appWiseData,
      timezoneOffsetMinutes: json['timezone_offset_minutes'] as int?,
      timezoneName: json['timezone_name'] as String?,
    );
  }
}

class LocationData {
  final String timestamp; // ISO 8601 format
  final double latitude;
  final double longitude;

  LocationData({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      timestamp: json['timestamp'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

class SiteAccessLog {
  final String timestamp; // ISO 8601 format
  final String url;
  final bool accessed; // true if allowed, false if blocked

  SiteAccessLog({
    required this.timestamp,
    required this.url,
    required this.accessed,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'url': url,
      'accessed': accessed,
    };
  }

  factory SiteAccessLog.fromJson(Map<String, dynamic> json) {
    return SiteAccessLog(
      timestamp: json['timestamp'] as String,
      url: json['url'] as String,
      accessed: json['accessed'] as bool,
    );
  }
}

class SiteAccessData {
  final List<SiteAccessLog> logs;

  SiteAccessData({required this.logs});

  Map<String, dynamic> toJson() {
    return {
      'logs': logs.map((log) => log.toJson()).toList(),
    };
  }

  factory SiteAccessData.fromJson(Map<String, dynamic> json) {
    final logsList = (json['logs'] as List? ?? [])
        .map((log) => SiteAccessLog.fromJson(log as Map<String, dynamic>))
        .toList();
    
    return SiteAccessData(logs: logsList);
  }
}
