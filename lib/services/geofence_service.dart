import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Geofence {
  final int id;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String triggerOn; // 'entry', 'exit', 'both'
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
  
  // Create from JSON map
  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      label: json['label'] ?? 'Unknown',
      latitude: (json['latitude'] is num) ? (json['latitude'] as num).toDouble() : 0.0,
      longitude: (json['longitude'] is num) ? (json['longitude'] as num).toDouble() : 0.0,
      radiusMeters: (json['radius'] is num) ? (json['radius'] as num).toDouble() : 100.0,
      triggerOn: json['trigger_on'] ?? 'both',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }
}

class GeofenceEvent {
  final Geofence geofence;
  final String type; // 'enter' or 'exit'
  final DateTime timestamp;

  GeofenceEvent(this.geofence, this.type) : timestamp = DateTime.now();

  @override
  String toString() => '$type ${geofence.label}';
}

class GeofenceService extends ChangeNotifier {
  static const String baseUrl = 'https://seraphguardlabs.com';
  
  final List<Geofence> _geofences = [];
  final Set<int> _insideGeofenceIds = {}; // Track which fences we are currently inside
  
  // Public access to geofences
  List<Geofence> get geofences => List.unmodifiable(_geofences);

  /// Load geofences from the server
  Future<void> loadGeofences(String email, String password, String childHash) async {
    final url = Uri.parse('$baseUrl/location_tracking/api/mobile/child/$childHash/geofences/');
    
    try {
      debugPrint('📍 Loading geofences for child: $childHash');
      final response = await http.get(
        url,
        headers: {
          'X-Email': email,
          'X-Password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'ok' || data['success'] == true) {
          final List<dynamic> list = data['geofences'] ?? [];
          _geofences.clear();
          // Reset inside state on reload as fences changed
          _insideGeofenceIds.clear(); 
          
          for (var item in list) {
            _geofences.add(Geofence.fromJson(item));
          }
          
          debugPrint('📍 Loaded ${_geofences.length} geofences');
          notifyListeners();
        }
      } else {
        debugPrint('❌ Failed to load geofences: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error loading geofences: $e');
    }
  }

  /// Add a new geofence via API
  Future<bool> addGeofence({
    required String email,
    required String password,
    required String childHash,
    required String label,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    String triggerOn = 'both',
  }) async {
    final url = Uri.parse('$baseUrl/location_tracking/api/mobile/child/$childHash/geofences/');
    
    try {
      final payload = {
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radiusMeters,
        'trigger_on': triggerOn,
      };
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Email': email,
          'X-Password': password,
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Add to local list immediately
        if (data['geofence'] != null) {
          _geofences.add(Geofence.fromJson(data['geofence']));
          notifyListeners();
        } else {
          // If geofence object not returned, reload list
          await loadGeofences(email, password, childHash);
        }
        
        return true;
      } else {
        debugPrint('❌ Failed to add geofence: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error adding geofence: $e');
      return false;
    }
  }

  /// Remove geofence via API
  Future<bool> removeGeofence(String email, String password, String childHash, int geofenceId) async {
    // Assuming DELETE endpoint exists or implemented similarly
    // If not, we just remove locally for UI responsiveness and wait for backend specific endpoint
    // The current docs didn't specify DELETE, so I'll just remove locally for now and mark TODO
    
    // TODO: Implement actual API DELETE call if endpoint is available
    // For now, we simulate removal
    _geofences.removeWhere((g) => g.id == geofenceId);
    _insideGeofenceIds.remove(geofenceId);
    notifyListeners();
    return true;
  }

  /// Check current location against all geofences
  /// Returns a list of events (Enter/Exit) that occurred
  List<GeofenceEvent> checkLocation(double latitude, double longitude) {
    final events = <GeofenceEvent>[];
    
    for (final g in _geofences) {
      final wasInside = _insideGeofenceIds.contains(g.id);
      final dist = _distanceMeters(g.latitude, g.longitude, latitude, longitude);
      final isNowInside = dist <= g.radiusMeters;
      
      if (!wasInside && isNowInside) {
        // ENTER Event
        _insideGeofenceIds.add(g.id);
        if (g.triggerOn == 'entry' || g.triggerOn == 'both') {
          debugPrint('📍 Geofence ENTER: ${g.label}');
          events.add(GeofenceEvent(g, 'enter'));
        }
      } else if (wasInside && !isNowInside) {
        // EXIT Event
        _insideGeofenceIds.remove(g.id);
        if (g.triggerOn == 'exit' || g.triggerOn == 'both') {
          debugPrint('📍 Geofence EXIT: ${g.label}');
          events.add(GeofenceEvent(g, 'exit'));
        }
      }
    }
    
    if (events.isNotEmpty) notifyListeners();
    return events;
  }

  /// Trigger geofence event via API
  Future<bool> triggerGeofenceEvent(String childHash, GeofenceEvent event) async {
    final url = Uri.parse('$baseUrl/location_tracking/api/ingest/'); // Assuming relative to location_tracking app
    
    try {
      final payload = {
        'child_hash': childHash,
        'data_type': 'geofence_event',
        'payload': {
          'geofence_id': event.geofence.id,
          'event_type': event.type,
          'timestamp': event.timestamp.toUtc().toIso8601String(),
        }
      };
      
      debugPrint('📍 Sending geofence event: $url');
      debugPrint('   Payload: $payload');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Child-Hash': childHash,
        },
        body: jsonEncode(payload),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Geofence event sent successfully');
        return true;
      } else {
        debugPrint('❌ Failed to send geofence event: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error sending geofence event: $e');
      return false;
    }
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
}