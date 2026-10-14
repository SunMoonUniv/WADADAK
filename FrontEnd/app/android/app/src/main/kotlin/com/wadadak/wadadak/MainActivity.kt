package com.wadadak.wadadak

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.SystemClock

class MainActivity : FlutterActivity() {
    private var runDevices: RunDevices? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        runDevices?.close()
        runDevices = RunDevices(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.wadadak.app/run_clock")
            .setMethodCallHandler { call, result ->
                if (call.method == "elapsedRealtime") result.success(SystemClock.elapsedRealtime())
                else result.notImplemented()
            }
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        runDevices?.close(); runDevices = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
