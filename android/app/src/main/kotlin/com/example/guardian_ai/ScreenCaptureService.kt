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
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * Captures a screenshot every 5 seconds using a **persistent** VirtualDisplay.
 *
 * Previous design created / destroyed a VirtualDisplay + ImageReader on every
 * capture tick, which caused heavy GC pressure, race conditions between the
 * image-available listener and the timeout handler, and frequent OOM crashes.
 *
 * New approach:
 *  1. A single ImageReader + VirtualDisplay is created once when the service
 *     starts and kept alive for the entire session.
 *  2. A repeating Handler tick (every 5 s) calls `acquireLatestImage()` to
 *     grab whatever frame the display has rendered most recently, converts it
 *     to a JPEG, and sends the path to Flutter.
 *  3. Only one screenshot file exists at a time (`latest.jpg`) – no
 *     accumulation, no old-file cleanup needed.
 *  4. A `pendingFlutterDelivery` flag provides back-pressure: if Flutter
 *     hasn't consumed the previous screenshot yet, the tick is skipped.
 */
class ScreenCaptureService : Service() {
    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "screen_capture_channel"

        /** Fixed capture interval – one screenshot every 5 seconds. */
        private const val CAPTURE_INTERVAL_MS = 5000L

        var methodChannel: MethodChannel? = null
        private var instance: ScreenCaptureService? = null

        val isRunning: Boolean get() = instance?.isCapturing == true

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

    // ── Persistent capture resources (created once, released on destroy) ──
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    private val handler = Handler(Looper.getMainLooper())
    private var tickRunnable: Runnable? = null

    private var screenWidth = 0
    private var screenHeight = 0
    private var captureWidth = 0
    private var captureHeight = 0
    private var screenDensity = 0

    private var isCapturing = false

    /**
     * Back-pressure flag. Set to `true` when a screenshot is sent to Flutter;
     * cleared when Flutter finishes processing (or on the next tick if the
     * channel call threw). Prevents unbounded queue growth on the Dart side.
     */
    @Volatile
    private var pendingFlutterDelivery = false

    // Reusable file – only one screenshot on disk at any time
    private lateinit var screenshotFile: File
    private var lastFrameJpegBytes: ByteArray? = null

    // ─────────────────────────────────────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "ScreenCaptureService created")

        // Log device information for diagnostic purposes
        Log.d(TAG, "Device Info: ${Build.MANUFACTURER} ${Build.MODEL} (API ${Build.VERSION.SDK_INT})")

        // Use half-resolution to save memory
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        wm.defaultDisplay.getRealMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        screenDensity = metrics.densityDpi

        // Prepare single screenshot file
        val dir = File(cacheDir, "screenshots")
        if (!dir.exists()) dir.mkdirs()
        screenshotFile = File(dir, "latest.jpg")

        Log.d(TAG, "Screen metrics: ${screenWidth}x$screenHeight @ ${screenDensity}dpi")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand called")

        createNotificationChannel()

        val notification = createNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground: ${e.message}")
        }

        val resultCode = intent?.getIntExtra("resultCode", Activity.RESULT_CANCELED)
            ?: Activity.RESULT_CANCELED
        val data = intent?.getParcelableExtra<Intent>("data")

        if (resultCode == Activity.RESULT_OK && data != null) {
            startScreenCapture(resultCode, data)
        } else {
            Log.e(TAG, "Invalid MediaProjection permission data")
            stopSelf()
        }

        return START_STICKY
    }

    // ── Core capture setup (runs once) ───────────────────────────────────────
    private fun startScreenCapture(resultCode: Int, data: Intent) {
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = mpm.getMediaProjection(resultCode, data)

            if (mediaProjection == null) {
                Log.e(TAG, "Failed to create MediaProjection")
                stopSelf()
                return
            }

            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.w(TAG, "MediaProjection stopped by system")
                    tearDown()
                }
            }, handler)

            // Create a persistent ImageReader (maxImages = 2)
            // FIXED OPTIMIZATION: Scale down to 448px baseline for Gemma 3 Vision processing speed (< 5s target)
            val scaleFactor = 448f / Math.max(screenWidth, screenHeight).toFloat()
            this.captureWidth = (screenWidth * scaleFactor).toInt()
            this.captureHeight = (screenHeight * scaleFactor).toInt()

            Log.d(TAG, "ImageReader dimensions: ${this.captureWidth}x${this.captureHeight}")

            try {
                imageReader = ImageReader.newInstance(
                    this.captureWidth, this.captureHeight,
                    PixelFormat.RGBA_8888, 2
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create ImageReader, retrying with smaller buffer", e)
                // Fallback: try with max 1 image in buffer
                imageReader = ImageReader.newInstance(
                    this.captureWidth, this.captureHeight,
                    PixelFormat.RGBA_8888, 1
                )
            }

            // Create ONE VirtualDisplay that mirrors the screen into the reader.
            try {
                virtualDisplay = mediaProjection?.createVirtualDisplay(
                    "GuardianCapture",
                    this.captureWidth, this.captureHeight, screenDensity,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    imageReader!!.surface,
                    null, null
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create VirtualDisplay", e)
                imageReader?.close()
                imageReader = null
                throw e
            }

            if (virtualDisplay == null) {
                Log.e(TAG, "VirtualDisplay creation returned null")
                imageReader?.close()
                imageReader = null
                stopSelf()
                return
            }

            isCapturing = true
            Log.d(TAG, "Persistent VirtualDisplay created – capturing every ${CAPTURE_INTERVAL_MS}ms")

            // Start the repeating tick
            scheduleTick()

        } catch (e: Exception) {
            Log.e(TAG, "Error starting screen capture: ${e.message}", e)
            stopSelf()
        }
    }

    // ── Repeating 5-second tick ──────────────────────────────────────────────
    private fun scheduleTick() {
        if (!isCapturing) return

        tickRunnable = Runnable {
            grabLatestFrame()
            scheduleTick()          // schedule the next tick
        }
        handler.postDelayed(tickRunnable!!, CAPTURE_INTERVAL_MS)
    }

    /**
     * Grab the most recent frame the VirtualDisplay has rendered into the
     * ImageReader. If no new frame is available (e.g. screen hasn't changed),
     * `acquireLatestImage()` returns null — we simply skip silently.
     */
    private fun grabLatestFrame() {
        if (!isCapturing) return

        // Back-pressure: skip if Flutter hasn't finished processing the last one
        if (pendingFlutterDelivery) {
            Log.d(TAG, "Skipping capture – Flutter still processing previous screenshot")
            return
        }

        val reader = imageReader ?: return
        var image: Image? = null
        var bitmap: Bitmap? = null
        try {
            image = reader.acquireLatestImage()
            if (image == null) {
                // If screen is static, ImageReader may return null. Reuse the
                // last frame so downstream AI analysis cadence stays consistent.
                val fallbackBytes = lastFrameJpegBytes
                if (fallbackBytes != null && saveJpegBytesToFile(fallbackBytes)) {
                    Log.d(TAG, "No new frame available; reusing previous screenshot")
                    sendScreenshotToFlutter(screenshotFile.absolutePath)
                }
                return
            }

            // Convert image to bitmap with safety checks
            bitmap = imageToBitmap(image)
            if (bitmap == null) {
                Log.w(TAG, "Failed to convert image to bitmap, reusing previous screenshot")
                val fallbackBytes = lastFrameJpegBytes
                if (fallbackBytes != null && saveJpegBytesToFile(fallbackBytes)) {
                    sendScreenshotToFlutter(screenshotFile.absolutePath)
                }
                return
            }

            val jpegBytes = bitmapToJpegBytes(bitmap)
            if (jpegBytes == null) {
                Log.w(TAG, "Failed to encode bitmap to JPEG")
                return
            }

            if (saveJpegBytesToFile(jpegBytes)) {
                lastFrameJpegBytes = jpegBytes
                sendScreenshotToFlutter(screenshotFile.absolutePath)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error grabbing frame: ${e.message}", e)
        } finally {
            // Always clean up resources
            try { bitmap?.recycle() } catch (_: Exception) {}
            try { image?.close() } catch (_: Exception) {}
        }
    }

    // ── Bitmap conversion (device-safe with fallback) ─────────────────────────
    private fun imageToBitmap(image: Image): Bitmap? {
        return try {
            // Validate image format and planes
            if (image.planes.isEmpty()) {
                Log.e(TAG, "Image has no planes")
                return null
            }

            val plane = image.planes[0]
            val buffer: ByteBuffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride   = plane.rowStride
            val width = image.width
            val height = image.height

            // Validate stride configuration
            if (pixelStride <= 0 || rowStride <= 0) {
                Log.e(TAG, "Invalid stride: pixelStride=$pixelStride, rowStride=$rowStride")
                return null
            }

            // Calculate row padding – check for negative values
            val rowPadding = rowStride - pixelStride * width
            
            if (rowPadding < 0) {
                // Device has stride < width*pixelStride; copy row-by-row instead
                Log.d(TAG, "Negative rowPadding=$rowPadding; using row-by-row copy")
                return copyImageRowByRow(image, plane, buffer, pixelStride, rowStride, width, height)
            }

            // Standard path: attempt direct buffer copy
            try {
                val bitmapWidth = if (rowPadding > 0) width + rowPadding / pixelStride else width
                val bmp = Bitmap.createBitmap(bitmapWidth, height, Bitmap.Config.ARGB_8888)
                bmp.copyPixelsFromBuffer(buffer)

                return if (rowPadding > 0) {
                    val cropped = Bitmap.createBitmap(bmp, 0, 0, width, height)
                    bmp.recycle()
                    cropped
                } else {
                    bmp
                }
            } catch (bufferEx: Exception) {
                // If direct buffer copy fails, fall back to row-by-row
                Log.w(TAG, "Direct buffer copy failed (${bufferEx.message}), using row-by-row copy")
                return copyImageRowByRow(image, plane, buffer, pixelStride, rowStride, width, height)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error converting image to bitmap", e)
            null
        }
    }

    /**
     * Fallback: Copy image data row-by-row to avoid stride issues on problematic devices.
     * This is more robust for devices with unusual buffer configurations.
     */
    private fun copyImageRowByRow(
        image: Image,
        plane: Image.Plane,
        buffer: ByteBuffer,
        pixelStride: Int,
        rowStride: Int,
        width: Int,
        height: Int
    ): Bitmap? {
        return try {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            buffer.position(0)
            
            val pixelData = IntArray(width)
            for (y in 0 until height) {
                buffer.position(y * rowStride)
                for (x in 0 until width) {
                    val offset = x * pixelStride
                    // Read ARGB pixel from RGBA format
                    val a = buffer.get(offset + 3).toInt() and 0xFF
                    val r = buffer.get(offset + 0).toInt() and 0xFF
                    val g = buffer.get(offset + 1).toInt() and 0xFF
                    val b = buffer.get(offset + 2).toInt() and 0xFF
                    pixelData[x] = (a shl 24) or (r shl 16) or (g shl 8) or b
                }
                bitmap.setPixels(pixelData, 0, width, 0, y, width, 1)
            }
            bitmap
        } catch (e: Exception) {
            Log.e(TAG, "Error in row-by-row copy: ${e.message}", e)
            null
        }
    }

    // ── File I/O (single file, overwritten each time) ────────────────────────
    private fun bitmapToJpegBytes(bitmap: Bitmap): ByteArray? {
        return try {
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 60, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            Log.e(TAG, "Error encoding screenshot", e)
            null
        }
    }

    private fun saveJpegBytesToFile(jpegBytes: ByteArray): Boolean {
        return try {
            FileOutputStream(screenshotFile).use { out ->
                out.write(jpegBytes)
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error saving screenshot", e)
            false
        }
    }

    // ── Flutter communication ────────────────────────────────────────────────
    private fun sendScreenshotToFlutter(path: String) {
        pendingFlutterDelivery = true
        handler.post {
            try {
                methodChannel?.invokeMethod(
                    "onScreenshotCaptured",
                    mapOf(
                        "path" to path,
                        "timestamp" to System.currentTimeMillis(),
                        "foregroundApp" to getForegroundApp()
                    )
                )
                Log.d(TAG, "Screenshot sent to Flutter")
            } catch (e: Exception) {
                Log.e(TAG, "Error sending screenshot to Flutter", e)
            } finally {
                // Release back-pressure regardless of success/failure so the
                // next tick can proceed.
                pendingFlutterDelivery = false
            }
        }
    }

    // ── Foreground-app detection ─────────────────────────────────────────────
    private fun getForegroundApp(): String? {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
            val now = System.currentTimeMillis()

            val events = usm.queryEvents(now - 60_000, now)
            var fg: String? = null
            val ev = android.app.usage.UsageEvents.Event()

            while (events.hasNextEvent()) {
                events.getNextEvent(ev)
                when (ev.eventType) {
                    android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED,
                    android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND -> fg = ev.packageName
                    android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED,
                    android.app.usage.UsageEvents.Event.ACTIVITY_STOPPED,
                    android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                        if (fg == ev.packageName) fg = null
                    }
                }
            }
            fg
        } catch (e: Exception) {
            Log.e(TAG, "Error getting foreground app", e)
            null
        }
    }

    // ── Notification ─────────────────────────────────────────────────────────
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
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Guardian AI Active")
            .setContentText("Monitoring screen for safety")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentIntent(pi)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────
    override fun onBind(intent: Intent?): IBinder? = null

    private fun tearDown() {
        isCapturing = false
        tickRunnable?.let { handler.removeCallbacks(it) }
        try { virtualDisplay?.release() }  catch (_: Exception) {}
        try { imageReader?.close() }       catch (_: Exception) {}
        virtualDisplay = null
        imageReader = null
        lastFrameJpegBytes = null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "ScreenCaptureService destroyed")
        tearDown()
        mediaProjection?.stop()
        mediaProjection = null
        instance = null
    }
}
