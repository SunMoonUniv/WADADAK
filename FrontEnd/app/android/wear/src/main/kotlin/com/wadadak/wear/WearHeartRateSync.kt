package com.wadadak.wear

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.WearableListenerService
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject

internal data class WearHeartRateSample(val measuredAtMs: Long, val bpm: Int)

internal object WearHeartRateSync {
    private const val DB_NAME = "wear_heart_rate_outbox.db"
    private const val BATCH_SIZE = 32
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val sending = Mutex()
    private var database: Outbox? = null

    @Synchronized
    private fun outbox(context: Context): Outbox =
        database ?: Outbox(context.applicationContext).also { database = it }

    fun record(context: Context, sessionId: String, samples: List<WearHeartRateSample>) {
        if (samples.isEmpty()) return
        val app = context.applicationContext
        scope.launch {
            try {
                outbox(app).insert(sessionId, samples)
                // WorkManager keeps trying after the measurement service has stopped.
                schedule(app)
                if (!flush(app)) schedule(app)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.w("WearHeartRateSync", "Could not queue heart rate: ${error.javaClass.simpleName}")
            }
        }
    }

    fun kick(context: Context) {
        val app = context.applicationContext
        if (!outboxFile(app).isFile) return
        scope.launch {
            try {
                if (!flush(app)) schedule(app)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Log.w("WearHeartRateSync", "Could not resume heart rate sync: ${error.javaClass.simpleName}")
            }
        }
    }

    private fun schedule(context: Context) {
        val request = OneTimeWorkRequestBuilder<WearHeartRateSyncWorker>()
            .setInitialDelay(10, TimeUnit.SECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(DB_NAME, ExistingWorkPolicy.KEEP, request)
    }

    suspend fun flush(context: Context): Boolean = withContext(Dispatchers.IO) {
        if (!sending.tryLock()) return@withContext false
        try {
            val outbox = outbox(context)
            val unavailable = mutableSetOf<String>()
            while (true) {
                val session = outbox.sessions().firstOrNull { it !in unavailable } ?: break
                val samples = outbox.newest(session)
                if (samples.isEmpty()) continue
                if (send(context, session, samples)) {
                    outbox.acknowledge(session, samples)
                } else {
                    // A different account's pending run must not delay the current run.
                    unavailable.add(session)
                }
            }
            unavailable.isEmpty()
        } finally {
            sending.unlock()
        }
    }

    private suspend fun send(
        context: Context, sessionId: String, samples: List<WearHeartRateSample>,
    ): Boolean {
        val points = JSONArray()
        for (sample in samples) {
            points.put(JSONArray().put(sample.measuredAtMs).put(sample.bpm))
        }
        val request = JSONObject().put("command", "heartRate")
            .put("sessionId", sessionId).put("samples", points)
        return withTimeoutOrNull(4500L) {
            suspendCancellableCoroutine { reply ->
                requestPhoneRun(context, request) { reply.isActive }.addOnCompleteListener { task ->
                    if (!reply.isActive) return@addOnCompleteListener
                    val accepted = task.isSuccessful && runCatching {
                        JSONObject(task.result.decodeToString()).optBoolean("heartRateAck")
                    }.getOrDefault(false)
                    reply.resume(accepted)
                }
            }
        } ?: false
    }

    private fun outboxFile(context: Context) = File(context.noBackupFilesDir, DB_NAME)

    private class Outbox(context: Context) : SQLiteOpenHelper(context, outboxFile(context).absolutePath, null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                """CREATE TABLE samples (
                    session_id TEXT NOT NULL, measured_at_ms INTEGER NOT NULL, bpm INTEGER NOT NULL,
                    PRIMARY KEY (session_id, measured_at_ms)
                )""",
            )
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

        fun insert(session: String, samples: List<WearHeartRateSample>) {
            val db = writableDatabase
            db.beginTransaction()
            try {
                for (sample in samples) {
                    val values = ContentValues().apply {
                        put("session_id", session)
                        put("measured_at_ms", sample.measuredAtMs)
                        put("bpm", sample.bpm)
                    }
                    db.insertWithOnConflict("samples", null, values, SQLiteDatabase.CONFLICT_IGNORE)
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        }

        fun sessions(): List<String> =
            readableDatabase.rawQuery(
                "SELECT session_id FROM samples GROUP BY session_id ORDER BY MAX(measured_at_ms) DESC",
                null,
            ).use { rows ->
                buildList { while (rows.moveToNext()) add(rows.getString(0)) }
            }

        fun newest(session: String): List<WearHeartRateSample> =
            readableDatabase.query(
                "samples", arrayOf("measured_at_ms", "bpm"), "session_id=?", arrayOf(session),
                null, null, "measured_at_ms DESC", BATCH_SIZE.toString(),
            ).use { rows ->
                buildList {
                    while (rows.moveToNext()) add(WearHeartRateSample(rows.getLong(0), rows.getInt(1)))
                }
            }

        fun acknowledge(session: String, samples: List<WearHeartRateSample>) {
            val placeholders = List(samples.size) { "?" }.joinToString(",")
            writableDatabase.delete(
                "samples", "session_id=? AND measured_at_ms IN ($placeholders)",
                arrayOf(session, *samples.map { it.measuredAtMs.toString() }.toTypedArray()),
            )
        }
    }
}

class WearHeartRateReconnectService : WearableListenerService() {
    override fun onCapabilityChanged(info: CapabilityInfo) {
        if (info.name == PHONE_RUN_CAPABILITY && info.nodes.isNotEmpty()) WearHeartRateSync.kick(this)
    }
}

class WearHeartRateSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        if (WearHeartRateSync.flush(applicationContext)) Result.success() else Result.retry()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        Result.retry()
    }
}
