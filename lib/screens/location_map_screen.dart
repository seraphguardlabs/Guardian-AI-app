import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Redesigned full-screen location view with:
/// - Interactive map visualization (OpenStreetMap)
/// - Timeline list of locations at the bottom
/// - Path visualization with polylines
/// - Location details on tap
class LocationMapScreen extends StatefulWidget {
  final List<Map<String, dynamic>> locations;
  final DateTime? lastUpdated;

  const LocationMapScreen({
    super.key,
    required this.locations,
    this.lastUpdated,
  });

  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen>
    with SingleTickerProviderStateMixin {
  late MapController _mapController;
  int? _selectedLocationIndex;
  bool _showTimeline = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return 'Unknown';
    }
  }

  String _formatDate(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }

  String _getLastUpdatedText() {
    if (widget.lastUpdated != null) {
      return DateFormat('MMM d, h:mm a').format(widget.lastUpdated!.toLocal());
    } else if (widget.locations.isNotEmpty &&
        widget.locations.first['timestamp'] is String) {
      try {
        final dt = DateTime.parse(widget.locations.first['timestamp'] as String)
            .toLocal();
        return DateFormat('MMM d, h:mm a').format(dt);
      } catch (_) {}
    }
    return 'No data';
  }

  @override
  Widget build(BuildContext context) {
    final validLocations = widget.locations.where((loc) {
      final lat = _toDouble(loc['latitude']);
      final lng = _toDouble(loc['longitude']);
      return lat != null && lng != null;
    }).toList();

    // Convert to latlong points
    final points = validLocations.map((loc) {
      return LatLng(_toDouble(loc['latitude'])!, _toDouble(loc['longitude'])!);
    }).toList();

    // Default center if no points
    final initialCenter = points.isNotEmpty ? points.first : const LatLng(0, 0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: CustomScrollView(
        slivers: [
          // Custom App Bar
          SliverAppBar(
            backgroundColor: const Color(0xFF0A0A0F),
            elevation: 0,
            pinned: true,
            expandedHeight: 60,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Location History',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _showTimeline ? Icons.map : Icons.timeline,
                  color: Colors.white70,
                ),
                onPressed: () {
                  setState(() {
                    _showTimeline = !_showTimeline;
                  });
                },
              ),
            ],
          ),

          // Stats Summary
          SliverToBoxAdapter(
            child: _buildStatsSummary(validLocations),
          ),

          // Map View
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  height: _showTimeline ? 320 : 500,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B263B),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: points.isNotEmpty ? 15.0 : 2.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.guardian_ai.app',
                        // Add a dark filter to match the app theme
                        tileBuilder: (context, tileWidget, tile) {
                          return ColorFiltered(
                            colorFilter: const ColorFilter.matrix([
                              -1, 0, 0, 0, 255,
                              0, -1, 0, 0, 255,
                              0, 0, -1, 0, 255,
                              0, 0, 0, 1, 0,
                            ]),
                            child: tileWidget,
                          );
                        },
                      ),
                      if (points.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: points,
                              strokeWidth: 4.0,
                              color: const Color(0xFF4ECDC4),
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: List.generate(points.length, (index) {
                          final point = points[index];
                          final isFirst = index == 0;
                          final isLast = index == points.length - 1;
                          final isSelected = _selectedLocationIndex == index;

                          return Marker(
                            point: point,
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedLocationIndex = isSelected ? null : index;
                                });
                              },
                              child: Column(
                                children: [
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _formatTimestamp(validLocations[index]['timestamp']),
                                        style: const TextStyle(color: Colors.white, fontSize: 8),
                                      ),
                                    ),
                                  Icon(
                                    isFirst
                                        ? Icons.my_location
                                        : isLast
                                            ? Icons.location_on
                                            : Icons.circle,
                                    size: isSelected ? 30 : (isFirst || isLast ? 24 : 12),
                                    color: isFirst
                                        ? Colors.red
                                        : isLast
                                            ? Colors.green
                                            : const Color(0xFF4ECDC4),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Timeline or Details
          if (_showTimeline) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Location Timeline',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${validLocations.length} locations',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (validLocations.isEmpty)
              SliverToBoxAdapter(child: _buildEmptyState())
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final loc = validLocations[index];
                    final isFirst = index == 0;
                    final isLast = index == validLocations.length - 1;
                    final isSelected = _selectedLocationIndex == index;
                    return _buildTimelineItem(
                      loc,
                      index,
                      validLocations.length,
                      isFirst: isFirst,
                      isLast: isLast,
                      isSelected: isSelected,
                    );
                  },
                  childCount: validLocations.length,
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildStatsSummary(List<Map<String, dynamic>> locations) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF101722),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: Icons.location_on,
              value: '${locations.length}',
              label: 'Points',
              color: const Color(0xFF4ECDC4),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.white12,
            ),
            _buildStatItem(
              icon: Icons.access_time,
              value: _getLastUpdatedText(),
              label: 'Last Update',
              color: const Color(0xFFFF6B6B),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.white12,
            ),
            _buildStatItem(
              icon: Icons.shield,
              value: locations.isEmpty ? 'No Data' : 'Active',
              label: 'Status',
              color: locations.isEmpty
                  ? Colors.grey
                  : const Color(0xFF4CAF50),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: const Color(0xFF101722),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_off,
              size: 40,
              color: Colors.white30,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Location Data',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Location tracking will appear here once\nthe child\'s device starts sharing location',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    Map<String, dynamic> location,
    int index,
    int totalCount, {
    required bool isFirst,
    required bool isLast,
    required bool isSelected,
  }) {
    final lat = _toDouble(location['latitude']) ?? 0;
    final lng = _toDouble(location['longitude']) ?? 0;
    final timestamp = location['timestamp'] as String?;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLocationIndex = isSelected ? null : index;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline line and dot
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  if (!isFirst)
                    Container(
                      width: 2,
                      height: 20,
                      color: const Color(0xFF4ECDC4).withOpacity(0.3),
                    ),
                  Container(
                    width: isSelected ? 16 : 12,
                    height: isSelected ? 16 : 12,
                    decoration: BoxDecoration(
                      color: isFirst
                          ? const Color(0xFFFF6B6B)
                          : isLast
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF4ECDC4),
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: (isFirst
                                  ? const Color(0xFFFF6B6B)
                                  : isLast
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFF4ECDC4))
                              .withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 40,
                      color: const Color(0xFF4ECDC4).withOpacity(0.3),
                    ),
                ],
              ),
            ),
            // Location card
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1B263B)
                      : const Color(0xFF101722),
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? Border.all(color: const Color(0xFF4ECDC4), width: 1)
                      : Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isFirst
                                  ? Icons.my_location
                                  : isLast
                                      ? Icons.flag
                                      : Icons.location_on_outlined,
                              color: isFirst
                                  ? const Color(0xFFFF6B6B)
                                  : isLast
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFF4ECDC4),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isFirst
                                  ? 'Current'
                                  : isLast
                                      ? 'Start'
                                      : 'Point ${totalCount - index}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _formatTimestamp(timestamp),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 8),
                      Text(
                        _formatDate(timestamp),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMapTap(TapDownDetails details, List<Map<String, dynamic>> locations) {
    if (locations.isEmpty) return;
    // Could implement interactive map selection here
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

