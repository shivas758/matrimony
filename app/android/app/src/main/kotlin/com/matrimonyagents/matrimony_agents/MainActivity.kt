package com.matrimonyagents.matrimony_agents

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

    /** Push notifications land in "Updates" (SPEC §9.16), high importance. */
    private fun createUpdatesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel("updates") != null) return
        manager.createNotificationChannel(
            NotificationChannel("updates", "Updates", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Requests, clients and decisions"
            },
        )
    }
}
