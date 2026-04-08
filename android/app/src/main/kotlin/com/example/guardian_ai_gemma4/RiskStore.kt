package com.example.guardian_ai_gemma4

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class RiskSnapshot(
    val timestampMs: Long,
    val sexual: Double,
    val violence: Double,
    val predatoryText: Double,
    val overall: Double,
)

object RiskStore {
    private const val PREFS_NAME = "guardian_risk_prefs"
    private const val KEY_MODEL_PATH = "model_path"
    private const val KEY_MODEL_ID = "model_id"
    private const val KEY_HF_TOKEN = "hf_token"
    private const val KEY_MONITORING_ENABLED = "monitoring_enabled"
    private const val KEY_CAPTURE_INTERVAL_SECONDS = "capture_interval_seconds"
    private const val KEY_LATEST = "latest"
    private const val KEY_HISTORY = "history"
    private const val MAX_HISTORY = 200

    fun setModelPath(context: Context, modelPath: String) {
        prefs(context).edit().putString(KEY_MODEL_PATH, modelPath).apply()
    }

    fun getModelPath(context: Context): String? = prefs(context).getString(KEY_MODEL_PATH, null)

    fun setModelId(context: Context, modelId: String) {
        prefs(context).edit().putString(KEY_MODEL_ID, modelId).apply()
    }

    fun getModelId(context: Context): String? = prefs(context).getString(KEY_MODEL_ID, null)

    fun setHfToken(context: Context, token: String) {
        prefs(context).edit().putString(KEY_HF_TOKEN, token).apply()
    }

    fun getHfToken(context: Context): String? = prefs(context).getString(KEY_HF_TOKEN, null)

    fun setMonitoringEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_MONITORING_ENABLED, enabled).apply()
    }

    fun isMonitoringEnabled(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_MONITORING_ENABLED, false)
    }

    fun setCaptureIntervalSeconds(context: Context, seconds: Int) {
        prefs(context).edit().putInt(KEY_CAPTURE_INTERVAL_SECONDS, seconds.coerceIn(2, 15)).apply()
    }

    fun getCaptureIntervalSeconds(context: Context): Int {
        return prefs(context).getInt(KEY_CAPTURE_INTERVAL_SECONDS, 5).coerceIn(2, 15)
    }

    @Synchronized
    fun storeRiskSnapshot(context: Context, snapshot: RiskSnapshot) {
        val latest = snapshotToJson(snapshot)
        val historyArray = JSONArray(prefs(context).getString(KEY_HISTORY, "[]") ?: "[]")
        historyArray.put(0, latest)

        while (historyArray.length() > MAX_HISTORY) {
            historyArray.remove(historyArray.length() - 1)
        }

        prefs(context).edit()
            .putString(KEY_LATEST, latest.toString())
            .putString(KEY_HISTORY, historyArray.toString())
            .apply()
    }

    fun getLatestRiskMap(context: Context): Map<String, Any>? {
        val latest = prefs(context).getString(KEY_LATEST, null) ?: return null
        return jsonToMap(JSONObject(latest))
    }

    fun getRecentRiskMaps(context: Context, limit: Int): List<Map<String, Any>> {
        val historyArray = JSONArray(prefs(context).getString(KEY_HISTORY, "[]") ?: "[]")
        val maxItems = limit.coerceIn(1, MAX_HISTORY)
        val output = mutableListOf<Map<String, Any>>()

        for (i in 0 until minOf(historyArray.length(), maxItems)) {
            output.add(jsonToMap(historyArray.getJSONObject(i)))
        }

        return output
    }

    private fun snapshotToJson(snapshot: RiskSnapshot): JSONObject {
        return JSONObject()
            .put("timestampMs", snapshot.timestampMs)
            .put("sexual", snapshot.sexual)
            .put("violence", snapshot.violence)
            .put("predatoryText", snapshot.predatoryText)
            .put("overall", snapshot.overall)
    }

    private fun jsonToMap(jsonObject: JSONObject): Map<String, Any> {
        return mapOf(
            "timestampMs" to jsonObject.optLong("timestampMs", 0L),
            "sexual" to jsonObject.optDouble("sexual", 0.0),
            "violence" to jsonObject.optDouble("violence", 0.0),
            "predatoryText" to jsonObject.optDouble("predatoryText", 0.0),
            "overall" to jsonObject.optDouble("overall", 0.0),
        )
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
