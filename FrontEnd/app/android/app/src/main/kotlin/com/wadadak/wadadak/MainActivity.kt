package com.wadadak.wadadak

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.SystemClock

class MainActivity : FlutterActivity() {
    private var runDevices: RunDevices? = null
    private var audioOutput: RunAudioOutput? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        runDevices?.close()
        audioOutput?.close()
        audioOutput = RunAudioOutput(this, flutterEngine.dartExecutor.binaryMessenger)
        runDevices = RunDevices(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.wadadak.app/run_clock")
            .setMethodCallHandler { call, result ->
                if (call.method == "elapsedRealtime") result.success(SystemClock.elapsedRealtime())
                else result.notImplemented()
            }
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audioOutput?.close(); audioOutput = null
        runDevices?.close(); runDevices = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
