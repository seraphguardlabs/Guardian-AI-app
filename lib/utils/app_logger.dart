import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static File? _logFile;
  static final List<String> _memoryLog = [];

  static const _channel = MethodChannel(
    'com.example.guardian_ai/shared_logger',
  );

  static Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/ai_guardian.log');
      if (!_logFile!.existsSync()) {
        _logFile!.createSync(recursive: true);
      }

      // Share path with native
      try {
        await _channel.invokeMethod('initLogger', {'path': _logFile!.path});
      } catch (e) {
        debugPrint('[LOGGER-ERROR] Could not sync path to native: $e');
      }

      log('🚀 Logger initialised — isolate: ${Isolate.current.debugName}');
    } catch (e, st) {
      debugPrint('[LOGGER-ERROR] Could not init log file: $e\n$st');
    }
  }

  static void log(String message) {
    final ts = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final line = '[$ts] $message';
    _memoryLog.add(line);

    if (_memoryLog.length > 500) _memoryLog.removeAt(0);

    debugPrint(line);

    try {
      if (_logFile != null) {
        _logFile!.writeAsStringSync(
          '$line\n',
          mode: FileMode.append,
          flush: true,
        );
      }
    } catch (e) {
      debugPrint('[LOGGER-WRITE-ERROR] $e');
    }
  }

  static void logError(String message, Object error, [StackTrace? st]) {
    log('❌ ERROR: $message — $error');
    if (st != null) log('📍 STACKTRACE:\n$st');
  }

  static Future<void> clearLogs() async {
    _memoryLog.clear();
    try {
      if (_logFile != null && _logFile!.existsSync()) {
        await _logFile!.writeAsString('', flush: true);
      }
      log('🧹 Logs cleared by user.');
    } catch (e) {
      debugPrint('[LOGGER-ERROR] Could not clear log file: $e');
    }
  }

  static Future<String> getFullLogFromFile() async {
    try {
      if (_logFile != null && _logFile!.existsSync()) {
        return await _logFile!.readAsString();
      }
    } catch (e) {
      return 'Error reading log file: $e';
    }
    return 'No logs recorded in file.';
  }

  static String getMemoryLog() => _memoryLog.join('\n');
}
