import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';

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
  
  void _centerOnUserLocation() async {
    if (!mounted) return;
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
  }
  
  Future<void> _loadGeofences() async {
    setState(() => _isLoading = true);
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    final email = prefs.getParentEmail();
    final password = prefs.getParentPassword();
    
    if (email != null && password != null) {
      final result = await _apiService.getGeofences(email, password, widget.child.childHash);
      if (result['success'] == true) {
        setState(() {
          _geofences = result['data']['geofences'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load geofences: ${result['error']}')),
          );
        }
      }
    }
  }

  Future<void> _createGeofence() async {
    if (_newGeofenceCenter == null || _labelController.text.isEmpty) return;
    
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
        builder: (ctx) => const Center(child: CircularProgressIndicator())
      );
      
      final result = await _apiService.createGeofence(email, password, widget.child.childHash, payload);
      
      // Hide loading
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close the loading dialog
      }
      
      if (result['success'] == true) {
        if (mounted) {
          setState(() {
            _geofences.add(result['data']['geofence']);
            _newGeofenceCenter = null;
            _labelController.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Geofence created successfully')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create geofence: ${result['error']}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Geofences: ${widget.child.firstName}'),
        backgroundColor: const Color(0xFF15335C),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(0, 0), // Will update with user location or defaults
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
                // Existing Geofences
                CircleLayer(
                  circles: [
                    for (var g in _geofences)
                      CircleMarker(
                        point: LatLng(
                          (g['latitude'] as num).toDouble(),
                          (g['longitude'] as num).toDouble(),
                        ),
                        radius: (g['radius'] as num).toDouble(),
                        useRadiusInMeter: true,
                        color: Colors.blue.withOpacity(0.3),
                        borderColor: Colors.blue,
                        borderStrokeWidth: 2,
                      ),
                    // New draft geofence
                    if (_newGeofenceCenter != null)
                      CircleMarker(
                        point: _newGeofenceCenter!,
                        radius: _newGeofenceRadius,
                        useRadiusInMeter: true,
                        color: Colors.green.withOpacity(0.3),
                        borderColor: Colors.green,
                        borderStrokeWidth: 2,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (var g in _geofences)
                      Marker(
                        point: LatLng(
                          (g['latitude'] as num).toDouble(),
                          (g['longitude'] as num).toDouble(),
                        ),
                        child: const Icon(Icons.location_on, color: Colors.blue),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tap on the map to add a geofence',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (_isLoading)
                  const Center(child: LinearProgressIndicator())
                else
                  Text(
                    '${_geofences.length} active geofences',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddGeofenceDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Geofence'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(labelText: 'Label (e.g. Home, School)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Radius: '),
                      Expanded(
                        child: Slider(
                          value: _newGeofenceRadius,
                          min: 50,
                          max: 1000,
                          divisions: 19,
                          label: '${_newGeofenceRadius.round()}m',
                          onChanged: (val) {
                            setState(() => _newGeofenceRadius = val);
                            this.setState(() => _newGeofenceRadius = val); // Update parent map
                          },
                        ),
                      ),
                      Text('${_newGeofenceRadius.round()}m'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() => _newGeofenceCenter = null);
                    this.setState(() => _newGeofenceCenter = null);
                    _labelController.clear();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _labelController.text.trim().isEmpty 
                    ? null 
                    : () async {
                      // Close the input dialog first
                      Navigator.of(context).pop();
                      
                      // Then start the creation process
                      await _createGeofence();
                    },
                  child: const Text('Create'),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
