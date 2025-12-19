package com.example.guardian_ai

import android.app.ActivityManager
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
    private val BLOCKER_CHANNEL = "com.example.guardian_ai/app_blocker"

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
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLOCKER_CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "getForegroundApp" -> {
                    val foregroundApp = getForegroundApp()
                    result.success(foregroundApp)
                }
                "blockApp" -> {
                    val packageName = call.argument<String>("package")
                    if (packageName != null) {
                        blockApp(packageName)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Package name required", null)
                    }
                }
                "goToHomeScreen" -> {
                    goToHomeScreen()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun getForegroundApp(): String? {
        if (!hasUsageStatsPermission()) {
            return null
        }
        
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val currentTime = System.currentTimeMillis()
        val fiveSecondsAgo = currentTime - 5000
        
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            fiveSecondsAgo,
            currentTime
        )
        
        if (stats != null && stats.isNotEmpty()) {
            // Get the most recently used app
            val sortedStats = stats.sortedByDescending { it.lastTimeUsed }
            return sortedStats.firstOrNull()?.packageName
        }
        
        return null
    }
    
    private fun blockApp(packageName: String) {
        // Kill the app process if permission is granted
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        
        // Send user to home screen
        goToHomeScreen()
        
        // Try to kill background processes (requires KILL_BACKGROUND_PROCESSES permission)
        try {
            activityManager.killBackgroundProcesses(packageName)
        } catch (e: Exception) {
            // Permission not granted or other error
        }
    }
    
    private fun goToHomeScreen() {
        val homeIntent = Intent(Intent.ACTION_MAIN)
        homeIntent.addCategory(Intent.CATEGORY_HOME)
        homeIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(homeIntent)
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
