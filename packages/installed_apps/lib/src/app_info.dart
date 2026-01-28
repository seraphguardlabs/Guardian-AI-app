import 'dart:convert';
import 'dart:typed_data';

/// Represents information about an installed application.
class AppInfo {
  /// The app's display name
  final String name;

  /// The app's package name (e.g., com.example.app)
  final String packageName;

  /// The app's version name
  final String versionName;

  /// The app's version code
  final int versionCode;

  /// App icon as bytes (decoded from base64)
  final Uint8List? icon;

  /// Whether this is a system app
  final bool isSystemApp;

  /// The app's install timestamp (milliseconds since epoch)
  final int installedTimestamp;

  AppInfo({
    required this.name,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    this.icon,
    required this.isSystemApp,
    required this.installedTimestamp,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    Uint8List? iconBytes;
    final iconBase64 = json['icon'] as String?;
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      try {
        iconBytes = base64Decode(iconBase64);
      } catch (e) {
        iconBytes = null;
      }
    }
    
    return AppInfo(
      name: json['name'] as String? ?? '',
      packageName: json['package_name'] as String? ?? '',
      versionName: json['version_name'] as String? ?? '',
      versionCode: (json['version_code'] as num?)?.toInt() ?? 0,
      icon: iconBytes,
      isSystemApp: json['is_system_app'] as bool? ?? false,
      installedTimestamp: (json['installed_timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'package_name': packageName,
      'version_name': versionName,
      'version_code': versionCode,
      'icon': icon != null ? base64Encode(icon!) : null,
      'is_system_app': isSystemApp,
      'installed_timestamp': installedTimestamp,
    };
  }

  @override
  String toString() {
    return 'AppInfo(name: $name, packageName: $packageName, versionName: $versionName)';
  }
}
