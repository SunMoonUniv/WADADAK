package com.wadadak.wadadak

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.SystemClock
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Real device sensors only. Counter baselines are reset for each resumed interval. */
class RunDevices(private val context: Context, messenger: BinaryMessenger) : SensorEventListener {
    private val channel = MethodChannel(messenger, "com.wadadak.app/run_device")
    private val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
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
    private var tts: TextToSpeech? = null
    private var voiceReady = false
    private var initializing = false
    private val voiceWaiters = mutableListOf<MethodChannel.Result>()
    private var focus: AudioFocusRequest? = null
    private var utterance = 0L
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startSteps" -> result.success(startSteps())
                    "sampleSteps" -> result.success(sample(call.argument<Boolean>("force") == true))
                    "stopSteps" -> { stopSteps(); result.success(null) }
                    "initializeVoice" -> initializeVoice(result)
                    "speak" -> result.success(speak(call.argument<String>("text") ?: ""))
                    "stopVoice" -> { stopVoice(); result.success(null) }
                    "close" -> { closeResources(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) { result.error("PERMISSION_REVOKED", "신체 활동 권한이 해제되었어요", null) }
        }
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
    private fun initializeVoice(result: MethodChannel.Result) {
        if (tts != null && !initializing) { result.success(voiceReady); return }
        voiceWaiters.add(result)
        if (initializing) return
        initializing = true
        tts = TextToSpeech(context) { status ->
            voiceReady = status == TextToSpeech.SUCCESS && (tts?.setLanguage(Locale.KOREAN) ?: -1) >= 0
            tts?.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {}
                override fun onDone(id: String?) { releaseFocus(id) }
                @Deprecated("Deprecated in Java") override fun onError(id: String?) {
                    releaseFocus(id)
                    Handler(Looper.getMainLooper()).post {
                        if (id == utterance.toString()) channel.invokeMethod("voiceError", null)
                    }
                }
            })
            initializing = false
            val waiters = voiceWaiters.toList(); voiceWaiters.clear()
            waiters.forEach { it.success(voiceReady) }
        }
    }
    private fun speak(text: String): Boolean {
        if (!voiceReady || text.isBlank()) return false
        stopVoice()
        val id = (++utterance).toString()
        val granted = if (Build.VERSION.SDK_INT >= 26) {
            focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setOnAudioFocusChangeListener { change -> if (change < 0) stopVoice() }.build()
            audio.requestAudioFocus(focus!!)
        } else {
            @Suppress("DEPRECATION") audio.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
        if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { releaseFocus(id); return false }
        val success = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, id) == TextToSpeech.SUCCESS
        if (!success) releaseFocus(id)
        return success
    }
    @Synchronized private fun releaseFocus(id: String?) {
        if (id != utterance.toString()) return
        if (Build.VERSION.SDK_INT >= 26) focus?.let { audio.abandonAudioFocusRequest(it) }
        else { @Suppress("DEPRECATION") audio.abandonAudioFocus(null) }
        focus = null
    }
    private fun stopVoice() { tts?.stop(); releaseFocus(utterance.toString()); utterance++ }
    private fun closeResources() {
        stopSteps(); stopVoice(); tts?.shutdown(); tts = null; voiceReady = false; initializing = false
        val waiters = voiceWaiters.toList(); voiceWaiters.clear(); waiters.forEach { it.success(false) }
    }
    fun close() { closeResources(); channel.setMethodCallHandler(null) }
}
