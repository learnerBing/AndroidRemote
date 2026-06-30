package com.androidremote.tv.data.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.androidremote.tv.AndroidRemoteApp
import com.androidremote.tv.R

class CastReceiverService : Service() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        val deviceName = intent?.getStringExtra(EXTRA_DEVICE_NAME) ?: "Living Room TV"
        AndroidRemoteApp.container(this).ensureReceiverStarted(deviceName)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        // Service lifecycle managed separately; avoid stopping on activity destroy
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Cast Receiver",
            NotificationManager.IMPORTANCE_LOW
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.notification_ready))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()

    companion object {
        const val EXTRA_DEVICE_NAME = "device_name"
        private const val CHANNEL_ID = "cast_receiver"
        private const val NOTIFICATION_ID = 1
        const val SIGNALING_PORT = 8765
    }
}
