package com.wadadak.wadadak

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.SystemClock
import android.provider.Settings

class MainActivity : FlutterActivity() {
    private var runDevices: RunDevices? = null
    private var audioOutput: RunAudioOutput? = null
    private var screenAwake: RunScreenAwake? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        runDevices?.close()
        audioOutput?.close()
        screenAwake?.close()
        screenAwake = RunScreenAwake(this, flutterEngine.dartExecutor.binaryMessenger)
        audioOutput = RunAudioOutput(this, flutterEngine.dartExecutor.binaryMessenger)
        runDevices = RunDevices(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.wadadak.app/run_clock")
            .setMethodCallHandler { call, result ->
                if (call.method == "snapshot") {
                    // Missing/unreadable BOOT_COUNT deliberately disables cross-process resume.
                    val count = try { Settings.Global.getInt(contentResolver, "boot_count", -1) }
                        catch (_: Exception) { -1 }
                    result.success(mapOf("elapsedMs" to SystemClock.elapsedRealtime(),
                        "bootId" to if (count >= 0) "android.boot:$count" else null))
                }
                else if (call.method == "elapsedRealtime") result.success(SystemClock.elapsedRealtime())
                else result.notImplemented()
            }
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        screenAwake?.close(); screenAwake = null
        audioOutput?.close(); audioOutput = null
        runDevices?.close(); runDevices = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
    override fun onResume() { super.onResume(); screenAwake?.resume() }
    override fun onPause() { screenAwake?.pause(); super.onPause() }
}
