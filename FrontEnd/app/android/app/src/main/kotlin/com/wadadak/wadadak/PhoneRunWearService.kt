package com.wadadak.wadadak

import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.android.gms.wearable.WearableListenerService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException
import org.json.JSONObject

class PhoneRunWearService : WearableListenerService() {
    override fun onRequest(nodeId: String, path: String, request: ByteArray): Task<ByteArray>? {
        if (path != "/wadadak/free-run/v1") return null
        return PhoneRunWearBridge.request(request)
    }
}

internal object PhoneRunWearBridge {
    private val main = Handler(Looper.getMainLooper())
    private var messenger: BinaryMessenger? = null
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        this.messenger = messenger
        channel = MethodChannel(messenger, "com.wadadak.app/wear_run")
    }

    fun detach(messenger: BinaryMessenger) {
        if (this.messenger !== messenger) return
        this.messenger = null
        channel = null
    }

    fun request(bytes: ByteArray): Task<ByteArray> {
        val reply = TaskCompletionSource<ByteArray>()
        fun unavailable() {
            reply.trySetResult(
                JSONObject(mapOf("phase" to "unavailable", "bridgeReady" to false, "message" to "폰에서 와다닥을 열어 주세요."))
                    .toString().encodeToByteArray()
            )
        }
        val request = try {
            require(bytes.size <= 512)
            JSONObject(bytes.decodeToString())
        } catch (_: IllegalArgumentException) {
            reply.setException(IllegalArgumentException("Invalid watch request"))
            return reply.task
        } catch (_: JSONException) {
            reply.setException(IllegalArgumentException("Invalid watch request"))
            return reply.task
        }
        val args = mapOf(
            "command" to request.optString("command"),
            "sessionId" to request.optString("sessionId").takeIf(String::isNotEmpty),
            "readyId" to (request.opt("readyId") as? String),
            "mode" to (request.opt("mode") as? String)
        )
        main.post {
            val target = channel
            if (target == null) {
                unavailable()
                return@post
            }
            target.invokeMethod("request", args, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result !is Map<*, *>) {
                        unavailable()
                        return
                    }
                    reply.trySetResult(JSONObject(result).toString().encodeToByteArray())
                }
                override fun error(code: String, message: String?, details: Any?) = unavailable()
                override fun notImplemented() = unavailable()
            })
        }
        return reply.task
    }
}
