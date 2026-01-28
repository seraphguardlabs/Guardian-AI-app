import 'dart:async';
import 'package:flutter/services.dart';
import 'app_info.dart';

export 'app_info.dart';

/// A Flutter plugin to get information about installed apps on Android
class InstalledApps {
  static const MethodChannel _channel = MethodChannel('installed_apps');

  /// Get a list of all installed apps
  /// 
  /// If [excludeSystemApps] is true, system apps will be filtered out.
  /// If [withIcon] is true, the result will include base64 encoded app icons.
  static Future<List<AppInfo>> getInstalledApps({
    bool excludeSystemApps = true,
    bool withIcon = true,
    String? packageNamePrefix,
  }) async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod(
        'getInstalledApps',
        {
          'exclude_system_apps': excludeSystemApps,
          'with_icon': withIcon,
          'package_name_prefix': packageNamePrefix,
        },
      );

      if (result == null) return [];

      return result
          .map((app) => AppInfo.fromJson(Map<String, dynamic>.from(app as Map)))
          .toList();
    } on PlatformException catch (e) {
      throw Exception('Failed to get installed apps: ${e.message}');
    }
  }

  /// Get information about a specific app by package name
  static Future<AppInfo?> getAppInfo(String packageName) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'getAppInfo',
        {'package_name': packageName},
      );

      if (result == null) return null;

      return AppInfo.fromJson(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw Exception('Failed to get app info: ${e.message}');
    }
  }

  /// Check if an app is installed
  static Future<bool> isAppInstalled(String packageName) async {
    try {
      final bool? result = await _channel.invokeMethod(
        'isAppInstalled',
        {'package_name': packageName},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Launch an app by package name
  static Future<bool> startApp(String packageName) async {
    try {
      final bool? result = await _channel.invokeMethod(
        'startApp',
        {'package_name': packageName},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Open app settings for a specific package
  static Future<bool> openSettings(String packageName) async {
    try {
      final bool? result = await _channel.invokeMethod(
        'openSettings',
        {'package_name': packageName},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
