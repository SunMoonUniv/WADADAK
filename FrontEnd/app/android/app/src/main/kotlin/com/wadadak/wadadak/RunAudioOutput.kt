package com.wadadak.wadadak

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Platform speech output only. Dart AudioGuide owns run audio policy. */
class RunAudioOutput(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.wadadak.app/audio_guide")
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
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
                    "initializeVoice" -> initializeVoice(result)
                    "speak" -> result.success(speak(call.argument<String>("text") ?: ""))
                    "stopVoice" -> { stopVoice(); result.success(null) }
                    "close" -> { closeResources(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: RuntimeException) {
                result.error("AUDIO_FAILURE", "음성 출력을 사용할 수 없어요", null)
            }
        }
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
        stopVoice(); tts?.shutdown(); tts = null; voiceReady = false; initializing = false
        val waiters = voiceWaiters.toList(); voiceWaiters.clear(); waiters.forEach { it.success(false) }
    }
    fun close() { closeResources(); channel.setMethodCallHandler(null) }
}
