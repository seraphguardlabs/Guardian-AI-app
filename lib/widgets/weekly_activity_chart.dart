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

  // Configuration
  static const double _dailyLimitHours = 3.0;

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

      _currentWeekData = _processWeekData(currentWeek);
      _previousWeekData = _processWeekData(previousWeek);
      _twoWeeksAgoData = _processWeekData(twoWeeksAgo);

      // Calculate today's usage from current week data
      final todayKey = dateFormatter.format(now);
      _todayUsage = _currentWeekData[todayKey] ?? 0.0;

      setState(() {
        _loading = false;
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

    if (allValues.isEmpty) {
      return _dailyLimitHours;
    }

    final maxVal = allValues.reduce((a, b) => a > b ? a : b);
    final target = maxVal > _dailyLimitHours ? maxVal : _dailyLimitHours;
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
          'Daily Limit: ${_dailyLimitHours.toInt()} hr',
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),

        // Today's usage
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Today',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatDuration(_todayUsage),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (_todayUsage / _dailyLimitHours).clamp(0.0, 1.0),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (_hasWeekData(_currentWeekData))
                    _buildLegendItem(const Color(0xFF2196F3), 'This Week'),
                  if (_hasWeekData(_previousWeekData))
                    _buildLegendItem(const Color(0xFF64B5F6), 'Last Week'),
                  if (_hasWeekData(_twoWeeksAgoData))
                    _buildLegendItem(const Color(0xFF90CAF9), '2 Weeks Ago'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Chart
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) {
                    return const FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '${value.toInt()}h',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
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
                      getTitlesWidget: (value, meta) {
                        const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
                        if (value.toInt() >= 0 && value.toInt() < 7) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              days[value.toInt()],
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
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
                    tooltipBgColor: const Color(0xFF5B4A9F),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          _formatDuration(spot.y),
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        );
                      }).toList();
                    },
                  ),
                  handleBuiltInTouches: true,
                ),
                lineBarsData: [
                  if (_hasWeekData(_twoWeeksAgoData))
                    LineChartBarData(
                      spots: _getWeekSpots(_twoWeeksAgoData, twoWeeksAgoStart),
                      isCurved: true,
                      color: const Color(0xFF90CAF9),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  if (_hasWeekData(_previousWeekData))
                    LineChartBarData(
                      spots: _getWeekSpots(_previousWeekData, previousWeekStart),
                      isCurved: true,
                      color: const Color(0xFF64B5F6),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  if (_hasWeekData(_currentWeekData))
                    LineChartBarData(
                      spots: _getWeekSpots(_currentWeekData, currentWeekStart),
                      isCurved: true,
                      color: const Color(0xFF2196F3),
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          if (index == now.weekday - 1) {
                            return FlDotCirclePainter(
                              radius: 6,
                              color: Colors.white,
                              strokeWidth: 2,
                              strokeColor: const Color(0xFF2196F3),
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
        const SizedBox(height: 24),

        // Weekly summary
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Weekly Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (_hasWeekData(_currentWeekData)) ...[
                _buildStatRow(
                  'This Week',
                  _formatDuration(_calculateWeekTotal(_currentWeekData)),
                  const Color(0xFF2196F3),
                ),
                if (_hasWeekData(_previousWeekData) || _hasWeekData(_twoWeeksAgoData))
                  const Divider(color: Colors.white24, height: 24),
              ],
              if (_hasWeekData(_previousWeekData)) ...[
                _buildStatRow(
                  'Last Week',
                  _formatDuration(_calculateWeekTotal(_previousWeekData)),
                  const Color(0xFF64B5F6),
                ),
                if (_hasWeekData(_twoWeeksAgoData))
                  const Divider(color: Colors.white24, height: 24),
              ],
              if (_hasWeekData(_twoWeeksAgoData))
                _buildStatRow(
                  'Two Weeks Ago',
                  _formatDuration(_calculateWeekTotal(_twoWeeksAgoData)),
                  const Color(0xFF90CAF9),
                ),
            ],
          ),
        ),
      ],
    );
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
