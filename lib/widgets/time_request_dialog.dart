import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/time_extension_service.dart';
import '../utils/preferences_manager.dart';

class TimeRequestDialog extends StatefulWidget {
  final String? packageName;
  final String? appName;

  const TimeRequestDialog({
    super.key,
    this.packageName,
    this.appName,
  });

  @override
  State<TimeRequestDialog> createState() => _TimeRequestDialogState();
}

class _TimeRequestDialogState extends State<TimeRequestDialog> {
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initConnection();
  }

  Future<void> _initConnection() async {
    final timeExtService = context.read<TimeExtensionService>();
    final prefsManager = context.read<PreferencesManager>();
    final childHash = prefsManager.getChildHash() ?? '';

    if (childHash.isNotEmpty) {
      // Preload guardian key and connect WebSocket
      timeExtService.preloadGuardianKey(childHash: childHash);
      timeExtService.connectChildSocket(childHash: childHash);
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final hoursText = _hoursController.text.trim();
    final reason = _reasonController.text.trim();

    if (hoursText.isEmpty) {
      _showError('Please enter the number of hours');
      return;
    }

    final hours = double.tryParse(hoursText);
    if (hours == null || hours <= 0) {
      _showError('Please enter a valid number');
      return;
    }

    if (reason.isEmpty) {
      _showError('Please provide a reason for your request');
      return;
    }

    final prefsManager = context.read<PreferencesManager>();
    final hash = prefsManager.getChildHash();
    if (hash == null || hash.isEmpty) {
      _showError('Error: Child profile not found');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final timeExtService = context.read<TimeExtensionService>();
      final success = await timeExtService.createRequest(
        childHash: hash,
        requestedHours: hours,
        reason: reason,
        packageName: widget.packageName,
        appName: widget.appName,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    success
                        ? 'Request sent! Your parent will be notified.'
                        : 'Failed to send request. Please try again.',
                  ),
                ),
              ],
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeExtService = context.watch<TimeExtensionService>();

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF317AF7), Color(0xFF15335C)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.access_time, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Request Extra Time',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.appName != null) ...[
                const Text(
                  'Requesting time for:',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.apps, color: Color(0xFF317AF7), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.appName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'How many extra hours do you need?',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hoursController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g., 1.5',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.timer, color: Colors.white54),
                  suffixText: 'hours',
                  suffixStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason for request:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Tell your parent why you need extra time...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Connection status indicator
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: timeExtService.childWsConnected
                          ? Colors.greenAccent
                          : timeExtService.childState == WsConnectionState.connecting
                              ? Colors.orangeAccent
                              : Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      timeExtService.childWsConnected
                          ? 'Connected to server'
                          : timeExtService.childState == WsConnectionState.connecting
                              ? 'Connecting…'
                              : 'Not connected',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF317AF7),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Send Request',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}
