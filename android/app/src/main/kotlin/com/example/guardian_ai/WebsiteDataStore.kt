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
        val websites = getWebsitesSet()
        websites.add(url)
        saveWebsites(websites)
    }
    
    fun getWebsites(): List<String> {
        val websites = getWebsitesSet()
        return websites.toList().sortedDescending()
    }
    
    fun clear() {
        sharedPreferences?.edit()?.remove(KEY_WEBSITES)?.apply()
    }
    
    fun getWebsitesCount(): Int {
        return getWebsitesSet().size
    }
    
    private fun getWebsitesSet(): MutableSet<String> {
        val prefs = sharedPreferences ?: return mutableSetOf()
        val jsonString = prefs.getString(KEY_WEBSITES, "[]") ?: "[]"
        val websites = mutableSetOf<String>()
        
        try {
            val jsonArray = JSONArray(jsonString)
            for (i in 0 until jsonArray.length()) {
                websites.add(jsonArray.getString(i))
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return websites
    }
    
    private fun saveWebsites(websites: Set<String>) {
        val prefs = sharedPreferences ?: return
        val jsonArray = JSONArray()
        websites.forEach { jsonArray.put(it) }
        prefs.edit().putString(KEY_WEBSITES, jsonArray.toString()).apply()
    }
}
