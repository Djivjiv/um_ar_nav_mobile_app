package com.example.um_ar_mobile_app

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UnityBridge.attach(this, flutterEngine)
        // Time since boot, for ClockSource.uptimeMs: unlike the phone's clock,
        // it can't be changed, and it counts through sleep and app restarts.
        // The screen capture setting (kBlockScreenCapture) arrives here too.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.um.arnav/clock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())
                    "setBlockScreenCapture" -> {
                        ScreenCaptureBlock.set(this, call.arguments == true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

/**
 * FLAG_SECURE, as set by kBlockScreenCapture in app_config.dart. It blanks the
 * window in screenshots, recordings, mirroring and the recent-apps preview.
 *
 * It is a per-window flag, so it is also put on each activity opened later:
 * the Unity AR player has a window of its own.
 */
private object ScreenCaptureBlock : Application.ActivityLifecycleCallbacks {
    private var block = false
    private var listening = false

    fun set(activity: Activity, value: Boolean) {
        block = value
        if (!listening) {
            activity.application.registerActivityLifecycleCallbacks(this)
            listening = true
        }
        val flag = WindowManager.LayoutParams.FLAG_SECURE
        if (block) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
        if (block) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
