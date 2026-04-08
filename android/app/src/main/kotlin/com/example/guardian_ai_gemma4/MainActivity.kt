package com.example.guardian_ai_gemma4

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val CHANNEL = "guardian_ai/methods"

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"initializeModel" -> {
						val modelPath = call.argument<String>("modelPath")
						val modelId = call.argument<String>("modelId")
						val hfToken = call.argument<String>("hfToken") ?: ""
						if (modelPath.isNullOrBlank()) {
							result.error("INVALID_MODEL_PATH", "modelPath is required", null)
							return@setMethodCallHandler
						}

						if (modelId.isNullOrBlank()) {
							result.error("INVALID_MODEL_ID", "modelId is required", null)
							return@setMethodCallHandler
						}

						RiskStore.setModelPath(this, modelPath)
						RiskStore.setModelId(this, modelId)
						RiskStore.setHfToken(this, hfToken)
						GemmaLiteEngine.initialize(modelPath)
						result.success(null)
					}

					"setMonitoringEnabled" -> {
						val enabled = call.argument<Boolean>("enabled") ?: false
						val intervalSeconds = call.argument<Int>("intervalSeconds") ?: 5

						RiskStore.setMonitoringEnabled(this, enabled)
						RiskStore.setCaptureIntervalSeconds(this, intervalSeconds)
						GuardianAccessibilityService.requestImmediateCapture()
						result.success(null)
					}

					"openAccessibilitySettings" -> {
						val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(null)
					}

					"isAccessibilityServiceEnabled" -> {
						result.success(isAccessibilityServiceEnabled())
					}

					"getLatestRiskResult" -> {
						result.success(RiskStore.getLatestRiskMap(this))
					}

					"getRecentRiskResults" -> {
						val limit = call.argument<Int>("limit") ?: 30
						result.success(RiskStore.getRecentRiskMaps(this, limit))
					}

					else -> result.notImplemented()
				}
			}
	}

	private fun isAccessibilityServiceEnabled(): Boolean {
		val componentName = ComponentName(this, GuardianAccessibilityService::class.java)
		val expectedShort = componentName.flattenToShortString()
		val expectedFull = componentName.flattenToString()
		val expectedClass = GuardianAccessibilityService::class.java.name

		val enabledServices = Settings.Secure.getString(
			contentResolver,
			Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
		) ?: return false

		return enabledServices
			.split(':')
			.map { it.trim() }
			.any {
				it.equals(expectedShort, ignoreCase = true) ||
					it.equals(expectedFull, ignoreCase = true) ||
					it.endsWith("/.GuardianAccessibilityService", ignoreCase = true) ||
					it.endsWith("/$expectedClass", ignoreCase = true)
			}
	}
}
