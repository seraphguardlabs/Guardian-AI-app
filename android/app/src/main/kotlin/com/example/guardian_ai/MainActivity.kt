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
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity: FlutterActivity() {

    companion object {
        private const val TAG = "GuardianAI"

        /** Receives JPEG ByteArray frames from ScreenCaptureService and delivers them to Dart. */
        var eventSink: EventChannel.EventSink? = null

        fun sendFrameToFlutter(frame: ByteArray) {
            Handler(Looper.getMainLooper()).post {
                if (eventSink != null) {
                    eventSink?.success(frame)
                    Log.d(TAG, "sendFrameToFlutter: ${frame.size} bytes sent ✅")
                } else {
                    Log.w(TAG, "sendFrameToFlutter: EventSink null — frame dropped")
                }
            }
        }
    }

    private val CHANNEL = "com.guardian_ai/screen_time"
    private val BROWSER_CHANNEL = "com.guardian_ai/browser_history"
    private val BLOCKER_CHANNEL = "com.example.guardian_ai/app_blocker"
    private val MONITORING_CHANNEL = "com.example.guardian_ai/monitoring_service"
    private val SCREEN_CAPTURE_CHANNEL = "guardian/screen_capture"
    private val SCREEN_FRAMES_CHANNEL = "guardian/screen_frames"
    private val LOCATION_SERVICE_CHANNEL = "com.example.guardian_ai/location_service"

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
            } else if (call.method == "getScreenTimeDetails") {
                if (!hasUsageStatsPermission()) {
                    result.error("PERMISSION", "Usage access not granted.", null)
                } else {
                    val details = computeScreenTimeDetails()
                    result.success(
                        mapOf(
                            "totalSeconds" to details.first,
                            "perAppSeconds" to details.second
                        )
                    )
                }
            } else if (call.method == "isAccessibilityServiceEnabled") {
                val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as android.view.accessibility.AccessibilityManager
                val enabledServices = am.getEnabledAccessibilityServiceList(android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                val isEnabled = enabledServices.any { it.resolveInfo.serviceInfo.name.contains("WebsiteMonitoringService", ignoreCase = true) }
                result.success(isEnabled)
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
                "updateDailyLimitExceeded" -> {
                    val exceeded = call.argument<Boolean>("exceeded") ?: false
                    MonitoringService.updateDailyLimitExceeded(this, exceeded)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Screen Capture MethodChannel — startService triggers permission dialog,
        // then service starts directly from onActivityResult (gemma3n pattern).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        screenCaptureResultCallback = result
                        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        startActivityForResult(mpm.createScreenCaptureIntent(), SCREEN_CAPTURE_REQUEST_CODE)
                        Log.d(TAG, "Screen capture permission dialog launched")
                    }
                    "stopService" -> {
                        ScreenCaptureService.stop(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Screen Frames EventChannel — ScreenCaptureService calls sendFrameToFlutter()
        // which posts to this sink. Dart side receives Uint8List directly in memory.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_FRAMES_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    Log.d(TAG, "EventChannel: Dart is listening ✅")
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    Log.d(TAG, "EventChannel: Dart cancelled stream")
                }
            })

        // Location Background Service Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startLocationService" -> {
                        LocationForegroundService.startService(this)
                        result.success(true)
                    }
                    "stopLocationService" -> {
                        LocationForegroundService.stopService(this)
                        result.success(true)
                    }
                    "isLocationServiceRunning" -> {
                        result.success(LocationForegroundService.isServiceRunning)
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    private fun getForegroundApp(): String? {
        if (!hasUsageStatsPermission()) {
            return null
        }
        
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val currentTime = System.currentTimeMillis()
        
        // First try to get the most recent foreground event (look back 1 hour)
        val events = usageStatsManager.queryEvents(currentTime - 3600000, currentTime)
        var foregroundApp: String? = null
        val event = UsageEvents.Event()
        
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED || 
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                foregroundApp = event.packageName
            } else if (event.eventType == UsageEvents.Event.ACTIVITY_PAUSED || 
                       event.eventType == UsageEvents.Event.ACTIVITY_STOPPED || 
                       event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND) {
                if (foregroundApp == event.packageName) {
                    foregroundApp = null
                }
            }
        }
        
        if (foregroundApp != null) {
            return foregroundApp
        }
        
        // Fallback to queryUsageStats (look back 1 minute)
        val oneMinuteAgo = currentTime - 60000
        
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST,
            oneMinuteAgo,
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

        val details = computeScreenTimeDetails()
        val totalPerPackage = details.second
        val totalTime = totalPerPackage.values.fold(0L) { acc, v -> acc + v } * 1000

        val calendar = Calendar.getInstance()
        val endTime = calendar.timeInMillis
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis

        // Debug logging: show top apps contributing to screen time
        if (totalPerPackage.isNotEmpty()) {
            val sorted = totalPerPackage.toList()
                .sortedByDescending { it.second }
                .take(15)

            Log.d("GuardianScreenTime", "===== Today app usage (foreground intervals) =====")
            Log.d("GuardianScreenTime", "Window: start=$startTime end=$endTime")

            for ((pkg, timeSeconds) in sorted) {
                val h = timeSeconds / 60 / 60
                val m = (timeSeconds / 60) % 60
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

    private fun computeScreenTimeDetails(): Pair<Long, Map<String, Long>> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val calendar = Calendar.getInstance()
        val endTime = calendar.timeInMillis
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis

        val allowedPackages = buildAllowedPackages()

        val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
        if (usageEvents == null) {
            return Pair(0L, emptyMap())
        }

        var screenInteractive = false
        var currentApp: String? = null
        var currentStart: Long? = null
        val totalPerPackage = mutableMapOf<String, Long>()
        val event = UsageEvents.Event()

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            val pkg = event.packageName

            when (event.eventType) {
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    screenInteractive = true
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    if (currentApp != null && currentStart != null) {
                        val diff = event.timeStamp - currentStart!!
                        if (diff > 0) {
                            totalPerPackage[currentApp!!] = (totalPerPackage[currentApp!!] ?: 0L) + diff
                        }
                    }
                    currentApp = null
                    currentStart = null
                    screenInteractive = false
                }
                UsageEvents.Event.ACTIVITY_RESUMED,
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    if (pkg == null || !allowedPackages.contains(pkg) || !screenInteractive) {
                        continue
                    }
                    if (currentApp != null && currentStart != null && currentApp != pkg) {
                        val diff = event.timeStamp - currentStart!!
                        if (diff > 0) {
                            totalPerPackage[currentApp!!] = (totalPerPackage[currentApp!!] ?: 0L) + diff
                        }
                    }
                    currentApp = pkg
                    currentStart = event.timeStamp
                }
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.ACTIVITY_STOPPED,
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    if (pkg == null || currentApp == null || currentStart == null || pkg != currentApp) {
                        continue
                    }
                    val diff = event.timeStamp - currentStart!!
                    if (diff > 0) {
                        totalPerPackage[currentApp!!] = (totalPerPackage[currentApp!!] ?: 0L) + diff
                    }
                    currentApp = null
                    currentStart = null
                }
            }
        }

        if (currentApp != null && currentStart != null && screenInteractive && endTime > currentStart!!) {
            val diff = endTime - currentStart!!
            if (diff > 0) {
                totalPerPackage[currentApp!!] = (totalPerPackage[currentApp!!] ?: 0L) + diff
            }
        }

        val totalSeconds = totalPerPackage.values.fold(0L) { acc, v -> acc + v } / 1000
        val perAppSeconds = totalPerPackage.mapValues { it.value / 1000 }
        return Pair(totalSeconds, perAppSeconds)
    }

    private fun buildAllowedPackages(): Set<String> {
        val pm = packageManager
        val installedApps = pm.getInstalledApplications(0)
        val allowedPackages = mutableSetOf<String>()

        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolveInfo = pm.resolveActivity(homeIntent, 0)
        val launcherPackage = resolveInfo?.activityInfo?.packageName

        for (app in installedApps) {
            val launchIntent = pm.getLaunchIntentForPackage(app.packageName)
            if (
                launchIntent != null &&
                app.packageName != launcherPackage &&
                app.packageName != packageName
            ) {
                allowedPackages.add(app.packageName)
            }
        }

        return allowedPackages
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
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == SCREEN_CAPTURE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.d(TAG, "Screen capture permission GRANTED ✅")
                // Start the service immediately — gemma3n pattern.
                // No deferred startCapture() call needed.
                ScreenCaptureService.start(this, resultCode, data)
                screenCaptureResultCallback?.success(true)
            } else {
                Log.w(TAG, "Screen capture permission DENIED")
                screenCaptureResultCallback?.success(false)
            }
            screenCaptureResultCallback = null
        }
    }
}
