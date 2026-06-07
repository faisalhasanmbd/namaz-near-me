package com.food4u.namaznearme

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class PrayerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val serviceIntent = Intent(context, PrayerReminderService::class.java).apply {
            putExtra("title", intent.getStringExtra("title") ?: "Namaz")
            putExtra("body", intent.getStringExtra("body") ?: "Jamaat is starting soon")
            putExtra("id", intent.getIntExtra("id", 0))
        }
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
