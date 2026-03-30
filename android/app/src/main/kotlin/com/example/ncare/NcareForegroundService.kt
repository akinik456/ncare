package com.example.ncare

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

class NcareForegroundService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var started = false

    private val engineRunnable = object : Runnable {
        override fun run() {
            Log.d("NCARE_ENGINE", "ENGINE TICK")
            handler.postDelayed(this, 30_000L)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("NCARE_ENGINE", "SERVICE START")

        startAsForeground()

        if (!started) {
            started = true
            handler.removeCallbacks(engineRunnable)
            handler.post(engineRunnable)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        Log.d("NCARE_ENGINE", "SERVICE DESTROY")
        handler.removeCallbacks(engineRunnable)
        started = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startAsForeground() {
        val channelId = "ncare_fg_channel"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "NCare Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("NCare")
            .setContentText("Location service running")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()

        startForeground(1, notification)
    }
}
