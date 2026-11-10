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
            } else if (call.method == "moveToBack") {
                // 러닝 중 뒤로가기: 앱을 닫지 않고 홈 화면으로만 보낸다(측정은 계속)
                activity.moveTaskToBack(true)
                result.success(null)
            } else if (call.method == "finish") {
                // 홈 탭에서 뒤로가기 두 번: 시스템 뒤로가기로 앱을 닫을 때와 같다.
                // Flutter가 뒤로가기를 가로채는 동안 SystemNavigator.pop은 뒤로가기를 다시 Flutter로 보내 앱이 닫히지 않는다
                activity.finish()
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
