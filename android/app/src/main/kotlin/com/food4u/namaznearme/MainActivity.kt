package com.food4u.namaznearme

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.food4u.namaznearme/prayer_alarm"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createLegacyChannel()
        requestNotificationPermission()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    1001
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val triggerMs = call.argument<Long>("triggerMs") ?: 0L
                        val title = call.argument<String>("title") ?: "Namaz"
                        val body = call.argument<String>("body") ?: "Jamaat is starting soon"
                        schedulePrayerAlarm(id, triggerMs, title, body)
                        result.success(true)
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id") ?: 0
                        cancelPrayerAlarm(id)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun schedulePrayerAlarm(id: Int, triggerMs: Long, title: String, body: String) {
        val am = getSystemService(ALARM_SERVICE) as AlarmManager
        // Use getForegroundService directly — bypasses Samsung's broadcast deferral
        val intent = Intent(this, PrayerReminderService::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
            putExtra("id", id)
        }
        val pi = PendingIntent.getForegroundService(
            this, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val info = AlarmManager.AlarmClockInfo(triggerMs, pi)
        am.setAlarmClock(info, pi)
        // Persist so BootCompletedReceiver can reschedule after reboot
        PrayerAlarmStore.save(this, id, triggerMs, title, body)
    }

    private fun cancelPrayerAlarm(id: Int) {
        val am = getSystemService(ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, PrayerReminderService::class.java)
        val pi = PendingIntent.getForegroundService(
            this, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.cancel(pi)
        PrayerAlarmStore.remove(this, id)
    }

    // Keep the old flutter_local_notifications channel alive so old reminders still work
    private fun createLegacyChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            "namaz_reminders_v5",
            "Namaz Prayer Reminders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Prayer time alerts"
            enableVibration(true)
            setBypassDnd(true)
            val audioAttr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(android.provider.Settings.System.DEFAULT_ALARM_ALERT_URI, audioAttr)
        }
        nm.createNotificationChannel(channel)
    }
}
