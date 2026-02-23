package com.example.guardian_ai

import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import org.json.JSONObject
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*

class LocationForegroundService : Service() {

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private val NOTIFICATION_ID = 1002            // distinct from ScreenCaptureService (1001)
    private val CHANNEL_ID = "guardian_ai_location_channel"

    // Throttle: send to server at most once every 30 seconds
    private var lastSendTimeMs: Long = 0
    private val SEND_INTERVAL_MS = 30_000L

    // Flutter SharedPreferences constants (flutter plugin stores with "flutter." prefix)
    private val FLUTTER_PREFS = "FlutterSharedPreferences"
    private val KEY_CHILD_HASH = "flutter.child_hash"
    private val KEY_VIEW_MODE  = "flutter.view_mode"

    private val API_INGEST_URL = "https://seraphguardlabs.com/api/ingest/"

    companion object {
        var isServiceRunning = false

        fun startService(context: Context) {
            val intent = Intent(context, LocationForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, LocationForegroundService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        startLocationUpdates()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, createNotification())
        isServiceRunning = true
        return START_STICKY          // restart automatically if killed by OS
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        if (::locationCallback.isInitialized) {
            fusedLocationClient.removeLocationUpdates(locationCallback)
        }
        isServiceRunning = false
    }

    // ─── Notification helpers ────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Guardian AI Location",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background location tracking active"
                setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Guardian AI – Location Active")
            .setContentText("Your location is being monitored for safety.")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    // ─── Location updates ────────────────────────────────────────────────────

    private fun startLocationUpdates() {
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            15_000L        // request every 15 s (saves battery vs. 1 s)
        ).apply {
            setMinUpdateIntervalMillis(10_000L)
            setWaitForAccurateLocation(false)
            setMaxUpdateDelayMillis(20_000L)
        }.build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.lastLocation?.let { handleLocationUpdate(it) }
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest, locationCallback, Looper.getMainLooper()
            )
        } catch (e: SecurityException) {
            android.util.Log.e("LocationService", "Location permission missing: ${e.message}")
        }
    }

    // ─── Core: send location to backend ─────────────────────────────────────

    private fun handleLocationUpdate(location: Location) {
        android.util.Log.d("LocationService",
            "📍 Location: ${location.latitude}, ${location.longitude}")

        val now = System.currentTimeMillis()
        if (now - lastSendTimeMs < SEND_INTERVAL_MS) return   // throttle
        lastSendTimeMs = now

        val prefs = getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val childHash = prefs.getString(KEY_CHILD_HASH, null)
        val viewMode  = prefs.getString(KEY_VIEW_MODE,  null)

        if (childHash.isNullOrEmpty()) {
            android.util.Log.w("LocationService", "⚠️ No child_hash in prefs – skipping send")
            return
        }
        if (viewMode != "child") {
            android.util.Log.d("LocationService", "Not in child mode ($viewMode) – skipping")
            return
        }

        val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(now))

        // Build JSON payload matching the /api/ingest/ endpoint
        val payload = JSONObject().apply {
            put("location_info", JSONObject().apply {
                put("child_hash", childHash)
                put("timestamp",  timestamp)
                put("latitude",   location.latitude)
                put("longitude",  location.longitude)
            })
        }.toString()

        // Must run HTTP on a background thread
        Thread {
            postLocation(payload)
        }.start()
    }

    private fun postLocation(payload: String) {
        var conn: HttpURLConnection? = null
        try {
            conn = (URL(API_INGEST_URL).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/json")
                doOutput = true
                connectTimeout = 10_000
                readTimeout = 10_000
            }
            val bytes = payload.toByteArray(Charsets.UTF_8)
            conn.outputStream.use { it.write(bytes) }
            val status = conn.responseCode
            android.util.Log.d("LocationService",
                if (status in 200..299) "✅ Location sent (HTTP $status)"
                else "❌ Location send failed (HTTP $status)"
            )
        } catch (e: Exception) {
            android.util.Log.e("LocationService", "❌ Network error: ${e.message}")
        } finally {
            conn?.disconnect()
        }
    }
}

