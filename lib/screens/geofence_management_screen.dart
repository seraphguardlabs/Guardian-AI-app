import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';
import '../utils/app_theme.dart';

class GeofenceManagementScreen extends StatefulWidget {
  final Child child;

  const GeofenceManagementScreen({
    super.key,
    required this.child,
  });

  @override
  State<GeofenceManagementScreen> createState() => _GeofenceManagementScreenState();
}

class _GeofenceManagementScreenState extends State<GeofenceManagementScreen> {
  final ApiService _apiService = ApiService();
  final MapController _mapController = MapController();
  
  List<dynamic> _geofences = [];
  bool _isLoading = true;
  
  // New geofence state
  LatLng? _newGeofenceCenter;
  double _newGeofenceRadius = 100.0;
  final TextEditingController _labelController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadGeofences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerOnUserLocation();
    });
  }
  
  Future<void> _centerOnUserLocation() async {
    if (!mounted) return;
    try {
      final locationService = Provider.of<LocationService>(context, listen: false);
      await locationService.startTracking();
      
      if (mounted && locationService.currentPosition != null) {
        _mapController.move(
          LatLng(
            locationService.currentPosition!.latitude, 
            locationService.currentPosition!.longitude
          ), 
          15.0
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }
  
  Future<void> _loadGeofences() async {
    setState(() => _isLoading = true);
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail();
    final password = prefs.getParentPassword();
    
    if (email != null && password != null) {
      try {
        final result = await _apiService.getGeofences(email, password, widget.child.childHash);
        if (mounted) {
          if (result['success'] == true) {
            setState(() {
              _geofences = result['data']['geofences'] ?? [];
              _isLoading = false;
            });
          } else {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load geofences: ${result['error']}'),
                backgroundColor: AppTheme.error,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _createGeofence() async {
    if (_newGeofenceCenter == null || _labelController.text.trim().isEmpty) return;
    
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail();
    final password = prefs.getParentPassword();
    
    if (email != null && password != null) {
      final payload = {
        'label': _labelController.text,
        'latitude': _newGeofenceCenter!.latitude,
        'longitude': _newGeofenceCenter!.longitude,
        'radius': _newGeofenceRadius,
        'trigger_on': 'both', // Default
      };
      
      // Show loading
      showDialog(
        context: context, 
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const CircularProgressIndicator(color: AppTheme.accentBlue),
          ),
        ),
      );
      
      try {
        final result = await _apiService.createGeofence(email, password, widget.child.childHash, payload);
        
        // Hide loading
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        
        if (result['success'] == true) {
          if (mounted) {
            setState(() {
              _geofences.add(result['data']['geofence']);
              _newGeofenceCenter = null;
              _labelController.clear();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Geofence created successfully'),
                backgroundColor: AppTheme.success, // Dark green
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to create geofence: ${result['error']}'),
                backgroundColor: AppTheme.error,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Geofences (${widget.child.firstName})',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(0, 0),
                  initialZoom: 13.0,
                  onTap: (tapPosition, point) {
                    setState(() {
                      _newGeofenceCenter = point;
                    });
                    _showAddGeofenceDialog();
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.guardian_ai',
                  ),
                  // Geofence Circles
                  CircleLayer(
                    circles: [
                      // Existing Geofences
                      for (var g in _geofences)
                        CircleMarker(
                          point: LatLng(
                            (g['latitude'] as num).toDouble(),
                            (g['longitude'] as num).toDouble(),
                          ),
                          radius: (g['radius'] as num? ?? 100).toDouble(),
                          useRadiusInMeter: true,
                          color: AppTheme.accentBlue.withOpacity(0.2),
                          borderColor: AppTheme.accentBlue,
                          borderStrokeWidth: 2,
                        ),
                      // Draft Geofence
                      if (_newGeofenceCenter != null)
                        CircleMarker(
                          point: _newGeofenceCenter!,
                          radius: _newGeofenceRadius,
                          useRadiusInMeter: true,
                          color: const Color(0xFF4CAF50).withOpacity(0.3),
                          borderColor: const Color(0xFF4CAF50),
                          borderStrokeWidth: 2,
                        ),
                    ],
                  ),
                  // Markers
                  MarkerLayer(
                    markers: [
                      for (var g in _geofences)
                        Marker(
                          point: LatLng(
                            (g['latitude'] as num).toDouble(),
                            (g['longitude'] as num).toDouble(),
                          ),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on, 
                            color: AppTheme.accentBlue, 
                            size: 40,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom Control Panel
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppTheme.background,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Monitoring Areas',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!_isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_geofences.length} Active',
                          style: const TextStyle(
                            color: AppTheme.accentBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(color: AppTheme.accentBlue),
                    ),
                  )
                else
                  Text(
                    'Tap on the map to create a new safe zone or restricted area for ${widget.child.firstName}.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 14,
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddGeofenceDialog() {
    setState(() => _newGeofenceRadius = 100.0);
    _labelController.clear();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        // Use a StatefulBuilder to update the slider/radius locally inside the sheet
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 24, 
                left: 24, 
                right: 24
              ),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'New Geofence',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Label Input
                    TextField(
                      controller: _labelController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Label (e.g. Home, School)',
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        filled: true,
                        fillColor: AppTheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.accentBlue, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Radius Slider
                    Row(
                      children: [
                        Text(
                          'Radius',
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                        const Spacer(),
                        Text(
                          '${_newGeofenceRadius.round()}m',
                          style: const TextStyle(
                            color: AppTheme.accentBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.accentBlue,
                        inactiveTrackColor: AppTheme.surface,
                        thumbColor: Colors.white,
                        overlayColor: AppTheme.accentBlue.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: _newGeofenceRadius,
                        min: 50,
                        max: 1000,
                        divisions: 19,
                        label: '${_newGeofenceRadius.round()}m',
                        onChanged: (val) {
                          setSheetState(() => _newGeofenceRadius = val);
                          // Also update parent state to redraw the map circle
                          this.setState(() => _newGeofenceRadius = val);
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              this.setState(() => _newGeofenceCenter = null);
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_labelController.text.trim().isNotEmpty) {
                                Navigator.pop(context);
                                _createGeofence();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentBlue,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Create',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            );
          },
        );
      },
    );
  }
}
