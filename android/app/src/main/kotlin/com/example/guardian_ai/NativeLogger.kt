package com.example.guardian_ai

import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*

object NativeLogger {
    private const val TAG = "NativeLogger"
    private var logFile: File? = null
    private val dateFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    fun init(filePath: String) {
        try {
            logFile = File(filePath)
            log("🚀 Native Logger initialised — path: $filePath")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to init NativeLogger: ${e.message}")
        }
    }

    fun log(message: String) {
        val ts = dateFormat.format(Date())
        val line = "[$ts] [Native] $message"
        
        // Log to Android Logcat
        Log.d("GuardianAI", line)
        
        // Write to shared file
        try {
            logFile?.let { file ->
                FileOutputStream(file, true).use { out ->
                    out.write("$line\n".toByteArray())
                    out.flush()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error writing to log file: ${e.message}")
        }
    }

    fun logError(message: String, e: Throwable? = null) {
        log("❌ ERROR: $message ${e?.message ?: ""}")
    }
}
