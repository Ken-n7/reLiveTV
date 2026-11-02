package com.ken.tv_channels

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Small app-specific platform calls; avoids pulling in plugins for one-liners.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "relivetv/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "cacheDir" -> result.success(cacheDir.absolutePath) // app-private, re-creatable data
                else -> result.notImplemented()
            }
        }
    }
}
