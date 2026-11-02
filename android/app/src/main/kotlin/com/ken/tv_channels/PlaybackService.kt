package com.ken.tv_channels

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app alive while it plays in the background (Android stops or freezes
 * background apps otherwise). Shows one low-priority notification with
 * Pause/Play and Stop. Runs only while background play is on and something plays.
 */
class PlaybackService : Service() {
    companion object {
        const val ACTION_START = "start"
        const val ACTION_TOGGLE = "toggle"
        const val ACTION_STOP = "stop"
        private const val CHANNEL_ID = "playback"
        private const val NOTIFICATION_ID = 1

        /** Set by MainActivity: forwards notification buttons to Dart. */
        var onAction: ((String) -> Unit)? = null

        fun start(context: Context, title: String, playing: Boolean) {
            val intent = Intent(context, PlaybackService::class.java)
                .setAction(ACTION_START)
                .putExtra("title", title)
                .putExtra("playing", playing)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PlaybackService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE, ACTION_STOP -> {
                onAction?.invoke(intent.action!!)
                if (intent.action == ACTION_STOP) stopSelf()
                return START_NOT_STICKY
            }
        }
        val title = intent?.getStringExtra("title") ?: "reLiveTV"
        val playing = intent?.getBooleanExtra("playing", true) ?: true
        val notification = build(title, playing)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY // if Android kills the app, don't restart playback on its own
    }

    private fun build(title: String, playing: Boolean): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Background playback", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        fun action(name: String, code: Int) =
            PendingIntent.getService(this, code, Intent(this, PlaybackService::class.java).setAction(name), flags)
        val open = PendingIntent.getActivity(this, 0, packageManager.getLaunchIntentForPackage(packageName), flags)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else @Suppress("DEPRECATION") Notification.Builder(this)
        return builder
            .setSmallIcon(if (playing) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause)
            .setContentTitle(title)
            .setContentText("Playing in background · reLiveTV")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, if (playing) "Pause" else "Play", action(ACTION_TOGGLE, 1)).build())
            .addAction(Notification.Action.Builder(null, "Stop", action(ACTION_STOP, 2)).build())
            .build()
    }
}
