package com.food4u.namaznearme

import android.content.Context
import android.util.Base64

data class AlarmData(val id: Int, val triggerMs: Long, val title: String, val body: String)

/**
 * Persists scheduled prayer alarm data in SharedPreferences so that
 * BootCompletedReceiver can reschedule them after device reboot.
 * AlarmManager clears all alarms on reboot — this store is the only
 * way to survive that.
 */
object PrayerAlarmStore {
    private const val PREFS_NAME = "prayer_alarms"
    private const val KEY_ALARMS = "alarms"

    fun save(context: Context, id: Int, triggerMs: Long, title: String, body: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = prefs.getStringSet(KEY_ALARMS, emptySet())!!.toMutableSet()
        existing.removeAll { it.startsWith("$id|") }
        existing.add("$id|$triggerMs|${encode(title)}|${encode(body)}")
        prefs.edit().putStringSet(KEY_ALARMS, existing).apply()
    }

    fun remove(context: Context, id: Int) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = prefs.getStringSet(KEY_ALARMS, emptySet())!!.toMutableSet()
        existing.removeAll { it.startsWith("$id|") }
        prefs.edit().putStringSet(KEY_ALARMS, existing).apply()
    }

    fun loadAll(context: Context): List<AlarmData> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return (prefs.getStringSet(KEY_ALARMS, emptySet()) ?: emptySet())
            .mapNotNull { parse(it) }
    }

    private fun encode(value: String): String =
        Base64.encodeToString(value.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)

    private fun parse(entry: String): AlarmData? {
        val parts = entry.split("|")
        if (parts.size < 4) return null
        return try {
            AlarmData(
                id = parts[0].toInt(),
                triggerMs = parts[1].toLong(),
                title = String(Base64.decode(parts[2], Base64.NO_WRAP), Charsets.UTF_8),
                body = String(Base64.decode(parts[3], Base64.NO_WRAP), Charsets.UTF_8),
            )
        } catch (_: Exception) {
            null
        }
    }
}
