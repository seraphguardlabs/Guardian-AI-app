import 'package:flutter/material.dart';
import 'dart:async';
import '../models/alert.dart';
import '../services/realtime_alert_service.dart';
import 'alert_detail_screen.dart';

/// Dedicated full-screen risk alerts page
/// Displays all alerts (not just top 5) with real-time updates via stream
class RiskAlertsScreen extends StatefulWidget {
  final String? childHash;
  final String childName;

  const RiskAlertsScreen({
    Key? key,
    this.childHash,
    required this.childName,
  }) : super(key: key);

  @override
  State<RiskAlertsScreen> createState() => _RiskAlertsScreenState();
}

class _RiskAlertsScreenState extends State<RiskAlertsScreen> {
  final RealtimeAlertService _alertService = RealtimeAlertService();
  List<Alert> _alerts = [];
  bool _isLoading = true;
  StreamSubscription<Alert>? _alertStreamSubscription;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _subscribeToAlertStream();
  }

  @override
  void dispose() {
    _alertStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await _alertService.getAlerts(childHash: widget.childHash);
      if (mounted) {
        setState(() {
          _alerts = alerts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading alerts: $e')),
        );
      }
    }
  }

  void _subscribeToAlertStream() {
    _alertStreamSubscription = _alertService.alertStream.listen((alert) {
      // Only add alerts for the selected child
      if (widget.childHash == null || alert.childHash == widget.childHash) {
        if (mounted) {
          setState(() {
            // Add to the beginning of list to keep newest first
            _alerts.insert(0, alert);
          });
        }
      }
    });
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Color _severityColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.HIGH:
        return const Color(0xFFFF4F92);
      case AlertSeverity.MEDIUM:
        return Colors.orange;
      case AlertSeverity.LOW:
        return Colors.blue;
    }
  }

  String _contentTypeLabel(ContentType contentType) {
    switch (contentType) {
      case ContentType.TEXT:
        return 'TEXT_ANALYSIS';
      case ContentType.IMAGE:
        return 'IMAGE';
      case ContentType.BEHAVIOR:
        return 'BEHAVIOR';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Risk Alerts'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _alerts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 64,
                        color: Colors.white30,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Alerts',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No risk alerts detected for ${widget.childName}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[400],
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _alerts.length,
                  itemBuilder: (context, index) {
                    final alert = _alerts[index];
                    final badgeColor = _severityColor(alert.severity);
                    final timeAgo = _formatTimeAgo(alert.timestamp);
                    final severityText = alert.severity.toString().split('.').last;
                    final contentTypeLabel = _contentTypeLabel(alert.contentType);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  AlertDetailScreen(alert: alert),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border(
                              left: BorderSide(
                                color: badgeColor,
                                width: 4,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      severityText,
                                      style: TextStyle(
                                        color: badgeColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          alert.summary,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          alert.formattedDateTime,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Risk Score Progress Bar
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Risk Score: ${alert.riskScore}%',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Text(
                                        contentTypeLabel,
                                        style: TextStyle(
                                          color: badgeColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: alert.riskScore / 100.0,
                                      minHeight: 6,
                                      backgroundColor: Colors.grey[700],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        badgeColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Content Preview
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  alert.detectedContent.length > 100
                                      ? '${alert.detectedContent.substring(0, 100)}...'
                                      : alert.detectedContent,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    timeAgo,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                  const Row(
                                    children: [
                                      Text(
                                        'View Details',
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 10,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.white60,
                                        size: 10,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
