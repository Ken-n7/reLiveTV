package com.ken.tv_channels

import android.Manifest
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.PowerManager
import android.util.Rational
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pipAllowed = false // set by Dart: background play on and a video is playing

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Small app-specific platform calls; avoids pulling in plugins for one-liners.
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "relivetv/platform")
        channel = ch
        PlaybackService.onAction = { action -> runOnUiThread { ch.invokeMethod("notificationAction", action) } }
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "cacheDir" -> result.success(cacheDir.absolutePath) // app-private, re-creatable data
                "startPlaybackService" -> {
                    PlaybackService.start(this, call.argument<String>("title") ?: "reLiveTV", call.argument<Boolean>("playing") ?: true)
                    result.success(null)
                }
                "stopPlaybackService" -> {
                    PlaybackService.stop(this)
                    result.success(null)
                }
                "setPipAllowed" -> {
                    pipAllowed = call.arguments as Boolean
                    result.success(null)
                }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Leaving the app (home button, app switch) while a video plays → float it.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed && Build.VERSION.SDK_INT >= 26 && packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build())
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
        // The floating window was dismissed (not expanded back): stop like YouTube does.
        // Turning the screen off also ends picture-in-picture; that is not a dismissal.
        val screenOn = (getSystemService(POWER_SERVICE) as PowerManager).isInteractive
        if (!isInPictureInPictureMode && lifecycle.currentState == Lifecycle.State.CREATED && screenOn) {
            channel?.invokeMethod("pipClosed", null)
        }
    }

    override fun onDestroy() {
        PlaybackService.onAction = null
        PlaybackService.stop(this)
        super.onDestroy()
    }
}
