package com.matrimonyagents.gandharva

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createUpdatesChannel()
    }

    /**
     * The one push channel (SPEC §9.16): id `updates`, "Updates", high
     * importance. Creating an existing channel is a no-op, so this is safe on
     * every start-up. FCM messages name it via android.notification.channel_id,
     * and the manifest makes it the default.
     */
    private fun createUpdatesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "updates",
            "Updates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Your agent's decisions, replies to your interests and payment reminders"
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }
}
