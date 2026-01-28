package com.sharmadhiraj.installed_apps

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream

class InstalledAppsPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "installed_apps")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getInstalledApps" -> {
                val excludeSystemApps = call.argument<Boolean>("exclude_system_apps") ?: true
                val withIcon = call.argument<Boolean>("with_icon") ?: false
                val packageNamePrefix = call.argument<String>("package_name_prefix") ?: ""
                result.success(getInstalledApps(excludeSystemApps, withIcon, packageNamePrefix))
            }
            "getAppInfo" -> {
                val packageName = call.argument<String>("package_name") ?: ""
                result.success(getAppInfo(packageName))
            }
            "startApp" -> {
                val packageName = call.argument<String>("package_name") ?: ""
                result.success(startApp(packageName))
            }
            "openSettings" -> {
                val packageName = call.argument<String>("package_name") ?: ""
                openSettings(packageName)
                result.success(null)
            }
            "isSystemApp" -> {
                val packageName = call.argument<String>("package_name") ?: ""
                result.success(isSystemApp(packageName))
            }
            else -> result.notImplemented()
        }
    }

    private fun getInstalledApps(
        excludeSystemApps: Boolean,
        withIcon: Boolean,
        packageNamePrefix: String
    ): List<Map<String, Any?>> {
        val packageManager = context.packageManager
        var apps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        
        if (excludeSystemApps) {
            apps = apps.filter { !isSystemApp(it) }
        }
        
        if (packageNamePrefix.isNotEmpty()) {
            apps = apps.filter { it.packageName.startsWith(packageNamePrefix) }
        }
        
        return apps.map { appInfo ->
            getAppInfoMap(appInfo, packageManager, withIcon)
        }
    }

    private fun getAppInfo(packageName: String): Map<String, Any?>? {
        return try {
            val packageManager = context.packageManager
            val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getApplicationInfo(packageName, 0)
            }
            getAppInfoMap(appInfo, packageManager, true)
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun getAppInfoMap(
        appInfo: ApplicationInfo,
        packageManager: PackageManager,
        withIcon: Boolean
    ): Map<String, Any?> {
        val packageInfo = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(appInfo.packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(appInfo.packageName, 0)
            }
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }

        val map = mutableMapOf<String, Any?>(
            "name" to packageManager.getApplicationLabel(appInfo).toString(),
            "package_name" to appInfo.packageName,
            "version_name" to (packageInfo?.versionName ?: ""),
            "version_code" to getVersionCode(packageInfo),
            "built_with" to getBuiltWith(appInfo)
        )

        if (withIcon) {
            try {
                val icon = packageManager.getApplicationIcon(appInfo.packageName)
                map["icon"] = drawableToBase64(icon)
            } catch (e: Exception) {
                map["icon"] = null
            }
        }

        return map
    }

    private fun getVersionCode(packageInfo: PackageInfo?): Long {
        if (packageInfo == null) return 0
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
    }

    private fun getBuiltWith(appInfo: ApplicationInfo): String {
        val sourceDir = appInfo.sourceDir ?: return "unknown"
        // Simple detection based on common patterns
        return when {
            hasFlutterAssets(sourceDir) -> "flutter"
            hasReactNativeAssets(sourceDir) -> "react_native"
            hasXamarinMarkers(appInfo) -> "xamarin"
            else -> "native"
        }
    }

    private fun hasFlutterAssets(sourceDir: String): Boolean {
        // Check for Flutter-specific files
        return try {
            val apkFile = java.util.zip.ZipFile(sourceDir)
            val hasFlutter = apkFile.entries().asSequence().any { entry ->
                entry.name.contains("flutter_assets") || entry.name.contains("libflutter.so")
            }
            apkFile.close()
            hasFlutter
        } catch (e: Exception) {
            false
        }
    }

    private fun hasReactNativeAssets(sourceDir: String): Boolean {
        return try {
            val apkFile = java.util.zip.ZipFile(sourceDir)
            val hasRN = apkFile.entries().asSequence().any { entry ->
                entry.name.contains("libreactnative") || entry.name.contains("index.android.bundle")
            }
            apkFile.close()
            hasRN
        } catch (e: Exception) {
            false
        }
    }

    private fun hasXamarinMarkers(appInfo: ApplicationInfo): Boolean {
        return try {
            val metaData = appInfo.metaData
            metaData?.containsKey("mono.android.app.notificationbuilder") == true
        } catch (e: Exception) {
            false
        }
    }

    private fun isSystemApp(appInfo: ApplicationInfo): Boolean {
        return (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
    }

    private fun isSystemApp(packageName: String): Boolean {
        return try {
            val packageManager = context.packageManager
            val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getApplicationInfo(packageName, 0)
            }
            isSystemApp(appInfo)
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun startApp(packageName: String): Boolean {
        return try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(launchIntent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun openSettings(packageName: String) {
        val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        intent.data = Uri.parse("package:$packageName")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun drawableToBase64(drawable: Drawable): String? {
        return try {
            val bitmap = drawableToBitmap(drawable)
            val byteArrayOutputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
            val byteArray = byteArrayOutputStream.toByteArray()
            Base64.encodeToString(byteArray, Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return drawable.bitmap
        }
        
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
        
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }
}
