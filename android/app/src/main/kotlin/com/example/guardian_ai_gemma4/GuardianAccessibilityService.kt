package com.example.guardian_ai_gemma4

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.TakeScreenshotCallback
import android.accessibilityservice.AccessibilityService.ScreenshotResult
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.accessibility.AccessibilityEvent

class GuardianAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val loopTask = object : Runnable {
        override fun run() {
            captureAndScore()
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        scheduleNext(1000L)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Monitoring is timer-driven; events are intentionally ignored.
    }

    override fun onInterrupt() {
    }

    private fun captureAndScore() {
        val intervalMs = RiskStore.getCaptureIntervalSeconds(this) * 1000L
        if (!RiskStore.isMonitoringEnabled(this)) {
            scheduleNext(intervalMs)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            scheduleNext(intervalMs)
            return
        }

        val modelPath = RiskStore.getModelPath(this)
        if (modelPath.isNullOrBlank()) {
            scheduleNext(intervalMs)
            return
        }

        GemmaLiteEngine.initialize(modelPath)

        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onFailure(errorCode: Int) {
                    scheduleNext(intervalMs)
                }

                override fun onSuccess(screenshot: ScreenshotResult) {
                    val buffer = screenshot.hardwareBuffer
                    val colorSpace = screenshot.colorSpace
                    val hardwareBitmap = Bitmap.wrapHardwareBuffer(buffer, colorSpace)
                    buffer.close()

                    if (hardwareBitmap == null) {
                        scheduleNext(intervalMs)
                        return
                    }

                    val bitmap = hardwareBitmap.copy(Bitmap.Config.ARGB_8888, false)
                    hardwareBitmap.recycle()

                    if (bitmap == null) {
                        scheduleNext(intervalMs)
                        return
                    }

                    Thread {
                        try {
                            val result = GemmaLiteEngine.score(bitmap)
                            RiskStore.storeRiskSnapshot(this@GuardianAccessibilityService, result)
                        } catch (_: Exception) {
                            // Keep monitoring loop alive even if a single inference fails.
                        } finally {
                            bitmap.recycle()
                            scheduleNext(intervalMs)
                        }
                    }.start()
                }
            }
        )
    }

    private fun scheduleNext(delayMs: Long) {
        handler.removeCallbacks(loopTask)
        handler.postDelayed(loopTask, delayMs)
    }

    companion object {
        @Volatile
        private var instance: GuardianAccessibilityService? = null

        fun requestImmediateCapture() {
            instance?.scheduleNext(500L)
        }
    }
}
