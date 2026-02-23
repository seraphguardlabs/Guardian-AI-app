import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../utils/app_theme.dart';

/// Detail screen for displaying full alert information with parent action options
class AlertDetailScreen extends StatefulWidget {
  final Alert alert;
  final VoidCallback? onBackPressed;
  final Function(String action)? onAction; // 'WARN', 'BLOCK_APP', 'BLOCK_CONTACT'

  const AlertDetailScreen({
    Key? key,
    required this.alert,
    this.onBackPressed,
    this.onAction,
  }) : super(key: key);

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  bool _isLoadingAction = false;

  void _handleAction(String action) async {
    setState(() => _isLoadingAction = true);
    try {
      if (widget.onAction != null) {
        widget.onAction!(action);
      }
      // Show confirmation feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action "$action" initiated'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAction = false);
      }
    }
  }

  Color _getRiskScoreColor(int riskScore) {
    if (riskScore >= 70) return const Color(0xFFFF4F92); // High - pink/red
    if (riskScore >= 31) return Colors.orange; // Medium
    return Colors.blue; // Low
  }

  String _getRiskLevel(int riskScore) {
    if (riskScore >= 70) return 'High Risk';
    if (riskScore >= 31) return 'Medium Risk';
    return 'Low Risk';
  }

  String _getRiskExplanation(int riskScore) {
    if (riskScore >= 70) {
      return 'This alert requires immediate parental attention and action.';
    } else if (riskScore >= 31) {
      return 'Monitor this content. Consider discussing with your child.';
    }
    return 'This is routine activity. No immediate action needed.';
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final riskColor = _getRiskScoreColor(alert.riskScore);
    final riskLevel = _getRiskLevel(alert.riskScore);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            widget.onBackPressed?.call();
            Navigator.of(context).pop();
          },
        ),
        title: Text('Alert - ${alert.formattedTime}'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Summary Section
              FadeSlideIn(delay: const Duration(milliseconds: 0), child: _buildSummaryCard(alert)),
              const SizedBox(height: 20),

              // Risk Score Section
              FadeSlideIn(delay: const Duration(milliseconds: 100), child: _buildRiskScoreCard(alert, riskColor, riskLevel)),
              const SizedBox(height: 20),

              // Content Details Section
              FadeSlideIn(delay: const Duration(milliseconds: 200), child: _buildContentDetailsCard(alert)),
              const SizedBox(height: 20),

              // Alert Info Section
              FadeSlideIn(delay: const Duration(milliseconds: 300), child: _buildAlertInfoCard(alert)),
              const SizedBox(height: 30),

              // Recommended Actions Section
              if (_shouldShowActions(alert))
                FadeSlideIn(delay: const Duration(milliseconds: 400), child: _buildActionsSection(alert))
              else
                const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Alert alert) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _getRiskScoreColor(alert.riskScore),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.summary,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Child: ${alert.childName}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[400],
                            ),
                      ),
                    ],
                  ),
                ),
                _buildSeverityBadge(alert.severity),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityBadge(AlertSeverity severity) {
    final color = _severityColor(severity);
    final label = severity.toString().split('.').last.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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

  Widget _buildRiskScoreCard(Alert alert, Color riskColor, String riskLevel) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Risk Score',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            // Visual Risk Score Display
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${alert.riskScore}%',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: riskColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.2),
                    border: Border.all(color: riskColor, width: 1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    riskLevel,
                    style: TextStyle(
                      color: riskColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: alert.riskScore / 100.0,
                minHeight: 12,
                backgroundColor: Colors.grey[700],
                valueColor: AlwaysStoppedAnimation<Color>(riskColor),
              ),
            ),
            const SizedBox(height: 12),
            // Risk Explanation
            Text(
              _getRiskExplanation(alert.riskScore),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[400],
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentDetailsCard(Alert alert) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detected Content',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            // Content Type
            Row(
              children: [
                _buildContentTypeIcon(alert.contentType),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Type',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        _contentTypeLabel(alert.contentType),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Detected Content Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                alert.detectedContent.isNotEmpty
                    ? alert.detectedContent
                    : 'No content details available',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[300],
                    ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            // Detection Time
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 18,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detected At',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      alert.formattedDateTime,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentTypeIcon(ContentType contentType) {
    IconData icon;
    Color color;

    switch (contentType) {
      case ContentType.IMAGE:
        icon = Icons.image;
        color = Colors.purple;
        break;
      case ContentType.BEHAVIOR:
        icon = Icons.query_stats;
        color = Colors.cyan;
        break;
      case ContentType.TEXT:
      default:
        icon = Icons.chat_bubble;
        color = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  String _contentTypeLabel(ContentType contentType) {
    switch (contentType) {
      case ContentType.IMAGE:
        return 'Image Content';
      case ContentType.BEHAVIOR:
        return 'Behavioral Pattern';
      case ContentType.TEXT:
      default:
        return 'Text Content';
    }
  }

  Widget _buildAlertInfoCard(Alert alert) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Alert ID', alert.id),
            const Divider(height: 16),
            _buildInfoRow('Child Hash', alert.childHash),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[400],
              ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  bool _shouldShowActions(Alert alert) {
    // Show actions based on alert severity and type
    return alert.severity != AlertSeverity.LOW;
  }

  Widget _buildActionsSection(Alert alert) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recommended Actions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        // WARN Button
        _buildActionButton(
          label: 'WARN',
          icon: Icons.warning_amber,
          color: Colors.orange,
          onPressed: () => _handleAction('WARN'),
          isLoading: _isLoadingAction,
        ),
        const SizedBox(height: 10),
        // BLOCK_APP Button (for TEXT and IMAGE content)
        if (alert.contentType == ContentType.TEXT ||
            alert.contentType == ContentType.IMAGE)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildActionButton(
                label: 'BLOCK APP',
                icon: Icons.app_blocking,
                color: const Color(0xFFFF4F92),
                onPressed: () => _handleAction('BLOCK_APP'),
                isLoading: _isLoadingAction,
              ),
              const SizedBox(height: 10),
            ],
          ),
        // BLOCK_CONTACT Button (for BEHAVIOR alerts or chat-related)
        if (alert.contentType == ContentType.BEHAVIOR ||
            alert.summary.toLowerCase().contains('contact') ||
            alert.summary.toLowerCase().contains('chat'))
          _buildActionButton(
            label: 'BLOCK CONTACT',
            icon: Icons.block,
            color: Colors.red,
            onPressed: () => _handleAction('BLOCK_CONTACT'),
            isLoading: _isLoadingAction,
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required bool isLoading,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(8),
            color: isLoading ? color.withOpacity(0.1) : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
