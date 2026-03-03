import 'package:flutter/material.dart';
import '../models/child.dart';
import '../utils/app_theme.dart';
import '../widgets/weekly_activity_chart.dart';

/// Weekly Activity Screen
///
/// Thin wrapper around [WeeklyActivityChart] so the
/// full-screen view and the dashboard share the same
/// weekly activity implementation.
class WeeklyActivityScreen extends StatelessWidget {
  /// The child whose weekly activity is being displayed
  final Child child;

  const WeeklyActivityScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppTheme.standardAppBar(title: 'Weekly Activity', context: context),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: WeeklyActivityChart(child: child),
      ),
    );
  }
}
