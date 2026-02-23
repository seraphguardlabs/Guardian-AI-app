package com.example.guardian_ai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts the location foreground service after the device reboots,
 * provided the last active mode was "child".
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val viewMode  = prefs.getString("flutter.view_mode", null)
        val childHash = prefs.getString("flutter.child_hash",  null)

        if (viewMode == "child" && !childHash.isNullOrEmpty()) {
            Log.d("BootReceiver", "📍 Child mode detected – starting LocationForegroundService")
            LocationForegroundService.startService(context)
        } else {
            Log.d("BootReceiver", "Not in child mode or no child_hash – skipping service start")
        }
    }
}
