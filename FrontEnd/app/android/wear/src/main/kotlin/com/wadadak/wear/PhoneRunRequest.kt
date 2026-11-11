package com.wadadak.wear

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

internal const val PHONE_RUN_CAPABILITY = "wadadak_phone_free_run_v1"

internal fun requestPhoneRun(
    context: Context,
    payload: JSONObject,
    isCurrent: () -> Boolean = { true },
): Task<ByteArray> =
    Wearable.getCapabilityClient(context)
        .getCapability(PHONE_RUN_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
        .onSuccessTask { capability ->
            if (!isCurrent()) return@onSuccessTask Tasks.forCanceled<ByteArray>()
            val phone = capability.nodes.firstOrNull { it.isNearby }
                ?: capability.nodes.firstOrNull()
                ?: return@onSuccessTask Tasks.forException<ByteArray>(
                    IllegalStateException("Phone unavailable"),
                )
            Wearable.getMessageClient(context)
                .sendRequest(phone.id, "/wadadak/free-run/v1", payload.toString().encodeToByteArray())
        }
