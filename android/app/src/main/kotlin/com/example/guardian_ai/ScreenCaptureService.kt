package com.example.guardian_ai

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
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
import java.io.ByteArrayOutputStream

/**
 * Captures the screen on a fixed interval and delivers JPEG frames to Flutter
 * via an EventChannel as raw ByteArray — NO file I/O, NO MethodChannel callbacks.
 *
 * Architecture matches gemma3n's ScreenCaptureService exactly:
 *   • One persistent VirtualDisplay + ImageReader for the session.
 *   • Repeating Handler tick acquires the latest frame.
 *   • Bytes are sent to [MainActivity.sendFrameToFlutter] → EventSink → Dart.
 *   • If the screen is static (null image), the last frame is re-sent so the
 *     Dart-side watchdog timer does not time out.
 */
class ScreenCaptureService : Service() {

    companion object {
        private const val TAG = "ScreenCaptureService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "guardian_screen_capture"

        /** One frame every 30 seconds — same cadence as gemma3n. */
        private const val CAPTURE_INTERVAL_MS = 30_000L

        private var instance: ScreenCaptureService? = null
        val isRunning: Boolean get() = instance != null

        fun start(context: Context, resultCode: Int, data: Intent) {
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                putExtra("code", resultCode)
                putExtra("data", data)
            }
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

    // ── Capture resources ────────────────────────────────────────────────────
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    private val handler = Handler(Looper.getMainLooper())

    private var screenWidth = 0
    private var screenHeight = 0
    private var screenDensity = 0

    /** Last successfully encoded JPEG — re-sent when ImageReader returns null. */
    private var lastFrameBytes: ByteArray? = null

    private val captureRunnable = object : Runnable {
        override fun run() {
            captureFrame()
            handler.postDelayed(this, CAPTURE_INTERVAL_MS)
        }
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "onCreate")

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        screenDensity = metrics.densityDpi

        Log.d(TAG, "Screen: ${screenWidth}x${screenHeight} @ ${screenDensity}dpi")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand")
        createNotificationChannel()
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        val resultCode = intent?.getIntExtra("code", 0) ?: 0
        val data = intent?.getParcelableExtra<Intent>("data")

        if (resultCode != Activity.RESULT_OK || data == null) {
            Log.e(TAG, "Invalid projection data — stopping")
            stopSelf()
            return START_NOT_STICKY
        }

        startProjection(resultCode, data)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        super.onDestroy()
        tearDown()
        instance = null
    }

    // ── Projection setup ─────────────────────────────────────────────────────
    private fun startProjection(resultCode: Int, data: Intent) {
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data)

        if (mediaProjection == null) {
            Log.e(TAG, "❌ MediaProjection is null — stopping")
            stopSelf()
            return
        }

        mediaProjection!!.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Log.w(TAG, "MediaProjection revoked by system")
                tearDown()
                stopSelf()
            }
        }, handler)

        setupVirtualDisplay()

        // First capture after 3 s (VirtualDisplay warm-up), then every 30 s
        handler.postDelayed(captureRunnable, 3_000L)
        Log.d(TAG, "✅ Projection running — first frame in 3s")
    }

    private fun setupVirtualDisplay() {
        // 50 % scale keeps memory usage low while preserving enough detail for Gemma
        val scale = 0.5f
        val w = (screenWidth * scale).toInt()
        val h = (screenHeight * scale).toInt()

        if (w == 0 || h == 0) {
            Log.e(TAG, "❌ Zero dimensions — aborting VirtualDisplay setup")
            return
        }

        imageReader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "GuardianCapture", w, h, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )

        Log.d(TAG, "VirtualDisplay: ${w}x${h}")
    }

    // ── Frame capture ────────────────────────────────────────────────────────
    private fun captureFrame() {
        val reader = imageReader ?: return
        val image = reader.acquireLatestImage()

        if (image != null) {
            try {
                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * image.width

                val bitmapWidth = image.width + rowPadding / pixelStride

                val bitmap = Bitmap.createBitmap(bitmapWidth, image.height, Bitmap.Config.ARGB_8888)

                // Copy buffer safely to avoid "Buffer not large enough" exceptions
                buffer.position(0)
                val pixelArray = ByteArray(bitmap.byteCount)
                buffer.get(pixelArray, 0, buffer.remaining().coerceAtMost(pixelArray.size))
                bitmap.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(pixelArray))

                val cropped = Bitmap.createBitmap(bitmap, 0, 0, image.width, image.height)

                val out = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.JPEG, 60, out)
                val bytes = out.toByteArray()

                bitmap.recycle()
                cropped.recycle()

                Log.d(TAG, "📸 Frame: ${bytes.size} bytes")
                lastFrameBytes = bytes
                MainActivity.sendFrameToFlutter(bytes)

            } catch (e: Exception) {
                Log.e(TAG, "❌ Frame processing error: ${e.message}", e)
            } finally {
                image.close()
            }
        } else {
            // Screen unchanged — resend last frame so watchdog doesn't time out
            val fallback = lastFrameBytes
            if (fallback != null) {
                Log.d(TAG, "No new frame — reusing last (${fallback.size} bytes)")
                MainActivity.sendFrameToFlutter(fallback)
            } else {
                Log.w(TAG, "No frame available yet")
            }
        }
    }

    // ── Teardown ─────────────────────────────────────────────────────────────
    private fun tearDown() {
        handler.removeCallbacks(captureRunnable)
        try { virtualDisplay?.release() } catch (_: Exception) {}
        try { imageReader?.close() } catch (_: Exception) {}
        try { mediaProjection?.stop() } catch (_: Exception) {}
        virtualDisplay = null
        imageReader = null
        mediaProjection = null
        lastFrameBytes = null
    }

    // ── Notification ─────────────────────────────────────────────────────────
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Guardian AI Screen Monitor",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Monitoring screen content for child safety" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Guardian AI Active")
            .setContentText("Monitoring screen for child safety")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentIntent(pi)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
