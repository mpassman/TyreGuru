package com.tyreguru.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/** Shows a sealant-check reminder at the time the page asked for. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("reminders", "Sealant checks", NotificationManager.IMPORTANCE_DEFAULT))
        val n = NotificationCompat.Builder(c, "reminders").setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(i.getStringExtra("title") ?: "TyreGuru").setContentText(i.getStringExtra("body") ?: "").setAutoCancel(true).build()
        try { nm.notify((i.getStringExtra("id") ?: "tg").hashCode(), n) } catch (e: SecurityException) {}
    }
}
