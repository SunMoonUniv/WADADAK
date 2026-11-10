package com.wadadak.wear

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.TextView
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Wearable

class WearPingActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_wear_ping)

        val button = findViewById<Button>(R.id.send_ping)
        val status = findViewById<TextView>(R.id.ping_status)
        button.setOnClickListener { sendPing(button, status) }
    }

    private fun sendPing(button: Button, status: TextView) {
        button.isEnabled = false
        status.setText(R.string.sending_ping)

        val context = applicationContext
        Wearable.getCapabilityClient(context)
            .getCapability(PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
            .onSuccessTask { capability ->
                val phone = capability.nodes.firstOrNull { it.isNearby }
                    ?: capability.nodes.firstOrNull()
                    ?: return@onSuccessTask Tasks.forException<ByteArray>(PhoneUnavailable())
                Log.i(TAG, "Watch sent PING")
                Wearable.getMessageClient(context).sendRequest(phone.id, PING_PATH, "PING".encodeToByteArray())
            }
            .addOnCompleteListener { result ->
                if (isDestroyed) return@addOnCompleteListener
                button.isEnabled = true
                val message = when {
                    result.isSuccessful && result.result.contentEquals("PONG".encodeToByteArray()) -> {
                        Log.i(TAG, "Watch received PONG")
                        R.string.pong_received
                    }
                    result.isSuccessful -> R.string.unexpected_response
                    result.exception is PhoneUnavailable -> R.string.phone_unavailable
                    else -> {
                        Log.w(TAG, "Watch ping failed", result.exception)
                        R.string.ping_failed
                    }
                }
                status.setText(message)
            }
    }

    private class PhoneUnavailable : Exception()

    private companion object {
        const val PHONE_CAPABILITY = "wadadak_phone_ping_v1"
        const val PING_PATH = "/wadadak/diagnostics/ping/v1"
        const val TAG = "WadadakWearPing"
    }
}
