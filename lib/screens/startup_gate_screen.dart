import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/model_manager.dart';
import '../services/screen_capture_service.dart';
import '../services/content_analyzer.dart';
import '../services/alert_service.dart';
import '../utils/app_logger.dart';
import '../utils/app_theme.dart';

/// Gate screen shown on every launch.
///
/// Three sequential checks must pass before the user enters the app:
///   1. Model file on disk — valid size (from Content-Length).
///   2. Model loaded into FlutterGemma inference engine.
///   3. Screen capture permission granted by user.
///
/// The AI pipeline (capture → analyzer → alerts) is wired here and injected
/// into the widget tree via [Provider] before navigating to the main app.
class StartupGateScreen extends StatefulWidget {
  /// Builder for the child app that runs after all checks pass.
  final WidgetBuilder appBuilder;

  const StartupGateScreen({super.key, required this.appBuilder});

  @override
  State<StartupGateScreen> createState() => _StartupGateScreenState();
}

class _StartupGateScreenState extends State<StartupGateScreen>
    with SingleTickerProviderStateMixin {

  // ── Step state ─────────────────────────────────────────────────────────────
  _Step _step = _Step.checkingModel;
  String _statusMessage = 'Checking model…';
  bool _hasError = false;
  String _errorMessage = '';

  // ── Download progress ──────────────────────────────────────────────────────
  double _downloadProgress = 0;
  String _downloadSpeed = '';
  String _downloadEta = '';

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Start after first frame so MediaQuery/context is available
    WidgetsBinding.instance.addPostFrameCallback((_) => _runChecks());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Main check sequence ───────────────────────────────────────────────────

  Future<void> _runChecks() async {
    await _checkModel();
  }

  /// Step 1 — verify model file exists with matching size.
  Future<void> _checkModel() async {
    _setStep(_Step.checkingModel, 'Checking for AI model…');
    final ok = await ModelManager.instance.checkModel();
    if (!mounted) return;
    if (ok) {
      await _checkLoad();
    } else {
      _setStep(_Step.needsDownload, 'AI model not found on device.');
    }
  }

  /// Step 2 — register + load model into inference engine.
  Future<void> _checkLoad() async {
    _setStep(_Step.loadingModel, 'Loading AI model…');

    final completer = Completer<void>();
    final sub = ModelManager.instance.stateStream.listen((state) {
      if (state == ModelState.ready) {
        if (!completer.isCompleted) completer.complete();
      } else if (state == ModelState.error) {
        if (!completer.isCompleted) {
          completer.completeError(ModelManager.instance.lastError ?? 'Load failed');
        }
      }
    });

    try {
      await ModelManager.instance.loadModel();
      await completer.future;
      sub.cancel();
      if (!mounted) return;
      await _checkPermission();
    } catch (e) {
      sub.cancel();
      _setError('Failed to load AI model: $e');
    }
  }

  /// Step 3 — request screen capture permission.
  Future<void> _checkPermission() async {
    _setStep(_Step.requestingPermission, 'Requesting screen permission…');
    // Actual permission dialog is triggered by the "Grant Permission" button.
    // We auto-advance the message so the button appears.
    if (mounted) {
      setState(() {
        _step = _Step.requestingPermission;
        _statusMessage = 'Screen capture permission required.';
      });
    }
  }

  Future<void> _grantPermission() async {
    _setStep(_Step.requestingPermission, 'Waiting for permission…');

    // Build the capture service — it triggers the native permission dialog
    final capture = ScreenCaptureService(
      onCaptureFailed: (reason) {
        AppLogger.log('[StartupGate] Capture failed: $reason');
        // Surface this as a snackbar if we're in the app already
      },
    );

    final granted = await capture.startMonitoring();
    if (!mounted) return;

    if (!granted) {
      _setStep(_Step.requestingPermission, 'Permission denied. Tap "Grant" to try again.');
      return;
    }

    // All checks passed — wire the pipeline and navigate
    await _onAllChecksPassed(capture);
  }

  // ── Pipeline wiring ───────────────────────────────────────────────────────

  Future<void> _onAllChecksPassed(ScreenCaptureService capture) async {
    _setStep(_Step.starting, 'Starting AI monitoring…');

    final model = ModelManager.instance.model!;
    final analyzer = ContentAnalyzer(model);
    final alerts = AlertService(analyzer);

    // Wire: frame stream → analyzer
    capture.frameStream.listen((bytes) => analyzer.processFrame(bytes));

    // Wire: analysis → alerts
    await alerts.start();

    AppLogger.log('[StartupGate] ✅ All checks passed — entering app');

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            Provider<ScreenCaptureService>.value(value: capture),
            Provider<ContentAnalyzer>.value(value: analyzer),
            Provider<AlertService>.value(value: alerts),
          ],
          child: Builder(builder: widget.appBuilder),
        ),
      ),
    );
  }

  // ── Download flow ─────────────────────────────────────────────────────────

  Future<void> _startDownload() async {
    _setStep(_Step.downloading, 'Preparing download…');

    final destPath = await ModelManager.instance.getDefaultDownloadPath();
    final destDir = destPath.substring(0, destPath.lastIndexOf('/'));

    await ModelManager.instance.downloadModel(
      destDir: destDir,
      onProgress: (progress, speedMbps, eta) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = progress;
          _downloadSpeed = '${speedMbps.toStringAsFixed(1)} MB/s';
          _downloadEta = eta != null
              ? '~${eta.inMinutes}m ${eta.inSeconds % 60}s remaining'
              : '';
        });
      },
    );

    if (!mounted) return;

    final state = ModelManager.instance.currentState;
    if (state == ModelState.error) {
      _setError(ModelManager.instance.lastError ?? 'Download failed');
    } else {
      await _checkLoad();
    }
  }

  Future<void> _pickFromStorage() async {
    final picked = await ModelManager.instance.pickModelFromStorage();
    if (!mounted) return;
    if (picked) {
      await _checkLoad();
    } else {
      _setStep(_Step.needsDownload, 'No file selected.');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setStep(_Step step, String message) {
    if (!mounted) return;
    setState(() {
      _step = step;
      _statusMessage = message;
      _hasError = false;
      _errorMessage = '';
    });
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _errorMessage = message;
    });
    AppLogger.logError('[StartupGate]', message);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _AnimatedBg(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                ScaleTransition(
                  scale: _pulse,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Image.asset('assets/images/shield_logo.png',
                        fit: BoxFit.contain),
                  ),
                ),

                const SizedBox(height: 40),

                // Status message
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusMessage,
                    key: ValueKey(_statusMessage),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        letterSpacing: 0.3),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 28),

                // Error card
                if (_hasError) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.error.withOpacity(0.4)),
                    ),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(
                          color: AppTheme.error.withOpacity(0.9),
                          fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Step-specific body
                _buildStepBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {

      // ── Checking / Loading / Starting ──────────────────────────────────────
      case _Step.checkingModel:
      case _Step.loadingModel:
      case _Step.starting:
        return const CircularProgressIndicator(strokeWidth: 2);

      // ── Model not found ────────────────────────────────────────────────────
      case _Step.needsDownload:
        return Column(children: [
          _PrimaryButton(
            icon: Icons.download_rounded,
            label: 'Download Model (~3.1 GB)',
            onTap: _startDownload,
          ),
          const SizedBox(height: 12),
          _SecondaryButton(
            icon: Icons.folder_open_rounded,
            label: 'Choose from Storage',
            onTap: _pickFromStorage,
          ),
          const SizedBox(height: 8),
          Text(
            'Model is saved to your Downloads folder.\nYou will never need to download it again.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ]);

      // ── Downloading ────────────────────────────────────────────────────────
      case _Step.downloading:
        final pct = (_downloadProgress * 100).toStringAsFixed(1);
        return Column(children: [
          LinearProgressIndicator(
            value: _downloadProgress > 0 ? _downloadProgress : null,
            backgroundColor: Colors.white12,
            color: AppTheme.primary,
            minHeight: 6,
          ),
          const SizedBox(height: 10),
          Text(
            '$pct%   $_downloadSpeed',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          if (_downloadEta.isNotEmpty)
            Text(_downloadEta,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 12)),
        ]);

      // ── Permission ─────────────────────────────────────────────────────────
      case _Step.requestingPermission:
        return Column(children: [
          _PrimaryButton(
            icon: Icons.screen_share_rounded,
            label: 'Grant Screen Permission',
            onTap: _grantPermission,
          ),
          const SizedBox(height: 10),
          Text(
            'Guardian AI needs to view the screen to detect harmful content.',
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ]);
    }
  }
}

// ── Step enum ─────────────────────────────────────────────────────────────────
enum _Step {
  checkingModel,
  needsDownload,
  downloading,
  loadingModel,
  requestingPermission,
  starting,
}

// ── Button widgets ────────────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 20),
        label: Text(label),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 20),
        label: Text(label),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// ── Animated background ───────────────────────────────────────────────────────
class _AnimatedBg extends StatelessWidget {
  final Widget child;
  const _AnimatedBg({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.background,
            AppTheme.primary.withOpacity(0.08),
            AppTheme.background,
          ],
        ),
      ),
      child: child,
    );
  }
}
