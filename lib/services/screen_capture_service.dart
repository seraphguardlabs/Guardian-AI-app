import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/app_logger.dart';

/// Dart-side interface for the native screen capture service.
/// 
/// Architecture directly mirrors gemma3n's ScreenMonitorService:
///   • [MethodChannel] 'guardian/screen_capture' — start/stop commands to native.
///   • [EventChannel] 'guardian/screen_frames'  — native → Dart JPEG byte stream.
///   • Watchdog timer (45 s) fires [onCaptureFailed] if no frame arrives.
///
/// The AI frame pipeline:
///   ScreenCaptureService.frameStream  →  ContentAnalyzer.processFrame()
class ScreenCaptureService {
  static const _method = MethodChannel('guardian/screen_capture');
  static const _events = EventChannel('guardian/screen_frames');

  // ── Callbacks ──────────────────────────────────────────────────────────────
  /// Called with each raw JPEG frame emitted by native.
  final void Function(String reason)? onCaptureFailed;

  // ── State ─────────────────────────────────────────────────────────────────
  StreamSubscription<dynamic>? _frameSub;
  Timer? _watchdog;
  int _frameCount = 0;
  bool _running = false;

  /// 45 s watchdog — same as gemma3n (accounts for VirtualDisplay warm-up
  /// + one 30 s capture interval with headroom).
  static const _watchdogMs = 45000;

  ScreenCaptureService({this.onCaptureFailed});

  // ── Public API ────────────────────────────────────────────────────────────

  /// Raw JPEG frame stream.  Subscribe before calling [startMonitoring].
  Stream<Uint8List> get frameStream =>
      _events.receiveBroadcastStream().map((e) => e as Uint8List);

  /// Triggers the native permission dialog. On grant, native starts
  /// [ScreenCaptureService] immediately (gemma3n pattern — no deferred
  /// startCapture call).
  ///
  /// Returns true if permission was granted.
  Future<bool> startMonitoring() async {
    try {
      AppLogger.log('[ScreenCaptureService] Requesting screen capture permission…');
      final granted = await _method.invokeMethod<bool>('startService') ?? false;
      if (granted) {
        AppLogger.log('[ScreenCaptureService] ✅ Permission granted — service started');
        _listenToFrames();
        _startWatchdog();
        _running = true;
      } else {
        AppLogger.log('[ScreenCaptureService] ❌ Permission denied by user');
      }
      return granted;
    } catch (e) {
      AppLogger.logError('[ScreenCaptureService] startMonitoring error', e);
      return false;
    }
  }

  Future<void> stopMonitoring() async {
    _cancelWatchdog();
    await _frameSub?.cancel();
    _frameSub = null;
    _running = false;
    try {
      await _method.invokeMethod('stopService');
    } catch (e) {
      AppLogger.logError('[ScreenCaptureService] stopMonitoring error', e);
    }
    AppLogger.log('[ScreenCaptureService] Service stopped');
  }

  bool get isRunning => _running;
  int get frameCount => _frameCount;

  // ── Internal: Frame Listener ───────────────────────────────────────────────
  void _listenToFrames() {
    AppLogger.log('[ScreenCaptureService] Listening for frames on EventChannel…');
    _frameSub = _events.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Uint8List) {
          _frameCount++;
          AppLogger.log('[ScreenCaptureService] 📸 Frame #$_frameCount (${event.length} bytes)');
          _resetWatchdog();
          // NOTE: Consumers subscribe to frameStream directly.
          // This listener only manages the watchdog + logging.
        }
      },
      onError: (Object error) {
        AppLogger.logError('[ScreenCaptureService] EventChannel error', error);
      },
    );
  }

  // ── Watchdog ──────────────────────────────────────────────────────────────
  void _startWatchdog() {
    _cancelWatchdog();
    AppLogger.log('[ScreenCaptureService] Watchdog started (${_watchdogMs ~/ 1000}s)');
    _watchdog = Timer(Duration(milliseconds: _watchdogMs), _onWatchdogTimeout);
  }

  void _resetWatchdog() {
    _cancelWatchdog();
    _watchdog = Timer(Duration(milliseconds: _watchdogMs), _onWatchdogTimeout);
  }

  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  void _onWatchdogTimeout() {
    final reason = 'No screenshot received within ${_watchdogMs ~/ 1000}s. '
        'Screen capture may have failed or been revoked.';
    AppLogger.log('[ScreenCaptureService] 🚨 WATCHDOG TIMEOUT — $reason');
    stopMonitoring();
    onCaptureFailed?.call(reason);
  }
}
