import 'dart:math';

import 'package:flutter/foundation.dart';

class Geofence {
  final int id;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String triggerOn;
  final DateTime createdAt;

  Geofence({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.triggerOn = 'both',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class GeofenceService extends ChangeNotifier {
  final List<Geofence> _geofences = [];
  int _nextId = 1;

  List<Geofence> get geofences => List.unmodifiable(_geofences);

  Geofence addGeofence({
    required String label,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    String triggerOn = 'both',
  }) {
    final g = Geofence(
      id: _nextId++,
      label: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      triggerOn: triggerOn,
    );
    _geofences.add(g);
    notifyListeners();
    return g;
  }

  bool removeGeofence(int id) {
    final startLen = _geofences.length;
    _geofences.removeWhere((g) => g.id == id);
    final removed = _geofences.length < startLen;
    if (removed) notifyListeners();
    return removed;
  }

  // Haversine distance in meters
  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double deg) => deg * pi / 180.0;

  /// Return list of geofence ids that contain the point
  List<Geofence> geofencesContainingPoint(double latitude, double longitude) {
    final results = <Geofence>[];
    for (final g in _geofences) {
      final d = _distanceMeters(g.latitude, g.longitude, latitude, longitude);
      if (d <= g.radiusMeters) results.add(g);
    }
    return results;
  }

  /// Quick utility to check if a specific geofence id contains the point
  bool isInside(int geofenceId, double latitude, double longitude) {
    final g = _geofences.firstWhere((e) => e.id == geofenceId, orElse: () => throw ArgumentError('Geofence not found'));
    final d = _distanceMeters(g.latitude, g.longitude, latitude, longitude);
    return d <= g.radiusMeters;
  }
}
