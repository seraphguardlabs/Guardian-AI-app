import 'package:flutter/services.dart';

import '../models/risk_result.dart';

class GuardianPlatform {
  static const MethodChannel _channel = MethodChannel('guardian_ai/methods');

  Future<void> initializeModel({
    required String modelPath,
    required String modelId,
    required String hfToken,
  }) async {
    await _channel.invokeMethod<void>('initializeModel', {
      'modelPath': modelPath,
      'modelId': modelId,
      'hfToken': hfToken,
    });
  }

  Future<void> setMonitoringEnabled({
    required bool enabled,
    required int intervalSeconds,
  }) async {
    await _channel.invokeMethod<void>('setMonitoringEnabled', {
      'enabled': enabled,
      'intervalSeconds': intervalSeconds,
    });
  }

  Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod<void>('openAccessibilitySettings');
  }

  Future<bool> isAccessibilityServiceEnabled() async {
    final value = await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');
    return value ?? false;
  }

  Future<RiskResult?> getLatestRiskResult() async {
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>('getLatestRiskResult');
    if (map == null) {
      return null;
    }
    return RiskResult.fromMap(map);
  }

  Future<List<RiskResult>> getRecentRiskResults({int limit = 30}) async {
    final list = await _channel.invokeMethod<List<dynamic>>(
      'getRecentRiskResults',
      {'limit': limit},
    );

    if (list == null) {
      return <RiskResult>[];
    }

    return list
        .whereType<Map<dynamic, dynamic>>()
        .map(RiskResult.fromMap)
        .toList(growable: false);
  }
}
