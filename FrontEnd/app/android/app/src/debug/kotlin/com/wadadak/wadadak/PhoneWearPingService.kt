package com.wadadak.wadadak

import android.util.Log
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.WearableListenerService

class PhoneWearPingService : WearableListenerService() {
    override fun onRequest(nodeId: String, path: String, request: ByteArray): Task<ByteArray>? {
        if (path != PING_PATH) return null
        if (!request.contentEquals("PING".encodeToByteArray())) {
            return Tasks.forException(IllegalArgumentException("Expected PING"))
        }

        Log.i(TAG, "Phone received PING; replying PONG")
        return Tasks.forResult("PONG".encodeToByteArray())
    }

    private companion object {
        const val PING_PATH = "/wadadak/diagnostics/ping/v1"
        const val TAG = "WadadakWearPing"
    }
}
