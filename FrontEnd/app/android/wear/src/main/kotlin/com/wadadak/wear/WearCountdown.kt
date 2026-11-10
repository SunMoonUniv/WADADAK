package com.wadadak.wear

/** Runs the phone-confirmed countdown on the watch's monotonic clock. */
internal class WearCountdown {
    private var deadlineMs: Long? = null

    fun accept(number: Int, stepRemainingMs: Long, nowMs: Long) {
        if (number !in 1..3 || stepRemainingMs !in 0..STEP_MS) {
            clear()
        } else if (deadlineMs == null) {
            deadlineMs = nowMs + (number - 1) * STEP_MS + stepRemainingMs
        }
    }

    fun clear() {
        deadlineMs = null
    }

    fun numberAt(nowMs: Long): Int? {
        val remaining = remainingAt(nowMs) ?: return null
        return ((remaining - 1) / STEP_MS + 1).toInt()
    }

    fun nextTickAfter(nowMs: Long): Long? {
        val remaining = remainingAt(nowMs) ?: return null
        return (remaining - 1) % STEP_MS + 1
    }

    private fun remainingAt(nowMs: Long) = deadlineMs?.minus(nowMs)?.takeIf { it > 0 }

    private companion object {
        const val STEP_MS = 1000L
    }
}
