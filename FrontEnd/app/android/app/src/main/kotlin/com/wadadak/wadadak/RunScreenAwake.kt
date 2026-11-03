package com.wadadak.wadadak

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Foreground-only screen flag. Never turns a locked display back on. */
class RunScreenAwake(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.wadadak.app/run_screen")
    private var requested = false
    private var resumed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "setKeepScreenOn") {
                requested = call.argument<Boolean>("enabled") == true
                apply()
                result.success(null)
            } else result.notImplemented()
        }
    }
    fun resume() { resumed = true; apply() }
    fun pause() { resumed = false; apply() }
    private fun apply() {
        if (requested && resumed) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    fun close() { requested = false; pause(); channel.setMethodCallHandler(null) }
}
