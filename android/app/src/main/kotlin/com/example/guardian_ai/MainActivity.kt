package com.example.guardian_ai

import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.guardian_ai/screen_time"
    private val BROWSER_CHANNEL = "com.guardian_ai/browser_history"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize WebsiteDataStore
        WebsiteDataStore.init(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "getScreenTime") {
                val screenTime = getScreenTime()
                if (screenTime != null) {
                    result.success(screenTime)
                } else {
                    result.error("UNAVAILABLE", "Screen time not available.", null)
                }
            } else if (call.method == "openAccessibilitySettings") {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BROWSER_CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "getBrowserHistory") {
                val websites = WebsiteDataStore.getWebsites()
                val historyList = websites.map { url ->
                    mapOf(
                        "title" to url,
                        "url" to url,
                        "timestamp" to System.currentTimeMillis().toString()
                    )
                }
                result.success(historyList)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getScreenTime(): String? {
        // Note: The user requested "root access". 
        // Direct root access to usage stats files (/data/system/usagestats) is complex and brittle (binary formats).
        // The standard and stable way to get this data (which requires a system-level permission) is UsageStatsManager.
        // This provides the same data that "Digital Wellbeing" uses.
        
        if (!hasUsageStatsPermission()) {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            startActivity(intent)
            return "Please grant usage access permission and try again."
        }

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = Calendar.getInstance()
        val endTime = calendar.timeInMillis
        // Set start time to beginning of the day
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        val startTime = calendar.timeInMillis

        val usageStatsList = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, startTime, endTime
        )

        if (usageStatsList == null || usageStatsList.isEmpty()) {
            return "No usage stats found."
        }

        var totalTime: Long = 0
        for (usageStats in usageStatsList) {
            totalTime += usageStats.totalTimeInForeground
        }

        val hours = totalTime / 1000 / 60 / 60
        val minutes = (totalTime / 1000 / 60) % 60
        
        return "${hours}h ${minutes}m today"
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
