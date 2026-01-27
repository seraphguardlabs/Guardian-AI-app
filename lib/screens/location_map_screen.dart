import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Redesigned full-screen location view with:
/// - Interactive map visualization at the top
/// - Timeline list of locations at the bottom
/// - Animated path drawing
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
  late AnimationController _animationController;
  late Animation<double> _pathAnimation;
  int? _selectedLocationIndex;
  bool _showTimeline = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pathAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
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
                  height: _showTimeline ? 280 : 450,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0D1B2A),
                        Color(0xFF1B263B),
                        Color(0xFF0D1B2A),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: _pathAnimation,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _ModernLocationPainter(
                          locations: validLocations,
                          animationProgress: _pathAnimation.value,
                          selectedIndex: _selectedLocationIndex,
                        ),
                        child: GestureDetector(
                          onTapDown: (details) {
                            _handleMapTap(details, validLocations);
                          },
                        ),
                      );
                    },
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
    int index, {
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
                          ? const Color(0xFF4CAF50)
                          : isLast
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFF4ECDC4),
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: (isFirst
                                  ? const Color(0xFF4CAF50)
                                  : isLast
                                      ? const Color(0xFFFF6B6B)
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
                                  ? Icons.play_circle_outline
                                  : isLast
                                      ? Icons.flag
                                      : Icons.location_on_outlined,
                              color: isFirst
                                  ? const Color(0xFF4CAF50)
                                  : isLast
                                      ? const Color(0xFFFF6B6B)
                                      : const Color(0xFF4ECDC4),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isFirst
                                  ? 'Start'
                                  : isLast
                                      ? 'Current'
                                      : 'Point ${index + 1}',
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

/// Modern map painter with animated path and styled markers
class _ModernLocationPainter extends CustomPainter {
  final List<Map<String, dynamic>> locations;
  final double animationProgress;
  final int? selectedIndex;

  _ModernLocationPainter({
    required this.locations,
    required this.animationProgress,
    this.selectedIndex,
  });

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Draw sophisticated grid pattern
    _drawMapBackground(canvas, size);

    if (locations.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    // Collect valid points
    final points = <Offset>[];
    final lats = <double>[];
    final lngs = <double>[];

    for (final loc in locations) {
      final lat = _toDouble(loc['latitude']);
      final lng = _toDouble(loc['longitude']);
      if (lat != null && lng != null) {
        lats.add(lat);
        lngs.add(lng);
      }
    }

    if (lats.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);

    final latRange = (maxLat - minLat).abs().clamp(0.0001, double.infinity);
    final lngRange = (maxLng - minLng).abs().clamp(0.0001, double.infinity);

    const padding = 40.0;
    final width = size.width - padding * 2;
    final height = size.height - padding * 2;

    Offset project(double lat, double lng) {
      final x = ((lng - minLng) / lngRange) * width + padding;
      final y = ((maxLat - lat) / latRange) * height + padding;
      return Offset(x, y);
    }

    // Build points list (reversed for chronological order)
    for (final loc in locations.reversed) {
      final lat = _toDouble(loc['latitude']);
      final lng = _toDouble(loc['longitude']);
      if (lat != null && lng != null) {
        points.add(project(lat, lng));
      }
    }

    if (points.isEmpty) return;

    // Draw path glow (animated)
    final glowPaint = Paint()
      ..color = const Color(0xFF4ECDC4).withOpacity(0.15)
      ..strokeWidth = 16
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final pathPaint = Paint()
      ..shader = ui.Gradient.linear(
        points.first,
        points.last,
        [
          const Color(0xFF4CAF50),
          const Color(0xFF4ECDC4),
          const Color(0xFFFF6B6B),
        ],
        [0.0, 0.5, 1.0],
      )
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Animate path drawing
    final totalPoints = points.length;
    final animatedPointCount = (totalPoints * animationProgress).ceil().clamp(1, totalPoints);

    if (animatedPointCount > 1) {
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (var i = 1; i < animatedPointCount; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, pathPaint);
    }

    // Draw location markers
    for (var i = 0; i < animatedPointCount; i++) {
      final p = points[i];
      final isFirst = i == 0;
      final isLast = i == points.length - 1;
      final isSelected = selectedIndex != null && 
          (points.length - 1 - i) == selectedIndex;

      Color markerColor;
      double markerSize;

      if (isFirst) {
        markerColor = const Color(0xFF4CAF50);
        markerSize = 10;
      } else if (isLast) {
        markerColor = const Color(0xFFFF6B6B);
        markerSize = 12;
      } else {
        markerColor = const Color(0xFF4ECDC4);
        markerSize = 6;
      }

      if (isSelected) {
        markerSize += 4;
      }

      // Outer glow
      final glowMarkerPaint = Paint()
        ..color = markerColor.withOpacity(0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(p, markerSize + 4, glowMarkerPaint);

      // Center dot
      final markerPaint = Paint()
        ..color = markerColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, markerSize, markerPaint);

      // White border for start/end
      if (isFirst || isLast || isSelected) {
        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(p, markerSize, borderPaint);
      }
    }

    // Draw labels for start and end
    if (points.length >= 2 && animationProgress == 1.0) {
      _drawLabel(canvas, points.first, 'START', const Color(0xFF4CAF50));
      _drawLabel(canvas, points.last, 'NOW', const Color(0xFFFF6B6B));
    }
  }

  void _drawMapBackground(Canvas canvas, Size size) {
    // Base gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width / 2, size.height / 2),
        size.width * 0.8,
        [
          const Color(0xFF1B263B),
          const Color(0xFF0D1B2A),
        ],
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF243447)
      ..strokeWidth = 0.5;

    const gridSpacing = 40.0;
    for (double x = 0; x <= size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Corner decorations
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    _drawCorner(canvas, Offset.zero, 20, cornerPaint);
    _drawCorner(canvas, Offset(size.width, 0), 20, cornerPaint, flipX: true);
    _drawCorner(canvas, Offset(0, size.height), 20, cornerPaint, flipY: true);
    _drawCorner(canvas, Offset(size.width, size.height), 20, cornerPaint, flipX: true, flipY: true);
  }

  void _drawCorner(Canvas canvas, Offset pos, double size, Paint paint,
      {bool flipX = false, bool flipY = false}) {
    final dx = flipX ? -size : size;
    final dy = flipY ? -size : size;
    canvas.drawLine(pos, Offset(pos.dx + dx, pos.dy), paint);
    canvas.drawLine(pos, Offset(pos.dx, pos.dy + dy), paint);
  }

  void _drawLabel(Canvas canvas, Offset point, String text, Color color) {
    final textStyle = TextStyle(
      color: color,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(point.dx, point.dy - 25),
        width: textPainter.width + 12,
        height: textPainter.height + 6,
      ),
      const Radius.circular(4),
    );

    final bgPaint = Paint()..color = color.withOpacity(0.2);
    canvas.drawRRect(bgRect, bgPaint);

    final borderPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(bgRect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(
        point.dx - textPainter.width / 2,
        point.dy - 25 - textPainter.height / 2,
      ),
    );
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final textStyle = const TextStyle(
      color: Colors.white38,
      fontSize: 14,
    );
    final textSpan = TextSpan(text: 'No location data available', style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _ModernLocationPainter oldDelegate) {
    return oldDelegate.locations != locations ||
        oldDelegate.animationProgress != animationProgress ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
