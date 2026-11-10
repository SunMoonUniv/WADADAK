package com.wadadak.wear

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Wearable
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt

class WearRunActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val poll = Runnable { request("status") }
    private val countdown = WearCountdown()
    private val countdownTick = Runnable { if (visible) render() }
    private val resumeState by lazy { getSharedPreferences("wear_run_resume", MODE_PRIVATE) }
    private var rememberedSession: String? = null
    private var rememberedMode: String? = null
    private var requestTimeout: Runnable? = null
    private var requestId = 0
    private var visible = false
    private var pending = false
    private var activeCommand: String? = null
    private var queued: Pair<String, String?>? = null
    private var available = false
    private var state = JSONObject()
    private var confirming: String? = null
    private var dismissed: String? = null
    private var notice: String? = null
    private var commandNotice: String? = null
    private var commandIssue: String? = null
    private var mode = "free"
    private var page = "home"
    private var itemIndex = 0
    private var touchX = 0f
    private var touchY = 0f
    private var liveIndex = 1
    private var resultIndex = 0
    private var previousSession: String? = null
    private var shownTransition: String? = null
    private var transitionUntil = 0L

    private lateinit var panel: FrameLayout
    private val slots = mutableMapOf<String, View>()
    private var screen = ""
    private var size = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        rememberedSession = resumeState.getString("session", null)
        rememberedMode = resumeState.getString("mode", null)
        dismissed = resumeState.getString("dismissed", null)
        val bounds = windowManager.currentWindowMetrics.bounds
        size = minOf(bounds.width(), bounds.height())
        val root = FrameLayout(this).apply { setBackgroundColor(BACKGROUND) }
        panel = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(BACKGROUND)
                setStroke(px(1), TRACK)
            }
        }
        root.addView(panel, FrameLayout.LayoutParams(size, size, Gravity.CENTER))
        setContentView(root)
        render()
    }

    override fun onStart() {
        super.onStart()
        visible = true
        request("status")
    }

    override fun onStop() {
        visible = false
        available = false
        queued = null
        pending = false
        activeCommand = null
        requestId++
        requestTimeout?.let(handler::removeCallbacks)
        requestTimeout = null
        handler.removeCallbacks(poll)
        handler.removeCallbacks(countdownTick)
        countdown.clear()
        super.onStop()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun request(command: String, sessionId: String? = null) {
        if (!visible || (command != "status" && !available)) return
        if (pending) {
            if (command != "status" && activeCommand == "status" && queued == null) {
                queued = command to sessionId
            }
            return
        }
        handler.removeCallbacks(poll)
        pending = true
        activeCommand = command
        if (command != "status") {
            commandNotice = null
            commandIssue = null
        }
        val token = ++requestId
        val timeout = Runnable { complete(token, null, "폰 응답을 기다리고 있어요.") }
        requestTimeout = timeout
        val timeoutMs = when (command) {
            "status" -> 2500L
            in CATALOG_COMMANDS -> 15000L
            else -> 6500L
        }
        handler.postDelayed(timeout, timeoutMs)
        if (command != "status") render()

        val context = applicationContext
        val payload = JSONObject().put("command", command)
            .put("mode", if (command == "status") rememberedMode ?: mode else mode)
            .put(
                if (command == "start" && mode == "free") "readyId" else "sessionId",
                if (command == "status") rememberedSession else sessionId,
            )
        Wearable.getCapabilityClient(context)
            .getCapability(PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
            .onSuccessTask { capability ->
                if (!visible || !pending || token != requestId) {
                    return@onSuccessTask Tasks.forCanceled<ByteArray>()
                }
                val phone = capability.nodes.firstOrNull { it.isNearby }
                    ?: capability.nodes.firstOrNull()
                    ?: return@onSuccessTask Tasks.forException<ByteArray>(
                        IllegalStateException("Phone unavailable")
                    )
                Wearable.getMessageClient(context)
                    .sendRequest(phone.id, PATH, payload.toString().encodeToByteArray())
            }.addOnCompleteListener { task ->
                val reply = if (task.isSuccessful) {
                    runCatching { JSONObject(task.result.decodeToString()) }.getOrNull()
                } else {
                    null
                }
                complete(token, reply, "폰 연결을 확인해 주세요.")
            }
    }

    private fun complete(token: Int, reply: JSONObject?, failure: String) {
        if (isDestroyed || !pending || requestId != token) return
        requestTimeout?.let(handler::removeCallbacks)
        requestTimeout = null
        pending = false
        val completedCommand = activeCommand
        activeCommand = null
        val next = queued
        queued = null
        val wasAvailable = available
        val previousPhase = state.optString("phase")
        val snapshot = reply?.takeIf { it.optBoolean("bridgeReady", true) }
        val replyNotice = (reply?.opt("message") as? String)?.takeIf { it.isNotBlank() }
        val phase = snapshot?.optString("phase")
        available = snapshot != null && phase != "unavailable"
        if (!available) {
            confirming = null
            commandNotice = null
            commandIssue = null
            countdown.clear()
        } else if (completedCommand != "status" || snapshot?.optBoolean("reselectCourse") == true) {
            commandNotice = replyNotice
            commandIssue = reply?.opt("setupIssue") as? String
        }
        notice = replyNotice ?: if (snapshot == null) failure else commandNotice
        if (snapshot != null) {
            val id = snapshot.opt("sessionId") as? String
            val resumedResult = !wasAvailable && previousPhase != "ended" &&
                phase == "ended" && id != null && id == rememberedSession
            val previousCourseName = state.opt("courseName") as? String
            if (id != null && id == previousSession && phase == "ended" &&
                snapshot.isNull("courseName") && previousCourseName != null) {
                snapshot.put("courseName", previousCourseName)
            }
            val reselect = snapshot.optBoolean("reselectCourse") &&
                (!state.optBoolean("reselectCourse") || completedCommand == "start" ||
                    completedCommand == "prepareCourse")
            state = snapshot
            if (reselect) {
                show("home")
                if (phase == "ended" && id != dismissed && replyNotice != null) {
                    Toast.makeText(this, replyNotice, Toast.LENGTH_LONG).show()
                }
            }
            val runMode = state.optString("mode", "free")
            if (phase in RECORD_PHASES && id != null && id != dismissed) {
                rememberSession(id, runMode)
            } else if (phase == "ready" || phase == "unavailable") {
                rememberSession(null, null)
            }
            if (phase == "preparing") {
                countdown.accept(
                    state.optInt("countdown"), state.optLong("countdownStepRemainingMs", -1L),
                    SystemClock.uptimeMillis(),
                )
            } else {
                countdown.clear()
            }
            if (id != previousSession) {
                if (phase == "approach" && replyNotice == null) {
                    commandNotice = null
                    commandIssue = null
                    notice = null
                }
                previousSession = id
                shownTransition = null
                transitionUntil = 0L
                liveIndex = 1
                resultIndex = 0
            }
            val reason = state.opt("courseEndReason") as? String
            if (resumedResult && id != dismissed && runMode != "free") {
                resultIndex = if (runMode == "ghost") 2 else 1
            }
            if (phase == "running" && reason != null && reason != shownTransition) {
                shownTransition = reason
                if (wasAvailable) transitionUntil = SystemClock.uptimeMillis() + 3500
            }
            when (completedCommand) {
                "courses" -> show("courses")
                "selectCourse" -> if (notice == null) show(if (mode == "ghost") "ghosts" else "courseReady")
                "selectGhost" -> if (notice == null) show("courseReady")
            }
        }
        if (visible) {
            render()
            if (available && next != null) {
                request(next.first, next.second)
            } else {
                val pollDelay = when {
                    !available -> 2500L
                    phase == "preparing" -> 200L
                    phase == "ready" || phase == "approach" -> 450L
                    else -> 1000L
                }
                handler.postDelayed(poll, pollDelay)
            }
        }
    }

    private fun rememberSession(id: String?, mode: String?) {
        if (rememberedSession == id && rememberedMode == mode) return
        rememberedSession = id
        rememberedMode = mode
        resumeState.edit().putString("session", id).putString("mode", mode).apply()
    }

    private fun render() {
        handler.removeCallbacks(countdownTick)
        val id = state.optString("sessionId").takeIf { it.isNotBlank() && it != "null" }
        val phonePhase = state.optString("phase", "unavailable")
        val phase = if (id != null && id == dismissed && phonePhase == "ended") "ready" else phonePhase
        if (confirming != id || phase != "paused") {
            confirming = null
        }
        val setupIssue = state.opt("setupIssue") as? String ?: commandIssue
        val current = when {
            confirming != null -> "confirm"
            phase == "ready" && setupIssue == "permissions" -> "permissions"
            phase == "ready" && setupIssue == "offline" && mode != "free" -> "offline"
            phase == "ready" -> page
            available && phase == "running" && state.optBoolean("deviation") -> "deviation"
            available && phase == "running" && SystemClock.uptimeMillis() < transitionUntil -> "transition"
            available && phase == "running" && state.optBoolean("onCourse") && liveIndex == 0 -> "liveMap"
            available && phase == "running" && state.optBoolean("onCourse") && liveIndex == 2 && state.optString("mode") == "ghost" -> "ghostGap"
            phase == "ended" && resultIndex == 1 -> "courseResult"
            phase == "ended" && resultIndex == 2 -> "ghostResult"
            else -> phase
        }
        val shownMode = when {
            current in BROWSE -> mode
            state.optBoolean("continuing") && phase in listOf("running", "paused", "ending") &&
                current != "transition" -> "free"
            else -> state.optString("mode", "free")
        }
        val verdictStatus = state.optString("verdictStatus")
        val variant = when (current) {
            "courseResult" -> state.optJSONObject("courseResult")?.optBoolean("completed")?.toString() ?: verdictStatus
            "ghostResult" -> state.optJSONObject("ghostResult")?.optString("outcome") ?: verdictStatus
            "ended" -> verdictStatus
            "approach" -> state.optBoolean("nearStart").toString()
            "running" -> state.optBoolean("gpsWeak").toString()
            else -> ""
        }
        val layoutKey = "$current:$shownMode:$variant:$available"
        if (layoutKey != screen) {
            screen = layoutKey
            slots.clear()
            panel.removeAllViews()
        }
        if (phase in listOf("running", "paused", "preparing", "ending")) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        val enabled = available && (!pending || activeCommand == "status")
        val km = String.format(Locale.KOREA, "%.2f", state.optDouble("distanceM", 0.0) / 1000)
        val duration = time(state.optLong("activeMs") / 1000)
        val pace = pace(state.optDouble("pace"))
        when (current) {
            "home" -> renderHome(enabled)
            "courses", "ghosts" -> renderPicker(current, enabled)
            "courseReady" -> renderCourseReady(enabled)
            "approach" -> renderApproach(id, enabled)
            "liveMap" -> renderLiveMap(id, enabled)
            "ghostGap" -> renderGhostGap()
            "deviation" -> renderDeviation(id, shownMode, enabled)
            "transition" -> renderTransition(shownMode, km, duration)
            "courseResult" -> renderCourseResult()
            "ghostResult" -> renderGhostResult()
            "permissions", "offline" -> renderRestriction(current, enabled)
            "preparing" -> renderCountdown(shownMode, enabled)
            "running", "ending" -> {
                label("mode", "●  ${modeTitle(shownMode)}", 49, 15, 118, 14, 11, LIME)
                label("distance", km, 39, 30, 138, 50, 44)
                label("unit", "km", 76, 80, 64, 16, 13, MUTED)
                metric("time", "달린 시간", duration, 43, 98, 57, 18)
                divider(107, 104, 26)
                metric("pace", "평균 페이스", pace, 117, 98, 60, 18)
                val status = when {
                    phase == "ending" -> "기록 저장 중"
                    state.optBoolean("continuing") -> "이어서 기록 중"
                    shownMode == "ghost" && state.optDouble("ghostTimeDeltaMs").isFinite() -> timeGap()
                    state.optBoolean("onCourse") -> "코스 " + formatDistance(state.optDouble("remainingM")) + " 남음"
                    else -> "기록 중"
                }
                when {
                    !available -> renderConnectionWarning(132)
                    state.optBoolean("gpsWeak") -> {
                        label("warning", "GPS 신호 약함", 31, 132, 154, 14, 11, PALE_AMBER)
                        label("warning-detail", "시간 기록 중 · 거리 갱신 대기", 31, 146, 154, 12, 10, MUTED)
                    }
                    else -> label("status", status, 34, 138, 148, 21, 11, MUTED)
                }
                button("pause", "Ⅱ  일시정지", 54, 161, 108, 34, false,
                    enabled && phase == "running") { request("pause", id) }
                if (available && state.optBoolean("onCourse")) liveNav()
            }
            "paused" -> {
                label("mode", modeTitle(shownMode), 57, 17, 102, 12, 10, MUTED)
                label("title", "일시정지", 36, 33, 144, 27, 22)
                metric("distance", "거리", "$km km", 21, 69, 62, 14)
                metric("time", "달린 시간", duration, 84, 69, 52, 14)
                metric("pace", "평균 페이스", pace, 138, 69, 57, 14)
                if (available) {
                    label("status", notice ?: if (shownMode == "ghost") "고스트는 계속 달리고 있어요" else "",
                        37, 106, 142, 17, 10, MUTED)
                } else {
                    renderConnectionWarning(101)
                }
                button("resume", "재개", 48, 126, 120, 39, true, enabled) { request("resume", id) }
                button("end", "종료", 52, 168, 112, 33, false, enabled) {
                    confirming = id
                    render()
                }
            }
            "confirm" -> {
                label("mode", modeTitle(shownMode), 57, 17, 102, 12, 10, MUTED)
                label("title", "러닝을\n종료할까요?", 33, 34, 150, 52, 21)
                label("detail", notice ?: "지금까지의 기록을 저장해요", 33, 87, 150, 20, 11, MUTED)
                button("save", "종료하고 저장", 40, 112, 136, 40, true, enabled) { request("end", id) }
                button("cancel", "취소", 54, 160, 108, 34, false, true) {
                    confirming = null
                    render()
                }
            }
            "ended" -> {
                label("mode", modeTitle(shownMode), 56, 16, 104, 12, 10, LIME)
                val hasCourse = shownMode != "free"
                label("title", if (hasCourse) "전체 기록" else "러닝 요약", 40, 31, 136, 22, 18)
                label("distance", km, 41, 53, 103, 48, 40)
                label("unit", "km", 144, 68, 27, 20, 13, MUTED)
                metric("time", "달린 시간", duration, 43, 107, 57, 17)
                divider(107, 112, 24)
                metric("pace", "평균 페이스", pace, 117, 107, 60, 17)
                val verdict = if (shownMode == "ghost") "ghostResult" else "courseResult"
                val waitingForVerdict = hasCourse && state.optJSONObject(verdict) == null
                val verdictFailed = waitingForVerdict && verdictStatus == "failed"
                val status = when {
                    verdictFailed -> "판정 실패 · 폰에서 확인"
                    !available -> "폰 연결 끊김"
                    waitingForVerdict && verdictStatus == "pending" ->
                        if (state.optBoolean("saved")) "기기 저장 · 판정 대기" else "판정 대기"
                    state.optBoolean("saved") -> "기록 저장 완료"
                    else -> "저장된 기록 없음"
                }
                label("status", status, 35, if (hasCourse) 139 else 147, 146, 14, 10,
                    if (verdictFailed || !available) PALE_AMBER else MUTED)
                if (hasCourse) {
                    resultLink("코스 결과 ›", 1, 153)
                    arrow("result-next", "›", 180, 89, 32, 44) { showResult(1) }
                }
                button("done", "완료", 52, if (hasCourse) 175 else 166, 112, if (hasCourse) 30 else 35, true, true) {
                    dismissed = id
                    resumeState.edit().putString("dismissed", id).apply()
                    rememberSession(null, null)
                    show("home")
                    render()
                }
            }
            else -> {
                label("brand", "와다닥", 55, 47, 106, 15, 11, MUTED)
                label("title", "자유 러닝", 34, 72, 148, 29, 24)
                label("detail", notice ?: "폰 연결을 확인하고 있어요.", 36, 109, 144, 50, 12, MUTED)
            }
        }
    }

    private fun renderCountdown(shownMode: String, enabled: Boolean) {
        if (!available) {
            label("mode", "폰 연결 끊김", 34, 69, 148, 24, 17, PALE_AMBER)
            label("detail", "연결되면 시작 상태를 확인해요", 30, 104, 156, 32, 12, MUTED)
            return
        }

        val title = if (shownMode == "free") "러닝을 시작해요" else "${modeTitle(shownMode)} 시작"
        label("mode", title, 34, 47, 148, 16, 13, MUTED, bold = true)
        val now = SystemClock.uptimeMillis()
        val count = if (state.has("countdownStepRemainingMs")) {
            countdown.numberAt(now)
        } else {
            state.optInt("countdown").takeIf { it in 1..3 }
        }
        label("countdown", count?.toString() ?: "…", 32, 69, 152, 83, 68, LIME)
        countdown.nextTickAfter(now)?.let { handler.postDelayed(countdownTick, it) }
        if (state.optBoolean("canCancel")) {
            button("cancel", "시작 취소", 55, 161, 106, 34, false, enabled) { request("cancelStart") }
            slots["cancel"]?.visibility = View.VISIBLE
        } else {
            slots["cancel"]?.visibility = View.GONE
        }
    }

    private fun renderConnectionWarning(y: Int) {
        label("warning", "폰 연결 끊김", 31, y, 154, 13, 11, PALE_AMBER)
        label("warning-detail", "마지막으로 받은 기록", 31, y + 13, 154, 12, 10, MUTED)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchX = event.x
                touchY = event.y
            }
            MotionEvent.ACTION_UP -> {
                val dx = event.x - touchX
                val dy = event.y - touchY
                val ready = state.optString("phase") == "ready" ||
                    state.optString("sessionId") == dismissed
                if (screen.startsWith("home:") && abs(dy) > px(32) && abs(dy) > abs(dx)) {
                    cancelTouch(event)
                    shiftMode(if (dy < 0) 1 else -1)
                    return true
                }
                if (abs(dx) > px(32) && abs(dx) > abs(dy)) {
                    val phase = state.optString("phase")
                    val delta = if (dx < 0) 1 else -1
                    if (phase == "running" && state.optBoolean("onCourse") && !state.optBoolean("deviation")) {
                        cancelTouch(event)
                        shiftLive(delta)
                        return true
                    }
                    if (phase == "ended" && state.optString("mode", "free") != "free" &&
                        state.optString("sessionId") != dismissed) {
                        cancelTouch(event)
                        showResult(resultIndex + delta)
                        return true
                    }
                }
                if (ready && page in listOf("courses", "ghosts") &&
                    abs(dy) > px(24) && abs(dy) > abs(dx)) {
                    cancelTouch(event)
                    val count = state.optJSONArray(page)?.length() ?: 0
                    if (count > 0) itemIndex = (itemIndex + if (dy < 0) 1 else -1).coerceIn(0, count - 1)
                    render()
                    return true
                }
            }
        }
        return super.dispatchTouchEvent(event)
    }

    private fun cancelTouch(event: MotionEvent) {
        val cancel = MotionEvent.obtain(event)
        cancel.action = MotionEvent.ACTION_CANCEL
        super.dispatchTouchEvent(cancel)
        cancel.recycle()
    }

    private fun shiftLive(delta: Int) {
        val max = if (state.optString("mode") == "ghost") 2 else 1
        liveIndex = (liveIndex + delta).coerceIn(0, max)
        render()
    }

    private fun liveNav() {
        val count = if (state.optString("mode") == "ghost") 3 else 2
        if (liveIndex > 0) arrow("live-left", "‹", 4, 81, 32, 44) { shiftLive(-1) }
        if (liveIndex < count - 1) arrow("live-right", "›", 180, 81, 32, 44) { shiftLive(1) }
        var x = if (count == 3) 92 else 96
        for (i in 0 until count) {
            val key = "live-dot-$i"
            val width = if (i == liveIndex) 14 else 5
            if (key !in slots) {
                val dot = View(this).apply { background = pill(if (i == liveIndex) LIME else DOT, 3) }
                place(key, dot, x, 200, width, 5)
            }
            x += width + 4
        }
    }

    private fun timeGap(): String {
        val delta = state.optDouble("ghostTimeDeltaMs")
        if (!delta.isFinite()) return "시간차 확인 중"
        val seconds = (abs(delta) / 1000).roundToInt()
        return when {
            seconds == 0 -> "나란히 달리는 중"
            delta < 0 -> "${seconds}초 앞섬"
            else -> "${seconds}초 뒤처짐"
        }
    }

    private fun renderLiveMap(id: String?, enabled: Boolean) {
        label("mode", "코스 지도", 65, 16, 86, 14, 11, LIME)
        label("title", state.optString("courseName", "선택한 코스"), 46, 30, 124, 20, 14)
        val map = slots["route"] as? RouteMap ?: RouteMap().apply {
            background = pill(BUTTON, 14, BUTTON_LINE)
            clipToOutline = true
            place("route", this, 24, 53, 168, 85)
        }
        map.update(state.optJSONArray("route"), state.optJSONArray("position"),
            state.optJSONArray("ghostPosition"), true)
        val legend = if (state.optString("mode") == "ghost") "● 현재 위치  ·  ● 고스트" else "● 현재 위치"
        label("detail", if (state.optBoolean("gpsWeak")) "GPS 신호 약함" else legend, 43, 141, 130, 16, 10, MUTED)
        button("pause", "Ⅱ  일시정지", 54, 161, 108, 34, false, enabled) { request("pause", id) }
        liveNav()
    }

    private fun renderGhostGap() {
        label("mode", "고스트 격차", 50, 19, 116, 14, 11, LIME)
        label("source", "선택한 고스트 기록", 38, 35, 140, 14, 11, MUTED)
        label("time", timeGap(), 31, 53, 154, 37, 27)
        label("detail", "같은 코스 지점 기준", 40, 88, 136, 16, 11, MUTED)
        surface("gap-card", 44, 108, 128, 46, 12)
        val meters = state.optDouble("ghostDistanceM")
        val detail = when {
            !meters.isFinite() -> "거리 차이 확인 중"
            abs(meters) < .5 -> "같은 위치"
            else -> "${abs(meters).roundToInt()} m ${if (meters > 0) "앞섬" else "뒤처짐"}"
        }
        label("gap", detail, 46, 112, 124, 21, 15)
        label("gap-label", "코스상 거리 차이", 49, 135, 118, 14, 10, MUTED)
        liveNav()
    }

    private fun renderDeviation(id: String?, shownMode: String, enabled: Boolean) {
        label("mode", modeTitle(shownMode), 60, 15, 96, 15, 10, MUTED)
        surface("alert-card", 26, 35, 164, 145, 22, BUTTON_LINE)
        label("mark", "!", 83, 45, 50, 18, 16, AMBER)
        label("title", "코스를 벗어났어요", 33, 67, 150, 25, 16)
        button("confirm", "확인", 47, 101, 122, 36, true, enabled) { request("ackDeviation", id) }
        arrow("mute", "다시 표시하지 않음", 44, 141, 128, 27, 12) {
            if (enabled) request("muteDeviation", id)
        }
    }

    private fun renderTransition(shownMode: String, distance: String, duration: String) {
        val arrived = state.optString("courseEndReason") == "ROUTE_END"
        label("mode", modeTitle(shownMode), 52, 18, 112, 15, 11, MUTED)
        if (arrived) badge("transition-badge", 92, 36, 32, LIME, R.drawable.wear_check)
        else label("trigger", if (state.optString("courseEndReason") == "OFF_ROUTE_TIMEOUT") "코스 이탈 30초 지속" else "코스 구간 종료", 40, 39, 136, 15, 11, AMBER)
        label("title", if (arrived) "코스 끝에\n도착했어요" else "자유 러닝으로\n전환했어요",
            29, if (arrived) 75 else 59, 158, 56, 22)
        label("metrics", "$distance km  ·  $duration", 40, if (arrived) 133 else 121, 136, 24, 15)
        label("detail", if (arrived) "자유 러닝으로 이어집니다" else "거리와 시간을 이어서 기록해요",
            26, if (arrived) 166 else 156, 164, 22, 11, LIME)
    }

    private fun renderRestriction(current: String, enabled: Boolean) {
        label("mode", modeTitle(mode), 55, 17, 106, 16, 11, MUTED)
        val permission = current == "permissions"
        label("title", if (permission) "권한이\n필요해요" else "인터넷 연결이\n필요해요",
            29, 38, 158, 50, 21, AMBER)
        label("detail", if (permission) "폰에서 위치와 신체 활동 권한을\n허용해 주세요"
            else "연결 후 코스에\n다시 도전할 수 있어요", 35, 87, 146, 38, 11, MUTED)
        button("disabled", "러닝 시작", 51, 125, 114, 30, false, false) {}
        button("resolve", if (permission) "설정 열기" else "자유 러닝", 52, 163, 112, 36, true, enabled) {
            if (permission) request("openSettings") else {
                mode = "free"
                show("home")
                request("cancelCourse")
                render()
            }
        }
    }

    private fun showResult(index: Int) {
        val max = if (state.optString("mode") == "ghost") 2 else 1
        resultIndex = index.coerceIn(0, max)
        render()
    }

    private fun resultLink(text: String, index: Int, y: Int) {
        label("result-link-$index", text, 36, y, 144, 19, 11, LIME)
        slots["result-link-$index"]?.setOnClickListener { showResult(index) }
    }

    private fun verdictWarningBadge() {
        surface("verdict-fill", 93, 37, 30, 30, 15, OCHRE, OCHRE)
        label("verdict", "!", 93, 38, 30, 27, 17, AMBER)
    }

    private fun renderCourseResult() {
        val result = state.optJSONObject("courseResult")
        val completed = result?.optBoolean("completed") == true
        val failed = result == null && state.optString("verdictStatus") == "failed"
        label("mode", "코스 결과", 53, 17, 110, 14, 11, MUTED)
        when {
            result == null && !failed -> badge("verdict", 93, 37, 30, OCHRE, R.drawable.wear_clock)
            completed -> badge("verdict", 93, 37, 30, LIME, R.drawable.wear_check)
            else -> verdictWarningBadge()
        }
        val title = when {
            failed -> "판정 실패"
            result == null -> "판정 대기"
            completed -> "완주"
            else -> "미완주"
        }
        if (result == null) {
            label("title", title, 41, 70, 134, 28, 23, PALE_AMBER)
        } else {
            label("title", title, 41, 70, 134, 34, 25, if (completed) LIME else AMBER)
        }
        label("course", result?.opt("name") as? String ?: state.optString("courseName", "선택한 코스"),
            42, 103, 132, 18, 13)
        if (result == null) {
            val detail = when {
                failed -> VERDICT_CHECK_PHONE
                available -> "코스 완주 결과를\n확인하고 있어요"
                else -> "폰 연결을 기다려요\n다시 연결되면 확인해요"
            }
            label("detail", detail, 39, 125, 138, 32, 13, MUTED)
        } else {
            metric("distance", "코스 인정 거리", formatDistance(result.optDouble("recognizedDistanceM")), 38, 128, 69, 15)
            divider(113, 133, 25)
            metric("time", "코스 총 소요", if (completed) time(result.optLong("seconds")) else "—",
                118, 128, 64, 15)
            label("detail", if (completed) "코스 구간 기록" else "코스 도착 전 종료", 44, 169, 128, 15, 10, MUTED)
        }
        resultLink("‹ 전체 기록", 0, 187)
        arrow("left", "‹", 4, 88, 32, 43) { showResult(0) }
        if (state.optString("mode") == "ghost") arrow("right", "›", 180, 88, 32, 43) { showResult(2) }
    }

    private fun renderGhostResult() {
        val result = state.optJSONObject("ghostResult")
        val outcome = result?.optString("outcome")
        val failed = result == null && state.optString("verdictStatus") == "failed"
        val title = when (outcome) {
            "WIN" -> "승리"
            "LOSE" -> "패배"
            "DRAW" -> "무승부"
            "INVALID" -> "무효"
            else -> if (failed) "판정 실패" else "판정 대기"
        }
        val color = when (outcome) {
            "WIN" -> LIME
            "LOSE" -> AMBER
            "DRAW" -> VIOLET
            else -> if (failed) PALE_AMBER else WHITE
        }
        label("mode", "고스트 대결 결과", 50, 17, 116, 15, 11, MUTED)
        if (failed) verdictWarningBadge()
        else badge("ghost-icon", 93, 37, 30, VIOLET, R.drawable.wear_ghost)
        label("title", title, 39, 69, 138, 34, 25, color)
        label("course", "선택한 고스트와 비교", 44, 104, 128, 17, 11)
        if (outcome in listOf("WIN", "LOSE", "DRAW") && result != null) {
            val ours = result.optLong("ours")
            val theirs = result.optLong("theirs")
            metric("our", "이번 코스", time(ours), 42, 128, 63, 16)
            divider(109, 131, 26)
            metric("their", "고스트", time(theirs), 117, 128, 60, 16)
            val delta = abs(theirs - ours)
            val difference = if (delta >= 60) "${delta / 60}분 ${delta % 60}초" else "${delta}초"
            val note = when (outcome) {
                "DRAW" -> "같은 초에 완주했어요"
                "WIN" -> "고스트보다 $difference 빨랐어요"
                else -> "고스트보다 $difference 늦었어요"
            }
            label("detail", note, 31, 166, 154, 18, 10, MUTED)
        } else {
            val detail = when {
                failed -> VERDICT_CHECK_PHONE
                outcome == "INVALID" -> "대결이 정상 완주로\n판정되지 않았어요"
                available -> "서버에서 대결 결과를\n확인하고 있어요"
                else -> "폰 연결을 기다려요\n다시 연결되면 확인해요"
            }
            label("detail", detail, 39, 126, 138, 38, 12, MUTED)
        }
        resultLink("‹ 코스 결과", 1, 187)
        arrow("left", "‹", 4, 88, 32, 43) { showResult(1) }
    }

    private fun surface(key: String, x: Int, y: Int, width: Int, height: Int, radius: Int,
                        stroke: Int? = null, fill: Int = BUTTON) {
        if (key in slots) return
        val view = View(this).apply { background = pill(fill, radius, stroke) }
        place(key, view, x, y, width, height)
    }

    private fun badge(key: String, x: Int, y: Int, size: Int, fill: Int, icon: Int) {
        if (key in slots) return
        val view = ImageView(this).apply {
            background = pill(fill, size / 2)
            val inset = px(6)
            setPadding(inset, inset, inset, inset)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageResource(icon)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        place(key, view, x, y, size, size)
    }

    private fun show(page: String) {
        this.page = page
        itemIndex = 0
    }

    private fun shiftMode(delta: Int) {
        commandNotice = null
        commandIssue = null
        mode = MODES[(MODES.indexOf(mode) + delta).coerceIn(0, MODES.lastIndex)]
        render()
    }

    private fun modeTitle(value: String) = when (value) {
        "course" -> "코스 러닝"
        "ghost" -> "고스트 러닝"
        else -> "자유 러닝"
    }

    private fun renderHome(enabled: Boolean) {
        val index = MODES.indexOf(mode)
        label("brand", "와다닥", 40, 23, 136, 13, 10, MUTED)
        icon(when (mode) {
            "course" -> R.drawable.wear_course
            "ghost" -> R.drawable.wear_ghost
            else -> R.drawable.wear_target
        })
        label("mode", modeTitle(mode), 31, 77, 154, 30, 24)
        val description = when (mode) {
            "course" -> "선택한 코스를 따라 달려요"
            "ghost" -> "이전 기록과 나란히 달려요"
            else -> "코스 없이 자유롭게 달려요"
        }
        label("detail", notice ?: description, 26, 108, 164, 25, 12, MUTED)
        val free = mode == "free"
        button("primary", if (free) "러닝 시작" else "코스 선택", 44, 138, 128, 42,
            true, enabled, longPress = free) {
            if (free) request("start", state.opt("readyId") as? String) else request("courses")
        }
        if (free) label("hint", "길게 눌러 시작", 43, 181, 130, 15, 10, MUTED)
        if (index > 0) {
            arrow("mode-up", "⌃", 67, 1, 82, 22, description = "이전 러닝 모드") { shiftMode(-1) }
        }
        if (index < MODES.lastIndex) {
            arrow("mode-down", "⌄", 67, 194, 82, 22, description = "다음 러닝 모드") { shiftMode(1) }
        }
        var y = 92
        for (i in MODES.indices) {
            val key = "dot-$i"
            val height = if (i == index) 14 else 5
            if (key !in slots) {
                val dot = View(this).apply { background = pill(if (i == index) LIME else DOT, 3) }
                place(key, dot, 193, y, 5, height)
            }
            y += height + 4
        }
    }

    private fun renderPicker(current: String, enabled: Boolean) {
        val items = state.optJSONArray(current) ?: JSONArray()
        val item = items.optJSONObject(itemIndex)
        val pickingGhost = current == "ghosts"
        val title = if (pickingGhost) "고스트 선택" else "코스 선택"
        val subtitle = if (pickingGhost) "함께 달릴 기록을 골라요" else if (mode == "ghost")
            "기록을 비교할 코스를 골라요" else "달릴 코스를 선택해 주세요"
        val caption = if (pickingGhost) state.optString("courseName", modeTitle(mode)) else modeTitle(mode)
        label("mode", caption, 39, 31, 138, 14, 11, LIME)
        label("title", title, 39, 49, 138, 27, 22)
        label("detail", notice ?: subtitle, 33, 80, 150, 24, 11, MUTED)
        if (item == null) {
            label("empty", if (pickingGhost) "이 코스의 완주 기록이 없어요" else "저장하거나 가까운 코스가 없어요",
                35, 117, 146, 42, 12, MUTED)
            slots["card"]?.visibility = View.GONE
        } else {
            slots["empty"]?.visibility = View.GONE
            val detail = if (pickingGhost) time(item.optLong("seconds")) + "  ·  평균 " +
                pace(item.optDouble("seconds") * 1000 / item.optDouble("distanceM"))
                else formatDistance(item.optDouble("distanceM"))
            button("card", item.optString("name") + "  ›\n" + detail, 37, 112, 142, 53,
                false, enabled) {
                request(if (pickingGhost) "selectGhost" else "selectCourse", item.optString("id"))
            }
            slots["card"]?.visibility = View.VISIBLE
        }
        arrow("back", "‹", 88, 166, 40, 33) {
            show(if (pickingGhost) "courses" else "home")
            render()
        }
        if (items.length() > 1) {
            label("index", "${itemIndex + 1} / ${items.length()}", 72, 194, 72, 14, 10, MUTED)
        }
    }

    private fun renderCourseReady(enabled: Boolean) {
        label("mode", modeTitle(mode), 47, 26, 122, 14, 11, LIME)
        label("title", state.optString("courseName", "선택한 코스"), 35, 45, 146, 29, 21)
        val ghostSeconds = state.optLong("ghostSeconds")
        val subtitle = if (mode == "ghost" && ghostSeconds > 0) "내 기록  ·  " + time(ghostSeconds)
            else formatDistance(state.optDouble("courseDistanceM"))
        label("subtitle", subtitle, 35, 77, 146, 16, 12, MUTED)
        label("detail", notice ?: "출발점에서 시작할 수 있어요", 27, 95, 162, 21, 11, LIME)
        button("map", "출발점 지도", 44, 118, 128, 42, true, enabled) { request("prepareCourse") }
        label("hint", "지도에서 출발점 확인", 38, 164, 140, 15, 10, MUTED)
        arrow("change", "선택 변경", 70, 178, 76, 23, 11) {
            show(if (mode == "ghost") "ghosts" else "courses")
            render()
        }
    }

    private fun renderApproach(id: String?, enabled: Boolean) {
        mode = state.optString("mode", "course")
        label("mode", modeTitle(mode), 66, 15, 84, 13, 10, MUTED)
        label("title", state.optString("courseName", "출발점"), 53, 29, 110, 20, 14)
        arrow("back", "‹", 30, 17, 30, 32) {
            show("courseReady")
            request("cancelCourse", id)
        }
        val map = slots["route"] as? RouteMap ?: RouteMap().apply {
            background = pill(BUTTON, 14, BUTTON_LINE)
            clipToOutline = true
            place("route", this, 24, 49, 168, 85)
        }
        map.update(state.optJSONArray("route"), state.optJSONArray("position"))
        val near = state.optBoolean("nearStart")
        val meters = state.optDouble("startDistanceM", 0.0).roundToInt()
        label("detail", notice ?: if (near) "출발점 도착  ·  $meters m" else "출발점까지 $meters m",
            34, 135, 148, 20, 11, if (near) LIME else WHITE)
        button("start", "러닝 시작", 50, 154, 116, 38, true, enabled && near, longPress = true) {
            request("start", id)
        }
        label("hint", if (near) "길게 눌러 시작" else "출발점으로 이동", 42, 193, 132, 14, 10, MUTED)
    }

    private fun arrow(
        key: String, value: String, x: Int, y: Int, width: Int, height: Int,
        size: Int = 20, description: String? = null, action: () -> Unit,
    ) {
        label(key, value, x, y, width, height, size, MUTED)
        slots[key]?.apply {
            if (description != null) contentDescription = description
            setOnClickListener { action() }
        }
    }

    private fun formatDistance(meters: Double) =
        if (meters.isFinite()) String.format(Locale.KOREA, "%.1f km", meters / 1000) else "—"

    private inner class RouteMap : View(this@WearRunActivity) {
        private var route = emptyList<List<Pair<Double, Double>>>()
        private var position: Pair<Double, Double>? = null
        private var ghost: Pair<Double, Double>? = null
        private var showFinish = false
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private fun point(a: JSONArray): Pair<Double, Double>? {
            val lat = a.optDouble(0)
            val lon = a.optDouble(1)
            return if (lat.isFinite() && lon.isFinite()) lat to lon else null
        }
        fun update(segments: JSONArray?, current: JSONArray?, ghost: JSONArray? = null, finish: Boolean = false) {
            route = (0 until (segments?.length() ?: 0)).mapNotNull { index ->
                segments?.optJSONArray(index)?.let { segment ->
                    (0 until segment.length()).mapNotNull { segment.optJSONArray(it)?.let(::point) }
                }
            }.filter { it.isNotEmpty() }
            position = current?.let(::point)
            this.ghost = ghost?.let(::point)
            showFinish = finish
            invalidate()
        }
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val start = route.firstOrNull()?.firstOrNull() ?: return
            val marker = if (showFinish) route.last().last() else start
            val points = route.flatten() + listOfNotNull(position, ghost)
            val lat = points.map { it.first }
            val lon = points.map { it.second }
            val aspect = cos(Math.toRadians(start.first)).coerceAtLeast(.01)
            val latMid = (lat.max() + lat.min()) / 2
            val lonMid = (lon.max() + lon.min()) / 2
            val scale = minOf(
                (height - 2 * px(10)) / (lat.max() - lat.min()).coerceAtLeast(.00001),
                (width - 2 * px(10)) / ((lon.max() - lon.min()) * aspect).coerceAtLeast(.00001),
            )
            fun x(p: Pair<Double, Double>) = (width / 2 + (p.second - lonMid) * aspect * scale).toFloat()
            fun y(p: Pair<Double, Double>) = (height / 2 - (p.first - latMid) * scale).toFloat()
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = px(3).toFloat()
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeJoin = Paint.Join.ROUND
            paint.color = LIME
            for (segment in route) {
                val path = Path().apply {
                    moveTo(x(segment.first()), y(segment.first()))
                    for (point in segment.drop(1)) lineTo(x(point), y(point))
                }
                canvas.drawPath(path, paint)
            }
            val current = position
            if (current != null) {
                paint.strokeWidth = px(1).toFloat()
                paint.color = WHITE
                paint.pathEffect = DashPathEffect(floatArrayOf(px(4).toFloat(), px(3).toFloat()), 0f)
                if (!showFinish) canvas.drawLine(x(current), y(current), x(start), y(start), paint)
                paint.pathEffect = null
                paint.style = Paint.Style.FILL
                paint.color = 0xff5ab7f3.toInt()
                canvas.drawCircle(x(current), y(current), px(5).toFloat(), paint)
            }
            paint.style = Paint.Style.FILL
            ghost?.let {
                paint.color = VIOLET
                canvas.drawCircle(x(it), y(it), px(4).toFloat(), paint)
            }
            paint.color = if (showFinish) WHITE else LIME
            canvas.drawCircle(x(marker), y(marker), px(8).toFloat(), paint)
            val pin = getDrawable(if (showFinish) R.drawable.wear_finish else R.drawable.wear_course) ?: return
            val left = x(marker).roundToInt() - px(5)
            val top = y(marker).roundToInt() - px(5)
            pin.setBounds(left, top, left + px(10), top + px(10))
            pin.draw(canvas)
        }
    }

    private fun metric(key: String, caption: String, value: String, x: Int, y: Int, width: Int, size: Int) {
        label("$key-caption", caption, x, y, width, 12, 10, MUTED)
        label("$key-value", value, x, y + 15, width, size + 4, size)
    }

    private fun divider(x: Int, y: Int, height: Int) {
        if (slots.containsKey("divider")) return
        val view = View(this).apply { setBackgroundColor(TRACK) }
        place("divider", view, x, y, 1, height)
    }

    private fun icon(resource: Int) {
        if (slots.containsKey("icon")) return
        val view = ImageView(this).apply {
            background = pill(LIME, 16)
            val inset = px(5)
            setPadding(inset, inset, inset, inset)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageResource(resource)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        place("icon", view, 93, 41, 31, 31)
    }

    private fun label(
        key: String, value: String, x: Int, y: Int, width: Int, height: Int, size: Int,
        color: Int = WHITE,
        bold: Boolean = color != MUTED,
    ) {
        val view = slots[key] as? TextView ?: TextView(this).apply {
            gravity = Gravity.CENTER
            includeFontPadding = false
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
            setTextSize(TypedValue.COMPLEX_UNIT_PX, px(size).toFloat())
            setTextColor(color)
            if (key == "status") accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            place(key, this, x, y, width, height)
        }
        if (view.text != value) view.text = value
    }

    private fun button(
        key: String, label: String, x: Int, y: Int, width: Int, height: Int,
        accent: Boolean, enabled: Boolean, longPress: Boolean = false, onClick: () -> Unit,
    ) {
        val view = slots[key] as? Button ?: Button(this).apply {
            text = label
            isAllCaps = false
            gravity = Gravity.CENTER
            includeFontPadding = false
            minWidth = 0
            minHeight = 0
            minimumWidth = 0
            minimumHeight = 0
            setPadding(0, 0, 0, 0)
            stateListAnimator = null
            typeface = Typeface.DEFAULT_BOLD
            setTextSize(TypedValue.COMPLEX_UNIT_PX, px(if (accent) 16 else 13).toFloat())
            setTextColor(if (accent) INK else WHITE)
            background = RippleDrawable(
                ColorStateList.valueOf(0x26000000),
                pill(if (accent) LIME else BUTTON, height / 2, if (accent) null else BUTTON_LINE),
                null,
            )
            place(key, this, x, y, width, height)
        }
        if (view.text != label) view.text = label
        view.isEnabled = enabled
        view.alpha = if (enabled) 1f else .5f
        view.setOnClickListener(if (longPress) null else View.OnClickListener { onClick() })
        view.setOnLongClickListener(if (longPress) View.OnLongClickListener { onClick(); true } else null)
    }

    private fun place(key: String, view: View, x: Int, y: Int, width: Int, height: Int) {
        panel.addView(view, FrameLayout.LayoutParams(px(width), px(height), Gravity.TOP or Gravity.LEFT).apply {
            leftMargin = px(x)
            topMargin = px(y)
        })
        slots[key] = view
    }

    private fun pill(color: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = px(radius).toFloat()
        if (stroke != null) setStroke(px(1), stroke)
    }

    private fun px(value: Int) = (value * size / 216f).roundToInt()

    private fun time(seconds: Long): String =
        if (seconds >= 3600) String.format(Locale.KOREA, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        else String.format(Locale.KOREA, "%02d:%02d", seconds / 60, seconds % 60)

    private fun pace(seconds: Double): String {
        if (!seconds.isFinite() || seconds <= 0) return "—"
        val rounded = seconds.roundToInt()
        return String.format(Locale.KOREA, "%d′%02d″", rounded / 60, rounded % 60)
    }

    private companion object {
        val MODES = listOf("course", "free", "ghost")
        val CATALOG_COMMANDS = setOf("courses", "selectCourse", "selectGhost")
        val BROWSE = setOf("home", "courses", "ghosts", "courseReady")
        val RECORD_PHASES = setOf("running", "paused", "ending", "ended")
        const val VERDICT_CHECK_PHONE = "폰에서 와다닥을 열고\n기록을 확인해 주세요"
        const val PALE_AMBER = 0xffffe0a8.toInt()
        const val AMBER = 0xffffc47d.toInt()
        const val OCHRE = 0xff473829.toInt()
        const val VIOLET = 0xffb69bff.toInt()
        const val DOT = 0xff4a504c.toInt()
        const val BACKGROUND = 0xff111713.toInt()
        const val TRACK = 0xff2c322e.toInt()
        const val LIME = 0xffc3f25c.toInt()
        const val MUTED = 0xffbdbdbd.toInt()
        const val WHITE = 0xffffffff.toInt()
        const val INK = 0xff171b19.toInt()
        const val BUTTON = 0xff222c28.toInt()
        const val BUTTON_LINE = 0xff43524c.toInt()
        const val PHONE_CAPABILITY = "wadadak_phone_free_run_v1"
        const val PATH = "/wadadak/free-run/v1"
    }
}
