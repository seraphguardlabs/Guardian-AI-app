import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';

/// Weekly Activity Screen
/// 
/// Displays a comprehensive view of a child's screen time activity over a 3-week period.
/// 
/// Features:
/// - Line chart showing screen time trends for current week, last week, and two weeks ago
/// - Today's usage summary with progress bar against daily limit
/// - Weekly totals comparison
/// - Pull-to-refresh functionality
/// - Conditional rendering (only shows weeks with actual data)
/// 
/// API Integration:
/// - Uses /api/mobile/child/<hash>/screen-time/ endpoint
/// - Fetches data with date range parameters for each week
/// - Requires parent email/password authentication via headers
/// 
/// Color Scheme:
/// - Current week: Bright blue (#2196F3)
/// - Last week: Medium blue (#64B5F6)
/// - Two weeks ago: Light blue (#90CAF9)
class WeeklyActivityScreen extends StatefulWidget {
  /// The child whose weekly activity is being displayed
  final Child child;

  const WeeklyActivityScreen({super.key, required this.child});

  @override
  State<WeeklyActivityScreen> createState() => _WeeklyActivityScreenState();
}

class _WeeklyActivityScreenState extends State<WeeklyActivityScreen> {
  // Loading state
  bool _loading = true;
  
  // Currently selected time period (for future filtering feature)
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

  /// Fetches screen time data for the current week, previous week, and two weeks ago
  /// 
  /// Makes parallel API calls to /api/mobile/child/<hash>/screen-time/ endpoint
  /// with different date ranges for each week (Monday to Sunday).
  /// 
  /// Updates state with processed data and calculates today's usage.
  Future<void> _fetchWeeklyData() async {
    setState(() => _loading = true);
    
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      
      final email = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';
      
      if (email.isEmpty || password.isEmpty) {
        debugPrint('⚠️ Missing parent credentials for API call');
        if (mounted) setState(() => _loading = false);
        return;
      }
      
      // Calculate date ranges (all weeks start on Monday)
      final now = DateTime.now();
      final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
      final currentWeekEnd = currentWeekStart.add(const Duration(days: 6));
      final previousWeekStart = currentWeekStart.subtract(const Duration(days: 7));
      final previousWeekEnd = previousWeekStart.add(const Duration(days: 6));
      final twoWeeksAgoStart = currentWeekStart.subtract(const Duration(days: 14));
      final twoWeeksAgoEnd = twoWeeksAgoStart.add(const Duration(days: 6));
      
      // Fetch data for each week from API in parallel
      final results = await Future.wait([
        apiService.fetchScreenTime(
          email,
          password,
          widget.child.childHash,
          startDate: DateFormat('yyyy-MM-dd').format(currentWeekStart),
          endDate: DateFormat('yyyy-MM-dd').format(currentWeekEnd),
        ),
        apiService.fetchScreenTime(
          email,
          password,
          widget.child.childHash,
          startDate: DateFormat('yyyy-MM-dd').format(previousWeekStart),
          endDate: DateFormat('yyyy-MM-dd').format(previousWeekEnd),
        ),
        apiService.fetchScreenTime(
          email,
          password,
          widget.child.childHash,
          startDate: DateFormat('yyyy-MM-dd').format(twoWeeksAgoStart),
          endDate: DateFormat('yyyy-MM-dd').format(twoWeeksAgoEnd),
        ),
      ]);
      
      // Process API responses
      _currentWeekData = _processWeekData(results[0]);
      _previousWeekData = _processWeekData(results[1]);
      _twoWeeksAgoData = _processWeekData(results[2]);
      
      // Calculate today's usage
      final todayKey = DateFormat('yyyy-MM-dd').format(now);
      _todayUsage = _currentWeekData[todayKey] ?? 0.0;
      
      debugPrint('📊 Weekly data fetched successfully:');
      debugPrint('  Current week: ${_currentWeekData.length} days');
      debugPrint('  Previous week: ${_previousWeekData.length} days');
      debugPrint('  Two weeks ago: ${_twoWeeksAgoData.length} days');
      debugPrint('  Today usage: ${_formatDuration(_todayUsage)}');
      
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

  /// Processes API response and converts to Map<String, double>
  /// 
  /// Extracts the 'trend' array from API response and converts each day's
  /// total_seconds to hours for easier chart rendering.
  /// 
  /// Returns: Map with date strings (yyyy-MM-dd) as keys and hours as values
  Map<String, double> _processWeekData(Map<String, dynamic> apiResult) {
    final data = <String, double>{};
    
    if (apiResult['success'] != true || apiResult['data'] == null) {
      return data;
    }
    
    final responseData = apiResult['data'];
    final trend = responseData['trend'] as List?;
    
    if (trend == null) return data;
    
    for (var dayData in trend) {
      final date = dayData['date'] as String?;
      final totalSeconds = dayData['total_seconds'] as int? ?? 0;
      
      if (date != null) {
        final hours = totalSeconds / 3600.0;
        data[date] = hours;
      }
    }
    
    return data;
  }

  /// Converts week data to FlSpot list for chart rendering
  /// 
  /// Creates 7 data points (Monday to Sunday) for the line chart.
  /// Uses 0.0 for days with no data.
  /// 
  /// Parameters:
  /// - weekData: Map of date strings to hours
  /// - weekStart: The Monday of the week
  /// 
  /// Returns: List of FlSpot with x=day_index (0-6) and y=hours
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

  /// Formats hours as "Xh Ym" string
  /// 
  /// Examples:
  /// - 2.5 hours -> "2h 30m"
  /// - 0.75 hours -> "0h 45m"
  /// - 3.0 hours -> "3h 0m"
  String _formatDuration(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h}h ${m}m';
  }

  /// Calculates the maximum Y-axis value for the chart
  /// 
  /// Ensures the chart has enough space to display all data points
  /// by finding the max value across all weeks and adding 20% padding.
  /// Always shows at least the daily limit.
  /// 
  /// Returns: Ceiling of (max_value * 1.2) or daily limit, whichever is greater
  double _calculateMaxY() {
    double maxValue = _dailyLimitHours;
    
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

  /// Checks if a week has any non-zero screen time data
  /// 
  /// Used to conditionally render weeks in the chart and legend.
  /// Only weeks with actual usage are displayed.
  bool _hasWeekData(Map<String, double> weekData) {
    return weekData.isNotEmpty && weekData.values.any((value) => value > 0);
  }

  /// Calculates total screen time for a week
  /// 
  /// Sums all daily hours in the week data.
  /// 
  /// Returns: Total hours for the week
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
                      'Daily Limit: ${_dailyLimitHours.toInt()} hr',
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

  /// Builds a legend item showing a colored circle and label
  /// 
  /// Used in the today's usage card to show which line represents which week.
  /// 
  /// Parameters:
  /// - color: The color of the circle and corresponding line in the chart
  /// - label: Text label (e.g., "This Week", "Last Week")
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

  /// Builds a stat row showing weekly total with colored indicator
  /// 
  /// Used in the weekly summary section at the bottom of the screen.
  /// 
  /// Parameters:
  /// - label: Week name (e.g., "This Week")
  /// - value: Formatted duration string (e.g., "12h 30m")
  /// - color: Color matching the week's line in the chart
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
