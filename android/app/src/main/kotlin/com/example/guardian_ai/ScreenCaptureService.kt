package com.example.guardian_ai

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

class ScreenCaptureService : Service() {
    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "screen_capture_channel"
        
        // Adaptive sampling intervals (in milliseconds)
        private const val HIGH_RISK_INTERVAL = 2000L  // 2 seconds for browsers
        private const val NORMAL_INTERVAL = 10000L     // 10 seconds for normal apps
        private const val LOW_BATTERY_MULTIPLIER = 2   // Double interval when battery < 20%
        
        // High-risk app packages (browsers, social media)
        private val HIGH_RISK_PACKAGES = setOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "org.mozilla.firefox",
            "com.opera.browser",
            "com.microsoft.emmx",
            "com.brave.browser",
            "org.mozilla.focus",
            "com.duckduckgo.mobile.android",
            "com.instagram.android",
            "com.snapchat.android",
            "com.twitter.android",
            "com.facebook.katana",
            "com.whatsapp",
            "com.telegram.messenger"
        )
        
        // Trusted apps (skip analysis)
        private val TRUSTED_PACKAGES = setOf(
            "com.android.calculator2",
            "com.google.android.calculator",
            "com.android.camera",
            "com.google.android.apps.photos",
            "com.android.settings",
            "com.android.dialer",
            "com.android.contacts"
        )
        
        var methodChannel: MethodChannel? = null
        private var instance: ScreenCaptureService? = null
        
        fun start(context: Context, resultCode: Int, data: Intent) {
            val intent = Intent(context, ScreenCaptureService::class.java)
            intent.putExtra("resultCode", resultCode)
            intent.putExtra("data", data)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stop(context: Context) {
            context.stopService(Intent(context, ScreenCaptureService::class.java))
        }
    }
    
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler = Handler(Looper.getMainLooper())
    private var captureRunnable: Runnable? = null
    
    private var screenWidth = 0
    private var screenHeight = 0
    private var screenDensity = 0
    
    private var lastCaptureTime = 0L
    private var currentInterval = NORMAL_INTERVAL
    private var isCapturing = false
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "ScreenCaptureService created")
        
        // Get screen dimensions
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        screenDensity = metrics.densityDpi
        
        Log.d(TAG, "Screen: ${screenWidth}x$screenHeight @ ${screenDensity}dpi")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand called")
        
        // Create notification channel
        createNotificationChannel()
        
        // Start foreground service
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        
        // Get MediaProjection permission data
        val resultCode = intent?.getIntExtra("resultCode", Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        val data = intent?.getParcelableExtra<Intent>("data")
        
        if (resultCode == Activity.RESULT_OK && data != null) {
            startScreenCapture(resultCode, data)
        } else {
            Log.e(TAG, "Invalid MediaProjection permission data")
            stopSelf()
        }
        
        return START_STICKY
    }
    
    private fun startScreenCapture(resultCode: Int, data: Intent) {
        try {
            val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = mediaProjectionManager.getMediaProjection(resultCode, data)
            
            if (mediaProjection == null) {
                Log.e(TAG, "Failed to create MediaProjection")
                stopSelf()
                return
            }
            
            // Create ImageReader for capturing frames
            imageReader = ImageReader.newInstance(
                screenWidth / 2,  // Reduce resolution for performance
                screenHeight / 2,
                PixelFormat.RGBA_8888,
                2
            )
            
            // Create VirtualDisplay
            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "ScreenCapture",
                screenWidth / 2,
                screenHeight / 2,
                screenDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface,
                null,
                null
            )
            
            Log.d(TAG, "Screen capture started successfully")
            isCapturing = true
            
            // Start continuous capture loop
            scheduleNextCapture()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting screen capture", e)
            stopSelf()
        }
    }
    
    private fun scheduleNextCapture() {
        if (!isCapturing) return
        
        // Update interval based on foreground app and battery
        updateCaptureInterval()
        
        captureRunnable = Runnable {
            captureScreen()
            scheduleNextCapture()
        }
        
        handler.postDelayed(captureRunnable!!, currentInterval)
    }
    
    private fun updateCaptureInterval() {
        // Get foreground app
        val foregroundApp = getForegroundApp()
        
        // Determine base interval
        val baseInterval = when {
            foregroundApp in TRUSTED_PACKAGES -> {
                // Skip capture for trusted apps
                currentInterval = Long.MAX_VALUE
                return
            }
            foregroundApp in HIGH_RISK_PACKAGES -> HIGH_RISK_INTERVAL
            else -> NORMAL_INTERVAL
        }
        
        // Adjust for battery level
        val batteryLevel = getBatteryLevel()
        val batteryMultiplier = when {
            batteryLevel < 10 -> 4
            batteryLevel < 20 -> 2
            else -> 1
        }
        
        currentInterval = baseInterval * batteryMultiplier
        
        Log.d(TAG, "Capture interval: ${currentInterval}ms (app: $foregroundApp, battery: $batteryLevel%)")
    }
    
    private fun captureScreen() {
        try {
            val image = imageReader?.acquireLatestImage()
            if (image != null) {
                val bitmap = imageToBitmap(image)
                image.close()
                
                if (bitmap != null) {
                    // Save screenshot to temp file
                    val screenshotFile = saveScreenshot(bitmap)
                    bitmap.recycle()
                    
                    if (screenshotFile != null) {
                        // Send to Flutter for analysis
                        sendScreenshotToFlutter(screenshotFile.absolutePath)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing screen", e)
        }
    }
    
    private fun imageToBitmap(image: Image): Bitmap? {
        try {
            val planes = image.planes
            val buffer: ByteBuffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * image.width
            
            val bitmap = Bitmap.createBitmap(
                image.width + rowPadding / pixelStride,
                image.height,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)
            
            // Crop to actual dimensions if there's padding
            return if (rowPadding > 0) {
                Bitmap.createBitmap(bitmap, 0, 0, image.width, image.height)
            } else {
                bitmap
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error converting image to bitmap", e)
            return null
        }
    }
    
    private fun saveScreenshot(bitmap: Bitmap): File? {
        try {
            val screenshotsDir = File(cacheDir, "screenshots")
            if (!screenshotsDir.exists()) {
                screenshotsDir.mkdirs()
            }
            
            // Clean old screenshots (keep only last 10)
            cleanOldScreenshots(screenshotsDir)
            
            val timestamp = System.currentTimeMillis()
            val file = File(screenshotsDir, "screenshot_$timestamp.jpg")
            
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 70, out)
            }
            
            Log.d(TAG, "Screenshot saved: ${file.absolutePath}")
            return file
        } catch (e: Exception) {
            Log.e(TAG, "Error saving screenshot", e)
            return null
        }
    }
    
    private fun cleanOldScreenshots(dir: File) {
        try {
            val files = dir.listFiles() ?: return
            if (files.size > 10) {
                files.sortedBy { it.lastModified() }
                    .take(files.size - 10)
                    .forEach { it.delete() }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning old screenshots", e)
        }
    }
    
    private fun sendScreenshotToFlutter(path: String) {
        handler.post {
            try {
                methodChannel?.invokeMethod("onScreenshotCaptured", mapOf(
                    "path" to path,
                    "timestamp" to System.currentTimeMillis(),
                    "foregroundApp" to getForegroundApp()
                ))
                Log.d(TAG, "Screenshot sent to Flutter: $path")
            } catch (e: Exception) {
                Log.e(TAG, "Error sending screenshot to Flutter", e)
            }
        }
    }
    
    private fun getForegroundApp(): String? {
        try {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
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
                android.app.usage.UsageStatsManager.INTERVAL_BEST,
                currentTime - 60000,
                currentTime
            )
            
            if (stats != null && stats.isNotEmpty()) {
                val sortedStats = stats.sortedByDescending { it.lastTimeUsed }
                return sortedStats.firstOrNull()?.packageName
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting foreground app", e)
        }
        return null
    }
    
    private fun getBatteryLevel(): Int {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
        return batteryManager.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Monitoring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Guardian AI is monitoring screen content for safety"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Guardian AI Active")
            .setContentText("Monitoring screen for safety")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "ScreenCaptureService destroyed")
        
        isCapturing = false
        captureRunnable?.let { handler.removeCallbacks(it) }
        
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        
        virtualDisplay = null
        imageReader = null
        mediaProjection = null
        instance = null
    }
}
