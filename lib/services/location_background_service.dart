import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Controls the native Android [LocationForegroundService] from Flutter.
///
/// The service runs independently of the Flutter engine: it keeps sending
/// the child's GPS coordinates to the backend even after the user closes
/// the app or navigates away from the child screen.
///
/// Call [start] when entering child mode and [stop] only on explicit logout.
class LocationBackgroundService {
  static const _channel =
      MethodChannel('com.example.guardian_ai/location_service');

  /// Starts (or no-ops if already running) the Android foreground service.
  static Future<bool> start() async {
    try {
      final result = await _channel.invokeMethod<bool>('startLocationService');
      debugPrint('📍 LocationBackgroundService: started');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ LocationBackgroundService: failed to start – $e');
      return false;
    }
  }

  /// Stops the Android foreground service (call only on logout).
  static Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopLocationService');
      debugPrint('📍 LocationBackgroundService: stopped');
      return result ?? false;
    } catch (e) {
      debugPrint('❌ LocationBackgroundService: failed to stop – $e');
      return false;
    }
  }

  /// Returns [true] if the native service is currently active.
  static Future<bool> isRunning() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isLocationServiceRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
