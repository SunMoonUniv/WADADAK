package com.wadadak.wear

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.clearUpdateCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DataTypeAvailability
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseState
import androidx.health.services.client.data.ExerciseTrackedStatus
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import androidx.health.services.client.endExercise
import androidx.health.services.client.getCapabilities
import androidx.health.services.client.getCurrentExerciseInfo
import androidx.health.services.client.pauseExercise
import androidx.health.services.client.resumeExercise
import androidx.health.services.client.startExercise
import kotlin.coroutines.resume
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

class WearHeartRateService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var worker: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        starting = false
        val target = run
        if (intent?.action == STOP) {
            if (target != null && target.id == intent.getStringExtra(EXTRA_SESSION)) {
                publish(Reading(target.id, "심박수 측정 중지", retry = true))
            }
            if (worker == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (worker != null) return START_NOT_STICKY
        val sessionId = intent?.getStringExtra(EXTRA_SESSION)
        if (sessionId == null || !hasPermission(this)) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, notification(sessionId), ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
            } else {
                startForeground(NOTIFICATION_ID, notification(sessionId))
            }
        } catch (_: IllegalStateException) {
            fail(sessionId)
            stopSelf(startId)
            return START_NOT_STICKY
        } catch (_: SecurityException) {
            fail(sessionId)
            stopSelf(startId)
            return START_NOT_STICKY
        }

        if (target?.id != sessionId || target.phase != "running") {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        running = true
        worker = scope.launch {
            collectHeartRate(target)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun collectHeartRate(target: PhoneRun) {
        val client = HealthServices.getClient(this).exerciseClient
        val registered = CompletableDeferred<Boolean>()
        val ended = CompletableDeferred<Unit>()
        var ownsExercise = false
        var sensorState: ExerciseState? = null
        var sensorAvailable = true
        var lastTimestamp = SystemClock.elapsedRealtime() - 1
        var pausedAt: Long? = null
        val callback = object : ExerciseUpdateCallback {
            override fun onRegistered() {
                registered.complete(true)
            }

            override fun onRegistrationFailed(throwable: Throwable) {
                registered.complete(false)
            }

            override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) = Unit

            override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {
                if (dataType != DataType.HEART_RATE_BPM || !isCollecting(target.id)) return
                sensorAvailable = availability != DataTypeAvailability.UNAVAILABLE &&
                    availability != DataTypeAvailability.UNAVAILABLE_DEVICE_OFF_BODY
                if (!sensorAvailable) publish(Reading(target.id, "심박 신호 없음"))
            }

            override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
                val state = update.exerciseStateInfo.state
                sensorState = state
                val phoneRunning = run?.phase == "running" && isCollecting(target.id)
                if (ownsExercise || (state == ExerciseState.ACTIVE && phoneRunning)) {
                    // Health Services can deliver earlier samples when a pause or end flushes its batch.
                    val now = SystemClock.elapsedRealtime()
                    val cutoff = pausedAt ?: if (phoneRunning) Long.MAX_VALUE else now
                    val samples = update.latestMetrics.getData(DataType.HEART_RATE_BPM)
                        .filter { it.timeDurationFromBoot.toMillis() in (lastTimestamp + 1)..cutoff }
                    val latest = samples.maxByOrNull { it.timeDurationFromBoot }
                    if (latest != null) {
                        lastTimestamp = latest.timeDurationFromBoot.toMillis()
                        val bootEpochMs = System.currentTimeMillis() - now
                        val measured = samples.mapNotNull { sample ->
                            val value = sample.value
                            if (value.isFinite() && value in 1.0..300.0) {
                                WearHeartRateSample(
                                    bootEpochMs + sample.timeDurationFromBoot.toMillis(), value.roundToInt(),
                                )
                            } else null
                        }
                        WearHeartRateSync.record(applicationContext, target.id, measured)
                        if (state == ExerciseState.ACTIVE && phoneRunning && sensorAvailable) {
                            val bpm = latest.value
                            if (bpm.isFinite() && bpm in 1.0..300.0) {
                                publish(Reading(target.id, bpm = bpm.roundToInt(), measuredAt = lastTimestamp))
                            } else {
                                publish(Reading(target.id, "심박 신호 없음"))
                            }
                        }
                    }
                }
                if (state.isEnded) {
                    if (ownsExercise && isCollecting(target.id)) fail(target.id)
                    ownsExercise = false
                    ended.complete(Unit)
                }
            }
        }

        var callbackSet = false
        try {
            val capabilities = client.getCapabilities()
            if (ExerciseType.RUNNING !in capabilities.supportedExerciseTypes ||
                DataType.HEART_RATE_BPM !in capabilities
                    .getExerciseTypeCapabilities(ExerciseType.RUNNING).supportedDataTypes
            ) {
                fail(target.id, "심박수 미지원")
                return
            }
            if (!isCollecting(target.id)) return
            client.setUpdateCallback(mainExecutor, callback)
            callbackSet = true
            if (withTimeoutOrNull(5000L) { registered.await() } != true) {
                fail(target.id)
                return
            }
            if (!isCollecting(target.id)) return

            val exercise = client.getCurrentExerciseInfo()
            if (exercise.exerciseTrackedStatus == ExerciseTrackedStatus.OTHER_APP_IN_PROGRESS) {
                fail(target.id, "다른 운동 앱 사용 중")
                return
            }
            if (!isCollecting(target.id)) return
            if (exercise.exerciseTrackedStatus == ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS) {
                ownsExercise = true
            } else {
                sensorState = null
                withContext(NonCancellable) {
                    client.startExercise(
                        ExerciseConfig(
                            exerciseType = ExerciseType.RUNNING,
                            dataTypes = setOf(DataType.HEART_RATE_BPM),
                            isAutoPauseAndResumeEnabled = false,
                            isGpsEnabled = false,
                        ),
                    )
                    ownsExercise = sensorState?.isEnded != true
                    if (!ownsExercise) fail(target.id)
                }
            }

            var nextPhoneCheck = 0L
            var pendingPause: Boolean? = null
            var commandTimeout = 0L
            while (ownsExercise && isCollecting(target.id)) {
                val now = SystemClock.elapsedRealtime()
                val paused = run?.phase != "running"
                if (paused && pausedAt == null) {
                    pausedAt = now
                } else if (!paused && pausedAt != null) {
                    lastTimestamp = maxOf(lastTimestamp, now - 1)
                    pausedAt = null
                }
                val state = sensorState
                if (state == ExerciseState.ACTIVE || state?.isPaused == true) {
                    val sensorPaused = state.isPaused
                    if (pendingPause == sensorPaused || now >= commandTimeout) pendingPause = null
                    if (pendingPause == null && paused != sensorPaused) {
                        publish(Reading(target.id))
                        if (paused) client.pauseExercise() else client.resumeExercise()
                        pendingPause = paused
                        commandTimeout = SystemClock.elapsedRealtime() + 5000L
                    }
                }

                if (observer == null && SystemClock.elapsedRealtime() >= nextPhoneCheck) {
                    checkPhone(target)
                    nextPhoneCheck = SystemClock.elapsedRealtime() + 5000L
                }
                delay(500L)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            fail(target.id)
        } finally {
            withContext(NonCancellable) {
                if (ownsExercise) {
                    pausedAt = pausedAt ?: SystemClock.elapsedRealtime()
                    runCatching {
                        client.endExercise()
                        withTimeoutOrNull(1500L) { ended.await() }
                    }
                }
                if (callbackSet) runCatching { client.clearUpdateCallback(callback) }
            }
            if (reading?.id == target.id && reading?.retry != true) publish(null)
        }
    }

    private suspend fun checkPhone(target: PhoneRun) {
        val before = run
        val request = JSONObject().put("command", "status").put("sessionId", target.id).put("mode", target.mode)
        val snapshot = withTimeoutOrNull(2500L) {
            suspendCancellableCoroutine { reply ->
                requestPhoneRun(applicationContext, request) { reply.isActive && observer == null }
                    .addOnCompleteListener { task ->
                        if (!reply.isActive) return@addOnCompleteListener
                        val response = if (task.isSuccessful) {
                            runCatching { JSONObject(task.result.decodeToString()) }.getOrNull()
                        } else null
                        reply.resume(response)
                    }
            }
        }
        if (snapshot != null && observer == null && run == before) acceptSnapshot(snapshot)
    }

    private fun notification(sessionId: String): Notification {
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, getString(R.string.heart_rate_channel), NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, WearRunActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, WearHeartRateService::class.java).setAction(STOP).putExtra(EXTRA_SESSION, sessionId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.heart_rate_notification))
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, getString(R.string.heart_rate_stop), stop).build())
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
    }

    private data class PhoneRun(val id: String, val mode: String, val phase: String)

    internal data class Reading(
        val id: String,
        val text: String = "심박수 측정 중",
        val bpm: Int? = null,
        val measuredAt: Long = 0,
        val retry: Boolean = false,
    ) {
        fun freshBpm(): Int? = bpm?.takeIf { SystemClock.elapsedRealtime() - measuredAt <= 15_000L }
    }

    companion object {
        private const val CHANNEL = "running_heart_rate"
        private const val NOTIFICATION_ID = 21
        private const val STOP = "com.wadadak.wear.STOP_HEART_RATE"
        private const val EXTRA_SESSION = "run_session"
        private var run: PhoneRun? = null
        private var reading: Reading? = null
        private var observer: (() -> Unit)? = null
        private var starting = false
        private var running = false

        internal val permission: String
            get() = if (Build.VERSION.SDK_INT >= 36) "android.permission.health.READ_HEART_RATE"
                else Manifest.permission.BODY_SENSORS

        internal fun hasPermission(context: Context): Boolean =
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

        internal fun observe(listener: (() -> Unit)?) {
            observer = listener
        }

        internal fun acceptSnapshot(snapshot: JSONObject) {
            if (!snapshot.optBoolean("bridgeReady", true)) return
            val phase = snapshot.optString("phase")
            if (phase == "unavailable" || phase.isBlank()) return
            val id = snapshot.opt("sessionId") as? String
            val next = if (id != null && phase in setOf("running", "paused", "ending")) {
                PhoneRun(id, snapshot.optString("mode", "free"), phase)
            } else null
            val previous = run
            run = next
            if (next?.id != previous?.id) publish(null)
            else if (next?.phase != previous?.phase && reading?.retry != true) publish(null)
        }

        internal fun readingFor(sessionId: String?): Reading? = reading?.takeIf { it.id == sessionId }

        internal fun startIfRunning(context: Context, retry: Boolean = false) {
            val target = run ?: return
            if (target.phase != "running" || !hasPermission(context) || starting || running) return
            if (readingFor(target.id)?.retry == true && !retry) return
            if (retry) publish(null)
            starting = true
            try {
                context.startForegroundService(
                    Intent(context, WearHeartRateService::class.java).putExtra(EXTRA_SESSION, target.id),
                )
            } catch (_: IllegalStateException) {
                starting = false
                fail(target.id)
            } catch (_: SecurityException) {
                starting = false
                fail(target.id)
            }
        }

        private fun isCollecting(id: String): Boolean = run?.id == id && readingFor(id)?.retry != true

        private fun fail(id: String, message: String = "심박수 측정 불가") {
            if (run?.id == id) publish(Reading(id, message, retry = true))
        }

        private fun publish(value: Reading?) {
            if (reading == value) return
            reading = value
            observer?.invoke()
        }
    }
}
