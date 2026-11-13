package com.tyreguru.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/** Keeps the Bluetooth link to a paired TyreWiz alive while the app is in the background (Android needs a visible notice for this). */
class TyreWizService : Service() {
    override fun onBind(i: Intent?): IBinder? = null
    override fun onStartCommand(i: Intent?, f: Int, id: Int): Int {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("tyrewiz", "TyreWiz sensor", NotificationManager.IMPORTANCE_LOW))
        val n: Notification = NotificationCompat.Builder(this, "tyrewiz").setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("TyreGuru").setContentText("Listening for your TyreWiz sensor").setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(7, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE) else startForeground(7, n)
        TyreWizBle.attach(applicationContext)
        TyreWizBle.connectPaired()
        return START_STICKY
    }
}
