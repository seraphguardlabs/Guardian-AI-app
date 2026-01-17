import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';

/// Reusable weekly activity chart widget that can be embedded
/// directly in other screens (e.g. parent dashboard).
class WeeklyActivityChart extends StatefulWidget {
  final Child child;

  const WeeklyActivityChart({super.key, required this.child});

  @override
  State<WeeklyActivityChart> createState() => _WeeklyActivityChartState();
}

class _WeeklyActivityChartState extends State<WeeklyActivityChart> {
  bool _loading = true;
  String _selectedPeriod = 'This Week';

  // Screen time data for each week (date string -> hours as double)
  Map<String, double> _currentWeekData = {};
  Map<String, double> _previousWeekData = {};
  Map<String, double> _twoWeeksAgoData = {};

  // Global daily screen time limit in hours (fetched from API)
  double? _dailyLimitHours;
  // Default to 8 hours if the server does not provide a limit
  static const double _fallbackDailyLimitHours = 8.0;

  // Today's usage in hours
  double _todayUsage = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchWeeklyData();
  }

  Future<void> _fetchWeeklyData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final prefs = Provider.of<PreferencesManager>(context, listen: false);

      final email = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';

      if (email.isEmpty || password.isEmpty) {
        debugPrint('⚠️ Missing parent credentials for weekly activity chart');
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final now = DateTime.now();
      final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
      final previousWeekStart = currentWeekStart.subtract(const Duration(days: 7));
      final twoWeeksAgoStart = currentWeekStart.subtract(const Duration(days: 14));

      final currentWeekEnd = currentWeekStart.add(const Duration(days: 6));
      final previousWeekEnd = previousWeekStart.add(const Duration(days: 6));
      final twoWeeksAgoEnd = twoWeeksAgoStart.add(const Duration(days: 6));

      final dateFormatter = DateFormat('yyyy-MM-dd');

      final results = await Future.wait([
        apiService.fetchScreenTime(
          email,
          password,
          widget.child.childHash,
          startDate: dateFormatter.format(currentWeekStart),
          endDate: dateFormatter.format(currentWeekEnd),
        ),
        apiService.fetchScreenTime(
          email,
          password,
          widget.child.childHash,
          startDate: dateFormatter.format(previousWeekStart),
          endDate: dateFormatter.format(previousWeekEnd),
        ),
        apiService.fetchScreenTime(
          email,
          password,
          widget.child.childHash,
          startDate: dateFormatter.format(twoWeeksAgoStart),
          endDate: dateFormatter.format(twoWeeksAgoEnd),
        ),
        apiService.fetchDailyLimit(
          email,
          password,
          widget.child.childHash,
        ),
      ]);

      if (!mounted) return;

      final currentWeek = results[0]['success'] == true
          ? (results[0]['data'] as Map<String, dynamic>)
          : null;
      final previousWeek = results[1]['success'] == true
          ? (results[1]['data'] as Map<String, dynamic>)
          : null;
      final twoWeeksAgo = results[2]['success'] == true
          ? (results[2]['data'] as Map<String, dynamic>)
          : null;
        final dailyLimitResult = results[3];

      _currentWeekData = _processWeekData(currentWeek);
      _previousWeekData = _processWeekData(previousWeek);
      _twoWeeksAgoData = _processWeekData(twoWeeksAgo);

      // Global daily limit
      double? fetchedDailyLimitHours;
      if (dailyLimitResult is Map<String, dynamic> &&
          dailyLimitResult['success'] == true) {
        final dailyLimitData = dailyLimitResult['data'] as Map<String, dynamic>?;
        if (dailyLimitData != null) {
          // Backend returns 'daily_screen_time_limit' (and may not include the old 'daily_limit_hours')
          final value = dailyLimitData['daily_screen_time_limit'] ??
              dailyLimitData['daily_limit_hours'];
          if (value is num) {
            fetchedDailyLimitHours = value.toDouble();
          }
        }
      }

      // Calculate today's usage from current week data
      final todayKey = dateFormatter.format(now);
      _todayUsage = _currentWeekData[todayKey] ?? 0.0;

      setState(() {
        _loading = false;
        _dailyLimitHours = fetchedDailyLimitHours;
        debugPrint('📊 WeeklyActivityChart daily limit hours: ${_dailyLimitHours ?? _fallbackDailyLimitHours}');
      });
    } catch (e, stack) {
      debugPrint('❌ Error fetching weekly activity data: $e');
      debugPrint(stack.toString());
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Map<String, double> _processWeekData(Map<String, dynamic>? data) {
    if (data == null || data['trend'] == null) return {};

    final trend = data['trend'] as List<dynamic>;
    final Map<String, double> weekData = {};

    for (final item in trend) {
      if (item is Map<String, dynamic>) {
        final date = item['date'] as String?;
        final totalSeconds = item['total_seconds'] as int?;
        if (date != null && totalSeconds != null) {
          weekData[date] = totalSeconds / 3600.0; // convert to hours
        }
      }
    }

    return weekData;
  }

  bool _hasWeekData(Map<String, double> weekData) {
    return weekData.isNotEmpty && weekData.values.any((value) => value > 0);
  }

  double _calculateWeekTotal(Map<String, double> weekData) {
    return weekData.values.fold(0.0, (sum, value) => sum + value);
  }

  double _calculateMaxY() {
    final allValues = [
      ..._currentWeekData.values,
      ..._previousWeekData.values,
      ..._twoWeeksAgoData.values,
    ];

    final baseLimit = _dailyLimitHours ?? _fallbackDailyLimitHours;

    if (allValues.isEmpty) {
      return baseLimit;
    }

    final maxVal = allValues.reduce((a, b) => a > b ? a : b);
    final target = maxVal > baseLimit ? maxVal : baseLimit;
    return (target + 0.5).ceilToDouble();
  }

  List<FlSpot> _getWeekSpots(Map<String, double> weekData, DateTime weekStart) {
    final spots = <FlSpot>[];

    for (var i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(date);
      final value = weekData[key] ?? 0.0;
      spots.add(FlSpot(i.toDouble(), value));
    }

    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final previousWeekStart = currentWeekStart.subtract(const Duration(days: 7));
    final twoWeeksAgoStart = currentWeekStart.subtract(const Duration(days: 14));

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF5B4A9F)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Screen Time Trends',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white24,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _selectedPeriod,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          // Show server limit when available, otherwise default 8 hours
          'Daily Limit: ${_formatHours((_dailyLimitHours ?? _fallbackDailyLimitHours))} hr',
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),

        // Today's usage section with time display
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Today',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: _formatDuration(_todayUsage),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: '/${_formatHours((_dailyLimitHours ?? _fallbackDailyLimitHours))}h',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Progress bar
        Stack(
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            FractionallySizedBox(
              widthFactor: (() {
                final limit = _dailyLimitHours ?? _fallbackDailyLimitHours;
                if (limit <= 0) return 0.0;
                return (_todayUsage / limit).clamp(0.0, 1.0);
              })(),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF1565C0)],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Legend - Today and Previous Day
        Row(
          children: [
            _buildLegendItem(const Color(0xFF1565C0), 'This Week'),
            const SizedBox(width: 16),
            _buildLegendItem(const Color(0xFF4DD0E1), 'Previous Week'),
          ],
        ),
        const SizedBox(height: 10),

        // Chart
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            height: 120,
            child: LineChart(
            LineChartData(
              gridData: const FlGridData(
                show: false,
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
                      if (value.toInt() >= 0 && value.toInt() < 7) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            days[value.toInt()],
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: 6,
              minY: 0,
              maxY: _calculateMaxY(),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: const Color(0xFF1A3C8F),
                  tooltipRoundedRadius: 8,
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  getTooltipItems: (touchedSpots) {
                    // Only show tooltip for the first (Today) line
                    if (touchedSpots.isEmpty) return [];
                    final todaySpot = touchedSpots.firstWhere(
                      (s) => s.barIndex == (touchedSpots.length > 1 ? 1 : 0),
                      orElse: () => touchedSpots.first,
                    );
                    return touchedSpots.map((spot) {
                      if (spot == todaySpot) {
                        return LineTooltipItem(
                          _formatDuration(spot.y),
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        );
                      }
                      return null;
                    }).toList();
                  },
                ),
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (barData, spotIndexes) {
                  return spotIndexes.map((spotIndex) {
                    return TouchedSpotIndicatorData(
                      const FlLine(color: Colors.transparent),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          return FlDotCirclePainter(
                            radius: 6,
                            color: const Color(0xFF1A3C8F),
                            strokeWidth: 3,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                    );
                  }).toList();
                },
              ),
              lineBarsData: [
                // Previous Day line (lighter cyan)
                if (_hasWeekData(_previousWeekData))
                  LineChartBarData(
                    spots: _getWeekSpots(_previousWeekData, previousWeekStart),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFF4DD0E1),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                // Today line (darker blue)
                if (_hasWeekData(_currentWeekData))
                  LineChartBarData(
                    spots: _getWeekSpots(_currentWeekData, currentWeekStart),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFF1565C0),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        // Show dot only for today
                        if (index == now.weekday - 1) {
                          return FlDotCirclePainter(
                            radius: 5,
                            color: const Color(0xFF1565C0),
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        }
                        return FlDotCirclePainter(
                          radius: 0,
                          color: Colors.transparent,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
              ],
            ),
          ),
        ),
        ),
        const SizedBox(height: 16),

        // Weekly summary - simplified
        if (_hasWeekData(_currentWeekData) || _hasWeekData(_previousWeekData))
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                if (_hasWeekData(_currentWeekData))
                  _buildStatRow(
                    'This Week Total',
                    _formatDuration(_calculateWeekTotal(_currentWeekData)),
                    const Color(0xFF1565C0),
                  ),
                if (_hasWeekData(_currentWeekData) && _hasWeekData(_previousWeekData))
                  const SizedBox(height: 12),
                if (_hasWeekData(_previousWeekData))
                  _buildStatRow(
                    'Last Week Total',
                    _formatDuration(_calculateWeekTotal(_previousWeekData)),
                    const Color(0xFF4DD0E1),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatHours(double hours) {
    if (hours == hours.roundToDouble()) {
      return hours.toStringAsFixed(0);
    }
    return hours.toStringAsFixed(1);
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatDuration(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;

    if (h == 0) {
      return '${m}m';
    }
    if (m == 0) {
      return '${h}h';
    }
    return '${h}h ${m}m';
  }
}
