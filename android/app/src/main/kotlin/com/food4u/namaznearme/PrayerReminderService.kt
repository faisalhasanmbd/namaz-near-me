package com.food4u.namaznearme

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.IBinder
import androidx.core.app.NotificationCompat

class PrayerReminderService : Service() {

    companion object {
        private const val CHANNEL_ID = "namaz_prayer_alert_v1"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Namaz"
        val body = intent?.getStringExtra("body") ?: "Jamaat is starting soon"
        val id = intent?.getIntExtra("id", 1) ?: 1

        val notification = buildNotification(title, body)
        startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)

        // Auto-stop after 30 seconds
        android.os.Handler(mainLooper).postDelayed({ stopSelf() }, 30_000)
        return START_NOT_STICKY
    }

    private fun buildNotification(title: String, body: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
    }

    private fun createChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Namaz Prayer Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Prayer time alerts"
            enableVibration(true)
            setBypassDnd(true)
            val audioAttr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), audioAttr)
        }
        nm.createNotificationChannel(channel)
    }
}
