package com.example.guardian_ai

import android.accessibilityservice.AccessibilityService
import android.net.Uri
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class WebsiteMonitoringService : AccessibilityService() {

    companion object {
        private const val TAG = "WebsiteMonitor"
        
        // Browser package names
        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "org.mozilla.firefox",
            "com.brave.browser",
            "com.opera.browser",
            "com.microsoft.emmx",
            "com.duckduckgo.mobile.android",
            "com.sec.android.app.sbrowser",
            "com.UCMobile.intl",
            "com.kiwibrowser.browser"
        )
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || 
            event?.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            
            val packageName = event.packageName?.toString() ?: return
            
            // Check if it's a browser
            if (BROWSER_PACKAGES.contains(packageName)) {
                val source = event.source ?: return
                
                // Extract and track URL
                extractUrl(source)?.let { url ->
                    if (url.isNotBlank() && !url.contains("incognito", ignoreCase = true)) {
                        WebsiteDataStore.addWebsite(url)
                        Log.d(TAG, "Website tracked: $url")
                    }
                }
                
                source.recycle()
            }
        }
    }

    private fun extractUrl(node: AccessibilityNodeInfo): String? {
        // Try to find URL in address bar
        val urlNodes = findUrlNodes(node)
        
        for (urlNode in urlNodes) {
            val text = urlNode.text?.toString()
            if (!text.isNullOrBlank() && isValidUrl(text)) {
                return cleanUrl(text)
            }
        }
        
        return null
    }

    private fun findUrlNodes(root: AccessibilityNodeInfo): List<AccessibilityNodeInfo> {
        val nodes = mutableListOf<AccessibilityNodeInfo>()
        
        // Common URL bar identifiers
        val urlIdentifiers = listOf(
            "url_bar", "location_bar", "addressbar", "search_box",
            "com.android.chrome:id/url_bar",
            "org.mozilla.firefox:id/url_bar_title",
            "com.brave.browser:id/url_bar"
        )
        
        fun traverse(node: AccessibilityNodeInfo) {
            // Check if this node is a URL bar
            val viewId = node.viewIdResourceName?.lowercase()
            val className = node.className?.toString()?.lowercase()
            
            if (viewId != null && urlIdentifiers.any { viewId.contains(it) }) {
                nodes.add(node)
            } else if (className?.contains("edittext") == true || className?.contains("textview") == true) {
                val text = node.text?.toString()
                if (!text.isNullOrBlank() && isValidUrl(text)) {
                    nodes.add(node)
                }
            }
            
            // Traverse children
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { traverse(it) }
            }
        }
        
        traverse(root)
        return nodes
    }

    private fun isValidUrl(text: String): Boolean {
        val lowerText = text.lowercase()
        return (lowerText.startsWith("http://") || 
                lowerText.startsWith("https://") || 
                lowerText.contains(".com") || 
                lowerText.contains(".org") || 
                lowerText.contains(".net")) &&
                !lowerText.contains("search") &&
                !lowerText.contains("type a url") &&
                text.length > 5
    }

    private fun cleanUrl(url: String): String {
        var cleaned = url.trim()
        
        // Add protocol if missing
        if (!cleaned.startsWith("http://") && !cleaned.startsWith("https://")) {
            cleaned = "https://$cleaned"
        }
        
        // Extract just the domain if it's a full URL
        try {
            val uri = Uri.parse(cleaned)
            val host = uri.host
            if (!host.isNullOrBlank()) {
                return host
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing URL: ${e.message}")
        }
        
        return cleaned
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service interrupted")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        // Initialize WebsiteDataStore with application context
        WebsiteDataStore.init(applicationContext)
        Log.d(TAG, "Website monitoring service connected")
    }
}
