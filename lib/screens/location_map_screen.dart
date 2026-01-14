import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Full-screen location view that renders the child's recent
/// locations as an orange path over a dark "map" background.
///
/// This uses a pure Flutter CustomPainter so it does not rely on
/// native map SDKs (avoids crashes if maps are not configured).
class LocationMapScreen extends StatelessWidget {
  final List<Map<String, dynamic>> locations;
  final DateTime? lastUpdated;

  const LocationMapScreen({
    super.key,
    required this.locations,
    this.lastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    String lastUpdatedText = 'Unknown';

    if (lastUpdated != null) {
      lastUpdatedText = DateFormat('MMM d, h:mm a').format(lastUpdated!.toLocal());
    } else if (locations.isNotEmpty && locations.first['timestamp'] is String) {
      try {
        final dt = DateTime.parse(locations.first['timestamp'] as String).toLocal();
        lastUpdatedText = DateFormat('MMM d, h:mm a').format(dt);
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Location',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CustomPaint(
                  painter: _LocationPathPainter(locations),
                  child: Container(
                    color: const Color(0xFF020712),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: const Color(0xFF0F0F0F),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Last Updated',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastUpdatedText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: const [
                    Icon(Icons.route, color: Colors.orangeAccent, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Location Path',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter that turns a list of lat/long points into a
/// nice orange path over a dark background, roughly mimicking
/// a GPS route drawn over a map.
class _LocationPathPainter extends CustomPainter {
  final List<Map<String, dynamic>> locations;

  _LocationPathPainter(this.locations);

  void _drawCenteredText(Canvas canvas, Size size, String text) {
    final textStyle = const TextStyle(
      color: Colors.white70,
      fontSize: 14,
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tp.layout(maxWidth: size.width - 40);
    final offset = Offset(
      (size.width - tp.width) / 2,
      (size.height - tp.height) / 2,
    );
    tp.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background grid / subtle map texture
    final bgPaint = Paint()
      ..color = const Color(0xFF07121E);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Draw faint grid lines to hint at a map
    final gridPaint = Paint()
      ..color = const Color(0xFF0F2436)
      ..strokeWidth = 1;

    const gridSpacing = 32.0;
    for (double x = 0; x <= size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (locations.isEmpty) {
      // No data: show a friendly message in the middle.
      _drawCenteredText(canvas, size, 'No location data yet');
      return;
    }

    // Helper to safely convert dynamic to double
    double? _toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // Extract numeric lat/long values
    final validPoints = <Offset>[];
    final lats = <double>[];
    final lngs = <double>[];

    // First collect raw lat/lng lists so we can normalise later.
    for (final loc in locations) {
      final lat = _toDouble(loc['latitude']);
      final lng = _toDouble(loc['longitude']);
      if (lat != null && lng != null) {
        lats.add(lat);
        lngs.add(lng);
      }
    }

    if (lats.isEmpty || lngs.isEmpty) {
      _drawCenteredText(canvas, size, 'No valid coordinates');
      return;
    }

    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);

    final latRange = (maxLat - minLat).abs().clamp(0.0001, double.infinity);
    final lngRange = (maxLng - minLng).abs().clamp(0.0001, double.infinity);

    final padding = 24.0;
    final width = size.width - padding * 2;
    final height = size.height - padding * 2;

    Offset project(double lat, double lng) {
      final x = ((lng - minLng) / lngRange) * width + padding;
      // Invert latitude for canvas y-axis
      final y = ((maxLat - lat) / latRange) * height + padding;
      return Offset(x, y);
    }

    final pathPaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Build list of projected valid points in chronological order
    for (final loc in locations.reversed) {
      final lat = _toDouble(loc['latitude']);
      final lng = _toDouble(loc['longitude']);
      if (lat == null || lng == null) continue;
      validPoints.add(project(lat, lng));
    }

    if (validPoints.isEmpty) {
      _drawCenteredText(canvas, size, 'No valid coordinates');
      return;
    }

    // If we only have one point, show it clearly as a dot with glow.
    if (validPoints.length == 1) {
      final p = validPoints.first;
      final dotPaint = Paint()..color = Colors.redAccent;
      canvas.drawCircle(p, 6, dotPaint);

      final glowPaint = Paint()
        ..color = Colors.redAccent.withOpacity(0.25)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(p, 10, glowPaint);
      _drawCenteredText(canvas, size, 'Only one location point');
      return;
    }

    final path = Path()..moveTo(validPoints.first.dx, validPoints.first.dy);
    for (var i = 1; i < validPoints.length; i++) {
      path.lineTo(validPoints[i].dx, validPoints[i].dy);
    }

    canvas.drawPath(path, pathPaint);

    // Draw a glow around the path for a more dynamic feel
    final glowPaint = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.2)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glowPaint);

    // Draw start and end points
    final start = validPoints.first;
    final end = validPoints.last;

    final startPaint = Paint()..color = Colors.greenAccent;
    final endPaint = Paint()..color = Colors.redAccent;

    canvas.drawCircle(start, 5, startPaint);
    canvas.drawCircle(end, 6, endPaint);
  }

  @override
  bool shouldRepaint(covariant _LocationPathPainter oldDelegate) {
    return oldDelegate.locations != locations;
  }
}
