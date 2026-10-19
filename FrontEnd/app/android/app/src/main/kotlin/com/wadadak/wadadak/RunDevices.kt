package com.wadadak.wadadak

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Real device sensors only. Counter baselines are reset for each resumed interval. */
class RunDevices(private val context: Context, messenger: BinaryMessenger) : SensorEventListener {
    private val channel = MethodChannel(messenger, "com.wadadak.app/run_device")
    private val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var pressureSensor: Sensor? = null
    private var pressureStarted = 0L
    private var pressureAt = -1L
    private var pressureDeliveredAt = -1L
    private var pressureHpa = 0.0
    private var pressureAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
    private val pressureListener = object : SensorEventListener {
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
            pressureAccuracy = accuracy
        }
        override fun onSensorChanged(event: SensorEvent) {
            if (pressureSensor == null) return
            val at = event.timestamp / 1_000_000L
            val value = event.values[0].toDouble()
            if (at < pressureStarted || at <= pressureAt || !value.isFinite() || value <= 0) return
            pressureAt = at
            pressureHpa = value
            pressureAccuracy = event.accuracy
        }
    }
    private var sensor: Sensor? = null
    private var started = 0L
    private var boundary = 0L
    private var lastCounter: Long? = null
    private var lastCounterAt = 0L
    private var pendingSteps = 0
    private var pendingDuration = 0L
    private var pendingEnd = 0L
    private var detectorSteps = 0
    private var seenStep = false
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startPressure" -> result.success(startPressure())
                    "samplePressure" -> result.success(samplePressure())
                    "stopPressure" -> { stopPressure(); result.success(null) }
                    "startSteps" -> result.success(startSteps())
                    "sampleSteps" -> result.success(sample(call.argument<Boolean>("force") == true))
                    "stopSteps" -> { stopSteps(); result.success(null) }
                    "close" -> { stopSteps(); stopPressure(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) { result.error("PERMISSION_REVOKED", "신체 활동 권한이 해제되었어요", null) }
        }
    }
    private fun startPressure(): Boolean {
        stopPressure()
        pressureSensor = sensors.getDefaultSensor(Sensor.TYPE_PRESSURE) ?: return false
        pressureStarted = SystemClock.elapsedRealtime()
        if (!sensors.registerListener(pressureListener, pressureSensor, 1_000_000, 0)) {
            stopPressure()
            return false
        }
        return true
    }
    private fun samplePressure(): Map<String, Any>? {
        if (pressureSensor == null || pressureAt <= pressureDeliveredAt) return null
        val age = SystemClock.elapsedRealtime() - pressureAt
        if (age !in 0..2000) return null
        pressureDeliveredAt = pressureAt
        return mapOf("pressureHpa" to pressureHpa, "pressureAccuracy" to pressureAccuracy,
            "sampleClockMs" to pressureAt)
    }
    private fun stopPressure() {
        sensors.unregisterListener(pressureListener)
        pressureSensor = null
        pressureAt = -1L
        pressureDeliveredAt = -1L
        pressureAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
    }
    private fun startSteps(): String {
        stopSteps()
        if (Build.VERSION.SDK_INT >= 29 && context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED)
            throw SecurityException()
        sensor = sensors.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) ?: sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sensor == null) return "센서 미지원"
        started = SystemClock.elapsedRealtime(); boundary = started
        if (!sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL, 0)) {
            sensor = null; return "센서 연결 실패"
        }
        return "걸음 감지 대기"
    }
    private fun stopSteps() {
        sensors.unregisterListener(this); sensor = null
        lastCounter = null; pendingSteps = 0; pendingDuration = 0; detectorSteps = 0; seenStep = false
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onSensorChanged(event: SensorEvent) {
        if (sensor == null) return
        val at = event.timestamp / 1_000_000L
        if (at < started) return
        if (event.sensor.type == Sensor.TYPE_STEP_DETECTOR) {
            if (at >= boundary && event.values[0] > 0) { detectorSteps++; seenStep = true }
            return
        }
        val total = event.values[0].toLong()
        val previous = lastCounter
        if (previous != null) {
            val duration = at - lastCounterAt
            val delta = total - previous
            if (duration in 1..10000 && delta >= 0 && delta * 1000 <= duration * 5 && pendingDuration + duration <= 10000) {
                pendingSteps += delta.toInt(); pendingDuration += duration; pendingEnd = at
            } else { pendingSteps = 0; pendingDuration = 0 }
        }
        lastCounter = total; lastCounterAt = at
    }
    private fun sample(force: Boolean): Map<String, Any>? {
        val selected = sensor ?: return null
        if (Build.VERSION.SDK_INT >= 29 && context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED)
            throw SecurityException()
        if (selected.type == Sensor.TYPE_STEP_COUNTER) {
            if (pendingDuration < if (force) 200 else 5000) return null
            val result = mapOf("steps" to pendingSteps, "durationMs" to pendingDuration, "sampleEndClockMs" to pendingEnd)
            pendingSteps = 0; pendingDuration = 0; return result
        }
        val now = SystemClock.elapsedRealtime()
        val duration = now - boundary
        if (duration < if (force) 200 else 5000) return null
        val count = detectorSteps; detectorSteps = 0; boundary = now
        if (!seenStep || duration > 10000 || count * 1000 > duration * 5) return null
        return mapOf("steps" to count, "durationMs" to duration, "sampleEndClockMs" to now)
    }
    fun close() { stopSteps(); stopPressure(); channel.setMethodCallHandler(null) }
}
