import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';

class WeeklyActivityScreen extends StatefulWidget {
  final Child child;

  const WeeklyActivityScreen({super.key, required this.child});

  @override
  State<WeeklyActivityScreen> createState() => _WeeklyActivityScreenState();
}

class _WeeklyActivityScreenState extends State<WeeklyActivityScreen> {
  bool _loading = true;
  String _selectedPeriod = 'This Week';
  
  // Weekly data from API
  Map<String, double> _currentWeekData = {};
  Map<String, double> _previousWeekData = {};
  Map<String, double> _twoWeeksAgoData = {};
  double _dailyLimit = 3.0; // hours
  double _todayUsage = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchWeeklyData();
  }

  Future<void> _fetchWeeklyData() async {
    setState(() => _loading = true);
    
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      
      final email = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';
      
      // Calculate date ranges
      final now = DateTime.now();
      final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
      final currentWeekEnd = currentWeekStart.add(const Duration(days: 6));
      final previousWeekStart = currentWeekStart.subtract(const Duration(days: 7));
      final previousWeekEnd = previousWeekStart.add(const Duration(days: 6));
      final twoWeeksAgoStart = currentWeekStart.subtract(const Duration(days: 14));
      final twoWeeksAgoEnd = twoWeeksAgoStart.add(const Duration(days: 6));
      
      // Fetch data for each week from API
      final currentWeekResult = await apiService.fetchScreenTime(
        email,
        password,
        widget.child.childHash,
        startDate: DateFormat('yyyy-MM-dd').format(currentWeekStart),
        endDate: DateFormat('yyyy-MM-dd').format(currentWeekEnd),
      );
      
      final previousWeekResult = await apiService.fetchScreenTime(
        email,
        password,
        widget.child.childHash,
        startDate: DateFormat('yyyy-MM-dd').format(previousWeekStart),
        endDate: DateFormat('yyyy-MM-dd').format(previousWeekEnd),
      );
      
      final twoWeeksAgoResult = await apiService.fetchScreenTime(
        email,
        password,
        widget.child.childHash,
        startDate: DateFormat('yyyy-MM-dd').format(twoWeeksAgoStart),
        endDate: DateFormat('yyyy-MM-dd').format(twoWeeksAgoEnd),
      );
      
      // Process API responses
      _currentWeekData = _processWeekData(currentWeekResult);
      _previousWeekData = _processWeekData(previousWeekResult);
      _twoWeeksAgoData = _processWeekData(twoWeeksAgoResult);
      
      // Calculate today's usage
      final todayKey = DateFormat('yyyy-MM-dd').format(now);
      _todayUsage = _currentWeekData[todayKey] ?? 0.0;
      
      debugPrint('📊 Weekly data fetched:');
      debugPrint('  Current week: ${_currentWeekData.length} days');
      debugPrint('  Previous week: ${_previousWeekData.length} days');
      debugPrint('  Two weeks ago: ${_twoWeeksAgoData.length} days');
      debugPrint('  Today usage: ${_todayUsage}h');
      
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('❌ Error fetching weekly data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Map<String, double> _processWeekData(Map<String, dynamic> apiResult) {
    final data = <String, double>{};
    
    if (apiResult['success'] == true && apiResult['data'] != null) {
      final responseData = apiResult['data'];
      final trend = responseData['trend'] as List?;
      
      if (trend != null) {
        for (var dayData in trend) {
          final date = dayData['date'] as String;
          final totalSeconds = dayData['total_seconds'] as int? ?? 0;
          final hours = totalSeconds / 3600.0;
          data[date] = hours;
        }
      }
    }
    
    return data;
  }

  List<FlSpot> _getWeekSpots(Map<String, double> weekData, DateTime weekStart) {
    final spots = <FlSpot>[];
    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      final hours = weekData[dateKey] ?? 0.0;
      spots.add(FlSpot(i.toDouble(), hours));
    }
    return spots;
  }

  String _formatDuration(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h${m}m';
  }

  double _calculateMaxY() {
    // Find the maximum value across all weeks
    double maxValue = _dailyLimit;
    
    final allValues = [
      ..._currentWeekData.values,
      ..._previousWeekData.values,
      ..._twoWeeksAgoData.values,
    ];
    
    if (allValues.isNotEmpty) {
      final dataMax = allValues.reduce((a, b) => a > b ? a : b);
      maxValue = dataMax > maxValue ? dataMax : maxValue;
    }
    
    // Add 20% padding and round up to nearest whole number
    return (maxValue * 1.2).ceilToDouble();
  }

  bool _hasWeekData(Map<String, double> weekData) {
    return weekData.isNotEmpty && weekData.values.any((value) => value > 0);
  }

  double _calculateWeekTotal(Map<String, double> weekData) {
    return weekData.values.fold(0.0, (sum, value) => sum + value);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final previousWeekStart = currentWeekStart.subtract(const Duration(days: 7));
    final twoWeeksAgoStart = currentWeekStart.subtract(const Duration(days: 14));

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
          'Weekly Activity',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF5B4A9F)),
            )
          : RefreshIndicator(
              color: const Color(0xFF5B4A9F),
              onRefresh: _fetchWeeklyData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Screen Time Trends Header
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
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
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.expand_more,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Daily Limit: ${_dailyLimit.toInt()} hr',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Today's Usage Card
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
                          // Progress bar
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
                                widthFactor: (_todayUsage / _dailyLimit).clamp(0.0, 1.0),
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

                    // Chart Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 250,
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: 1,
                                  getDrawingHorizontalLine: (value) {
                                    return FlLine(
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
                                  topTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: AxisTitles(
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
                                  // Two weeks ago (lightest)
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
                                  // Previous week (medium)
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
                                  // Current week (brightest blue)
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
                                          // Highlight today's dot
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Weekly Stats Summary
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
                ),
              ),
            ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
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
}
