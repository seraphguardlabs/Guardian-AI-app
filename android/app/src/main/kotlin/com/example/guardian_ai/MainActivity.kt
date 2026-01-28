package com.example.guardian_ai

import android.app.Activity
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.app.usage.UsageEvents
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.media.projection.MediaProjectionManager
import android.util.Log
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
    private val MONITORING_CHANNEL = "com.example.guardian_ai/monitoring_service"
    private val SCREEN_CAPTURE_CHANNEL = "com.example.guardian_ai/screen_capture"
    
    private val SCREEN_CAPTURE_REQUEST_CODE = 1000
    private var screenCaptureResultCallback: MethodChannel.Result? = null

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
        
        // Monitoring Service Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MONITORING_CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "startMonitoring" -> {
                    MonitoringService.start(this)
                    result.success(true)
                }
                "stopMonitoring" -> {
                    MonitoringService.stop(this)
                    result.success(true)
                }
                "updateRestrictions" -> {
                    val restrictions = call.argument<Map<String, Any>>("restrictions")
                    if (restrictions != null) {
                        val json = org.json.JSONObject(restrictions).toString()
                        MonitoringService.updateRestrictions(this, json)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Restrictions required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Screen Capture Channel
        val screenCaptureChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL)
        ScreenCaptureService.methodChannel = screenCaptureChannel
        
        screenCaptureChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    requestScreenCapturePermission(result)
                }
                "stopCapture" -> {
                    ScreenCaptureService.stop(this)
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
        // Use UsageEvents to compute today's foreground time per app.
        // This is closer to how Digital Wellbeing measures "screen time":
        // - Window: today from local midnight to now
        // - Only user-launchable, non-system apps
        // - Time between ACTIVITY_RESUMED/FOREGROUND and PAUSED/STOPPED/BACKGROUND.

        if (!hasUsageStatsPermission()) {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            startActivity(intent)
            return "Please grant usage access permission and try again."
        }

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        // Use the device's local time zone and calendar day
        val calendar = Calendar.getInstance()
        val endTime = calendar.timeInMillis
        // Start at today's local midnight (not a rolling 24-hour window)
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis

        // Build a set of user-launchable, non-system app package names
        val pm = packageManager
        val installedApps = pm.getInstalledApplications(0)
        val allowedPackages = mutableSetOf<String>()

        // Detect the default launcher (home) app so we can exclude it
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolveInfo = pm.resolveActivity(homeIntent, 0)
        val launcherPackage = resolveInfo?.activityInfo?.packageName

        for (app in installedApps) {
            val launchIntent = pm.getLaunchIntentForPackage(app.packageName)
            val isSystemApp = (app.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
            // Exclude system apps, the launcher, and our own app package
            if (
                launchIntent != null &&
                !isSystemApp &&
                app.packageName != launcherPackage &&
                app.packageName != packageName
            ) {
                allowedPackages.add(app.packageName)
            }
        }

        val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
        if (usageEvents == null) {
            return "No usage stats found."
        }

        val lastForeground = mutableMapOf<String, Long>()
        val totalPerPackage = mutableMapOf<String, Long>()
        val event = UsageEvents.Event()

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            val pkg = event.packageName ?: continue
            if (!allowedPackages.contains(pkg)) continue

            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    lastForeground[pkg] = event.timeStamp
                }
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.ACTIVITY_STOPPED -> {
                    val startTs = lastForeground.remove(pkg)
                    if (startTs != null && event.timeStamp >= startTs) {
                        val diff = event.timeStamp - startTs
                        totalPerPackage[pkg] = (totalPerPackage[pkg] ?: 0L) + diff
                    }
                }
            }
        }

        // If any apps are still considered foreground at the end window, close them at endTime
        for ((pkg, startTs) in lastForeground) {
            if (!allowedPackages.contains(pkg)) continue
            if (endTime > startTs) {
                val diff = endTime - startTs
                totalPerPackage[pkg] = (totalPerPackage[pkg] ?: 0L) + diff
            }
        }

        val totalTime = totalPerPackage.values.fold(0L) { acc, v -> acc + v }

        // Debug logging: show top apps contributing to screen time
        if (totalPerPackage.isNotEmpty()) {
            val sorted = totalPerPackage.toList()
                .sortedByDescending { it.second }
                .take(15)

            Log.d("GuardianScreenTime", "===== Today app usage (foreground intervals) =====")
            Log.d("GuardianScreenTime", "Window: start=$startTime end=$endTime")

            for ((pkg, timeMs) in sorted) {
                val h = timeMs / 1000 / 60 / 60
                val m = (timeMs / 1000 / 60) % 60
                Log.d("GuardianScreenTime", "$pkg -> ${h}h ${m}m")
            }

            val totalH = totalTime / 1000 / 60 / 60
            val totalM = (totalTime / 1000 / 60) % 60
            Log.d("GuardianScreenTime", "TOTAL (apps counted) = ${totalH}h ${totalM}m")
            Log.d("GuardianScreenTime", "==============================================")
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
    
    private fun requestScreenCapturePermission(result: MethodChannel.Result) {
        val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        screenCaptureResultCallback = result
        startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), SCREEN_CAPTURE_REQUEST_CODE)
        Log.d("MainActivity", "Screen capture permission requested")
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == SCREEN_CAPTURE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.d("MainActivity", "Screen capture permission granted")
                // Start the screen capture service
                ScreenCaptureService.start(this, resultCode, data)
                screenCaptureResultCallback?.success(true)
            } else {
                Log.d("MainActivity", "Screen capture permission denied")
                screenCaptureResultCallback?.error("PERMISSION_DENIED", "User denied screen capture permission", null)
            }
            screenCaptureResultCallback = null
        }
    }
}
