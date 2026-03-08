package com.example.guardian_ai

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.app.usage.UsageStatsManager
import android.widget.Toast
import androidx.core.app.NotificationCompat
import org.json.JSONObject

class MonitoringService : Service() {
    
    companion object {
        private const val CHANNEL_ID = "GuardianAI_Monitoring"
        private const val NOTIFICATION_ID = 2001
        private const val PREFS_NAME = "guardian_ai_prefs"
        private const val KEY_RESTRICTIONS = "restrictions"
        private const val KEY_DAILY_LIMIT_EXCEEDED = "daily_limit_exceeded"
        private const val KEY_DAILY_LIMIT_DATE = "daily_limit_date"
        private const val CHECK_INTERVAL = 3000L // Check every 3 seconds

        // Essential packages that must never be blocked (phone, messages, camera, guardian)
        private val ESSENTIAL_KEYWORDS = listOf("dialer", "phone", "telecom", "mms", "sms", "messag", "camera")
        
        fun start(context: Context) {
            val intent = Intent(context, MonitoringService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stop(context: Context) {
            val intent = Intent(context, MonitoringService::class.java)
            context.stopService(intent)
        }
        
        fun updateRestrictions(context: Context, restrictionsJson: String) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString(KEY_RESTRICTIONS, restrictionsJson).apply()
        }

        fun updateDailyLimitExceeded(context: Context, exceeded: Boolean) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean(KEY_DAILY_LIMIT_EXCEEDED, exceeded).apply()
        }

        private fun isEssentialPackage(packageName: String): Boolean {
            if (packageName == "com.example.guardian_ai") return true
            val lower = packageName.lowercase()
            return ESSENTIAL_KEYWORDS.any { lower.contains(it) }
        }
    }
    
    private val handler = Handler(Looper.getMainLooper())
    private val checkRunnable = object : Runnable {
        override fun run() {
            checkAndBlockApps()
            handler.postDelayed(this, CHECK_INTERVAL)
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } catch (e: Exception) {
            android.util.Log.e("MonitoringService", "Failed to start foreground MonitoringService: \${e.message}")
        }

        // Start monitoring loop
        handler.post(checkRunnable)
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Restart service if killed
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    override fun onDestroy() {
        handler.removeCallbacks(checkRunnable)
        super.onDestroy()
    }
    
    private fun checkAndBlockApps() {
        try {
            val foregroundApp = getForegroundApp() ?: return
            
            // Skip system apps and our own app
            if (foregroundApp.startsWith("com.android") ||
                foregroundApp.startsWith("com.google.android") ||
                foregroundApp == "com.example.guardian_ai" ||
                foregroundApp.contains("launcher")) {
                return
            }

            // Never block essential apps (phone, messages, camera)
            if (isEssentialPackage(foregroundApp)) {
                return
            }
            
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // ── Reset stale daily-limit flag at the start of each new day ──
            val today = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date())
            val savedDate = prefs.getString(KEY_DAILY_LIMIT_DATE, "")
            if (savedDate != today) {
                prefs.edit()
                    .putBoolean(KEY_DAILY_LIMIT_EXCEEDED, false)
                    .putString(KEY_DAILY_LIMIT_DATE, today)
                    .apply()
                android.util.Log.d("MonitoringService", "New day detected ($today) — reset dailyLimitExceeded flag")
            }

            // ── Per-app limit check ──
            // Only block this specific app if IT has exceeded ITS own limit.
            val restrictionsJson = prefs.getString(KEY_RESTRICTIONS, null)
            if (restrictionsJson != null) {
                val restrictions = JSONObject(restrictionsJson)
                if (restrictions.has(foregroundApp)) {
                    val allowedHours = restrictions.getDouble(foregroundApp)
                    val usedSeconds = getAppUsageToday(foregroundApp)
                    val usedHours = usedSeconds / 3600.0
                    
                    android.util.Log.d("MonitoringService",
                        "Per-app check: $foregroundApp | used=${String.format("%.2f", usedHours)}h / allowed=${allowedHours}h")
                    
                    if (allowedHours == 0.0) {
                        // 0 hours = fully blocked (no usage allowed at all)
                        android.util.Log.w("MonitoringService", "BLOCKING $foregroundApp - fully blocked (0h allowed)")
                        blockApp(foregroundApp)
                        return
                    }
                    
                    if (usedHours >= allowedHours) {
                        android.util.Log.w("MonitoringService",
                            "BLOCKING $foregroundApp - per-app limit exceeded! (${String.format("%.2f", usedHours)}h >= ${allowedHours}h)")
                        blockApp(foregroundApp)
                        return
                    }
                    
                    // App is in restriction list but has NOT exceeded its limit — allow it
                    android.util.Log.d("MonitoringService", "ALLOWING $foregroundApp - within per-app limit")
                    return
                }
            }

            // ── Daily limit check ──
            // Only applies to apps NOT in the per-app restriction list.
            // Apps with per-app limits are handled above.
            val dailyLimitExceeded = prefs.getBoolean(KEY_DAILY_LIMIT_EXCEEDED, false)
            if (dailyLimitExceeded) {
                android.util.Log.w("MonitoringService", "BLOCKING $foregroundApp - daily screen-time limit exceeded!")
                blockApp(foregroundApp)
            }
        } catch (e: Exception) {
            android.util.Log.e("MonitoringService", "Error checking apps: ${e.message}")
        }
    }
    
    private fun getForegroundApp(): String? {
        try {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val currentTime = System.currentTimeMillis()
            
            // First try to get the most recent foreground event (look back 1 hour)
            val events = usageStatsManager.queryEvents(currentTime - 3600000, currentTime)
            var foregroundApp: String? = null
            val event = android.app.usage.UsageEvents.Event()
            
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED || 
                    event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    foregroundApp = event.packageName
                } else if (event.eventType == android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED || 
                           event.eventType == android.app.usage.UsageEvents.Event.ACTIVITY_STOPPED || 
                           event.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND) {
                    if (foregroundApp == event.packageName) {
                        foregroundApp = null
                    }
                }
            }
            
            if (foregroundApp != null) {
                return foregroundApp
            }
            
            // Fallback to queryUsageStats (look back 1 minute)
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                currentTime - 60000,
                currentTime
            )
            
            if (stats != null && stats.isNotEmpty()) {
                val sortedStats = stats.sortedByDescending { it.lastTimeUsed }
                return sortedStats.firstOrNull()?.packageName
            }
        } catch (e: Exception) {
            android.util.Log.e("MonitoringService", "Error getting foreground app: ${e.message}")
        }
        return null
    }
    
    /**
     * Get today's foreground usage for [packageName] in seconds.
     *
     * Uses event-based calculation (ACTIVITY_RESUMED / PAUSED) as the
     * primary source because it is scoped exactly to today's events.
     * Falls back to queryUsageStats only when no events are available.
     */
    private fun getAppUsageToday(packageName: String): Long {
        try {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val calendar = java.util.Calendar.getInstance()
            calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
            calendar.set(java.util.Calendar.MINUTE, 0)
            calendar.set(java.util.Calendar.SECOND, 0)
            calendar.set(java.util.Calendar.MILLISECOND, 0)
            val startTime = calendar.timeInMillis
            val endTime = System.currentTimeMillis()

            // ── Primary: event-based calculation (most accurate) ──
            val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
            if (usageEvents != null) {
                var lastForeground: Long? = null
                var totalMs = 0L
                var hasEvents = false
                val event = android.app.usage.UsageEvents.Event()

                while (usageEvents.hasNextEvent()) {
                    usageEvents.getNextEvent(event)
                    val pkg = event.packageName ?: continue
                    if (pkg != packageName) continue

                    hasEvents = true
                    when (event.eventType) {
                        android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED,
                        android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                            lastForeground = event.timeStamp
                        }
                        android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED,
                        android.app.usage.UsageEvents.Event.ACTIVITY_STOPPED,
                        android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                            val startTs = lastForeground
                            if (startTs != null && event.timeStamp >= startTs) {
                                totalMs += (event.timeStamp - startTs)
                            }
                            lastForeground = null
                        }
                    }
                }

                // Account for the current session if the app is still in foreground
                if (lastForeground != null && endTime > lastForeground!!) {
                    totalMs += (endTime - lastForeground!!)
                }

                if (hasEvents) {
                    val seconds = totalMs / 1000
                    android.util.Log.d("MonitoringService",
                        "Usage (events) for $packageName: ${seconds}s (${String.format("%.2f", seconds / 3600.0)}h)")
                    return seconds
                }
            }

            // ── Fallback: queryUsageStats when events are unavailable ──
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            )

            val appStat = stats?.firstOrNull { it.packageName == packageName }
            if (appStat != null && appStat.totalTimeInForeground > 0) {
                val seconds = appStat.totalTimeInForeground / 1000
                android.util.Log.d("MonitoringService",
                    "Usage (stats fallback) for $packageName: ${seconds}s (${String.format("%.2f", seconds / 3600.0)}h)")
                return seconds
            }
        } catch (e: Exception) {
            android.util.Log.e("MonitoringService", "Error getting app usage: ${e.message}")
        }
        return 0
    }
    
    private fun blockApp(packageName: String) {
        try {
            // Show toast
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(
                    this,
                    "⛔ Time limit exceeded!",
                    Toast.LENGTH_LONG
                ).show()
            }
            
            // Go to home screen
            val homeIntent = Intent(Intent.ACTION_MAIN)
            homeIntent.addCategory(Intent.CATEGORY_HOME)
            homeIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(homeIntent)
            
            // Try to kill the app
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.killBackgroundProcesses(packageName)
            
            // Try force-stop (requires root/system)
            try {
                Runtime.getRuntime().exec(arrayOf("am", "force-stop", packageName))
            } catch (e: Exception) {
                // Silently fail
            }
            
            // Check again after delay to prevent restart
            handler.postDelayed({
                val currentApp = getForegroundApp()
                if (currentApp == packageName) {
                    blockApp(packageName)
                }
            }, 500)
            
        } catch (e: Exception) {
            android.util.Log.e("MonitoringService", "Error blocking app: ${e.message}")
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Guardian AI Protection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitoring and protecting this device"
                setShowBadge(false)
                setSound(null, null)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Guardian AI Active")
            .setContentText("Protection running in background")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
