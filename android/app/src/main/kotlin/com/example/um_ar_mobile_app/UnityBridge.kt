package com.example.um_ar_mobile_app

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Bridges Flutter to a Unity AR player exported as an Android Library
 * (.aar) and launched as its own Activity — no flutter_unity_widget
 * (that package's bundled build.gradle calls the defunct jcenter()
 * repository and cannot build under this project's Android Gradle Plugin;
 * see the `unity-ar-blocked` note on the Flutter side).
 *
 * The Unity .aar is NOT part of this repo yet. Every method below is
 * written to keep working unmodified once it is added: the Unity player
 * class is only ever referenced by fully-qualified string name via
 * reflection (never imported directly), so this file compiles today and
 * will start actually launching Unity the moment
 * com.unity3d.player.UnityPlayerActivity is on the classpath (dropped in
 * under android/unityLibrary and wired into android/app/build.gradle) —
 * nothing here needs to change for that to happen.
 */
object UnityBridge : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private const val METHOD_CHANNEL = "com.um.arnav/unity"
    private const val EVENT_CHANNEL = "com.um.arnav/unity_events"
    private const val UNITY_ACTIVITY_CLASS = "com.unity3d.player.UnityPlayerActivity"

    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    /** Call from MainActivity.configureFlutterEngine(). */
    fun attach(activity: Activity, engine: FlutterEngine) {
        this.activity = activity
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isUnityAvailable" -> result.success(isUnityPlayerPresent())
            "startOutdoorNavigation" -> launchUnity("start_outdoor", call.arguments, result)
            "startIndoorNavigation" -> launchUnity("start_indoor", call.arguments, result)
            "stopNavigation" -> stopUnity(result)
            else -> result.notImplemented()
        }
    }

    private fun isUnityPlayerPresent(): Boolean {
        return try {
            Class.forName(UNITY_ACTIVITY_CLASS)
            true
        } catch (e: ClassNotFoundException) {
            false
        }
    }

    private fun launchUnity(kind: String, arguments: Any?, result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "MainActivity not attached", null)
            return
        }
        try {
            val unityClass = Class.forName(UNITY_ACTIVITY_CLASS)
            val json = JSONObject((arguments as? Map<*, *>) ?: emptyMap<Any, Any>())
            val intent = Intent(act, unityClass)
            intent.putExtra("kind", kind)
            intent.putExtra("routeData", json.toString())
            act.startActivity(intent)
            result.success(true)
        } catch (e: ClassNotFoundException) {
            emitEvent(
                mapOf(
                    "event" to "error",
                    "message" to ("Unity library not found. Export Unity as an " +
                        "Android Library (.aar), add it under android/unityLibrary, " +
                        "wire it into android/app/build.gradle, and rebuild."),
                ),
            )
            result.success(false)
        } catch (e: Exception) {
            emitEvent(mapOf("event" to "error", "message" to (e.message ?: "Unity launch failed")))
            result.success(false)
        }
    }

    private fun stopUnity(result: MethodChannel.Result) {
        // TODO(unity): once UnityPlayerActivity is real, signal it to finish
        // (e.g. a static WeakReference set from its onCreate, or a local
        // broadcast) instead of this no-op.
        result.success(true)
    }

    /**
     * Forwards an event to Flutter. Called from here on failure paths today;
     * once the real Unity player exists, its native callback (Unity's
     * `UnitySendMessage` arrives back into a plain Java/Kotlin method you
     * expose to it) should call this too, e.g. for "arrived" / "qr_scanned".
     */
    fun emitEvent(payload: Map<String, Any?>) {
        eventSink?.success(payload)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
