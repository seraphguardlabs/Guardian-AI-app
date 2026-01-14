import 'package:flutter/material.dart';
import '../models/child.dart';
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
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: WeeklyActivityChart(child: child),
      ),
    );
  }
}
