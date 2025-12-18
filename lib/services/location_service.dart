import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class LocationService extends ChangeNotifier {
  Position? _currentPosition;
  String _locationStatus = 'Initializing...';
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isTracking = false;

  Position? get currentPosition => _currentPosition;
  String get locationStatus => _locationStatus;
  bool get isTracking => _isTracking;

  // Location settings for continuous tracking
  final LocationSettings _locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // Update every 10 meters
  );

  Future<void> startTracking() async {
    if (_isTracking) return;

    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _locationStatus = 'Location services are disabled';
      notifyListeners();
      return;
    }

    // Check permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _locationStatus = 'Location permission denied';
        notifyListeners();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _locationStatus = 'Location permission permanently denied';
      notifyListeners();
      return;
    }

    // Start continuous location updates
    _isTracking = true;
    _locationStatus = 'Tracking location...';
    notifyListeners();

    try {
      // Get initial position
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _locationStatus = 'Location found';
      notifyListeners();

      // Start listening to position stream
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: _locationSettings,
      ).listen(
        (Position position) {
          _currentPosition = position;
          _locationStatus = 'Location updated';
          notifyListeners();
        },
        onError: (error) {
          _locationStatus = 'Error: $error';
          notifyListeners();
        },
      );
    } catch (e) {
      _locationStatus = 'Error getting location: $e';
      _isTracking = false;
      notifyListeners();
    }
  }

  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isTracking = false;
    _locationStatus = 'Tracking stopped';
    notifyListeners();
  }

  String getLocationString() {
    if (_currentPosition == null) {
      return 'Location unavailable';
    }
    return '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}';
  }

  String getLocationWithAccuracy() {
    if (_currentPosition == null) {
      return 'Location unavailable';
    }
    return 'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}\n'
        'Lon: ${_currentPosition!.longitude.toStringAsFixed(6)}\n'
        'Accuracy: ±${_currentPosition!.accuracy.toStringAsFixed(1)}m';
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
