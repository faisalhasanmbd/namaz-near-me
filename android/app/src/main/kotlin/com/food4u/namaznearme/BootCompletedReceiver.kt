package com.food4u.namaznearme

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Reschedules prayer alarms after device reboot.
 * Android clears all AlarmManager alarms on reboot. This receiver reads the
 * persisted alarm list from PrayerAlarmStore and re-registers each one.
 *
 * Heavy work must NOT be done here — only lightweight alarm rescheduling.
 * The receiver completes quickly; the actual notification fires later via
 * PrayerReminderService when each alarm triggers.
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON") return

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        val staleThresholdMs = 5 * 60 * 1000L // skip alarms > 5 min in the past

        PrayerAlarmStore.loadAll(context).forEach { alarm ->
            if (alarm.triggerMs < now - staleThresholdMs) return@forEach

            val serviceIntent = Intent(context, PrayerReminderService::class.java).apply {
                putExtra("title", alarm.title)
                putExtra("body", alarm.body)
                putExtra("id", alarm.id)
            }
            val pi = PendingIntent.getForegroundService(
                context,
                alarm.id,
                serviceIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            am.setAlarmClock(AlarmManager.AlarmClockInfo(alarm.triggerMs, pi), pi)
        }
    }
}
