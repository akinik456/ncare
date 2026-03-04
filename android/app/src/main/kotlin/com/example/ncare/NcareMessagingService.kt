package com.example.ncare

import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class NcareMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {

    Log.d("NCARE_FCM", "onMessageReceived data=${message.data}")

    val type = message.data["type"]
    Log.d("NCARE_FCM", "type=$type (starting FG if rl)")

    if (type == "rl") {
        Log.d("NCARE_FCM", "STARTING FG NOW")

        val intent = Intent(this, NcareForegroundService::class.java)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    } else {
        Log.d("NCARE_FCM", "NOT STARTING FG (type != rl)")
    }
}

    override fun onNewToken(token: String) {
        Log.d("NCARE_FCM", "onNewToken=$token")
    }
}