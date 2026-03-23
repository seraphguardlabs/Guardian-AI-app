package com.example.guardian_ai

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray

object WebsiteDataStore {
    private const val PREFS_NAME = "website_monitoring"
    private const val KEY_WEBSITES = "visited_websites"
    private var sharedPreferences: SharedPreferences? = null
    
    fun init(context: Context) {
        sharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    
    fun addWebsite(url: String) {
        val prefs = sharedPreferences ?: return
        val websites = getWebsitesList()
        
        // Use a list of maps to maintain order and structure
        val entry = mapOf(
            "url" to url,
            "timestamp" to System.currentTimeMillis().toString()
        )
        
        // Limit to last 50 entries and avoid duplicates (simple logic: if same URL exists, replace it with new timestamp)
        val filteredList = websites.filter { it["url"] != url }.toMutableList()
        filteredList.add(0, entry) // Add at start (newest first)
        
        if (filteredList.size > 50) {
            filteredList.removeAt(filteredList.size - 1)
        }
        
        saveWebsites(filteredList)
    }
    
    fun getWebsites(): List<Map<String, String>> {
        return getWebsitesList()
    }
    
    fun clear() {
        sharedPreferences?.edit()?.remove(KEY_WEBSITES)?.apply()
    }
    
    fun getWebsitesCount(): Int {
        return getWebsitesList().size
    }
    
    private fun getWebsitesList(): List<Map<String, String>> {
        val prefs = sharedPreferences ?: return emptyList()
        val jsonString = prefs.getString(KEY_WEBSITES, "[]") ?: "[]"
        val websites = mutableListOf<Map<String, String>>()
        
        try {
            val jsonArray = JSONArray(jsonString)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                websites.add(mapOf(
                    "url" to obj.getString("url"),
                    "timestamp" to obj.optString("timestamp", System.currentTimeMillis().toString())
                ))
            }
        } catch (e: Exception) {
            e.printStackTrace()
            // Fallback for old simple string array format
            try {
                val jsonArray = JSONArray(jsonString)
                for (i in 0 until jsonArray.length()) {
                    websites.add(mapOf(
                        "url" to jsonArray.getString(i),
                        "timestamp" to System.currentTimeMillis().toString()
                    ))
                }
            } catch (inner: Exception) {}
        }
        
        return websites
    }
    
    private fun saveWebsites(websites: List<Map<String, String>>) {
        val prefs = sharedPreferences ?: return
        val jsonArray = JSONArray()
        websites.forEach { entry ->
            val obj = org.json.JSONObject()
            obj.put("url", entry["url"])
            obj.put("timestamp", entry["timestamp"])
            jsonArray.put(obj)
        }
        prefs.edit().putString(KEY_WEBSITES, jsonArray.toString()).apply()
    }
}
