package com.wadadak.wear

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.view.View
import org.json.JSONArray
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

private data class MapPoint(val lat: Double, val lon: Double) {
    fun eastFrom(origin: MapPoint) = (lon - origin.lon) * METERS_PER_DEGREE *
        cos(Math.toRadians(origin.lat))
    fun northFrom(origin: MapPoint) = (lat - origin.lat) * METERS_PER_DEGREE

    companion object {
        private const val METERS_PER_DEGREE = 111195.08

        fun fromJson(point: JSONArray?): MapPoint? {
            val lat = point?.optDouble(0) ?: return null
            val lon = point.optDouble(1)
            return if (lat in -90.0..90.0 && lon in -180.0..180.0) MapPoint(lat, lon) else null
        }
    }
}

private fun mapSegments(segments: JSONArray?): List<List<MapPoint>> =
    (0 until (segments?.length() ?: 0)).mapNotNull { index ->
        segments?.optJSONArray(index)?.let { segment ->
            (0 until segment.length()).mapNotNull { MapPoint.fromJson(segment.optJSONArray(it)) }
        }
    }.filter { it.isNotEmpty() }

internal class NearRunMap(
    context: Context,
    private val lime: Int,
    private val violet: Int,
    private val muted: Int,
    private val backgroundColor: Int,
) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()
    private var route = emptyList<List<MapPoint>>()
    private var track = emptyList<List<MapPoint>>()
    private var position: MapPoint? = null
    private var ghost: MapPoint? = null
    private var heading: Double? = null

    fun update(
        course: JSONArray?,
        recorded: JSONArray?,
        current: JSONArray?,
        opponent: JSONArray?,
        gpsWeak: Boolean,
    ) {
        route = mapSegments(course)
        track = mapSegments(recorded)
        position = MapPoint.fromJson(current)
        ghost = MapPoint.fromJson(opponent)
        if (!gpsWeak) updateHeading()
        contentDescription = if (position == null) "현재 위치 확인 중" else "내 위치 주변 100 m 축척 지도"
        invalidate()
    }

    private fun updateHeading() {
        val current = position ?: return
        val segment = track.lastOrNull() ?: return
        val latest = segment.last()
        if (hypot(latest.eastFrom(current), latest.northFrom(current)) > 30) return
        // Use recent movement in one recorded segment, with enough displacement to ignore jitter.
        for (i in segment.lastIndex - 1 downTo 0) {
            val previous = segment[i]
            val east = latest.eastFrom(previous)
            val north = latest.northFrom(previous)
            val meters = hypot(east, north)
            if (meters > 60) return
            if (meters >= 8) {
                heading = atan2(east, north)
                return
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val unit = width / 188f
        val scale = 0.32f * unit
        val centerX = width * 0.52f
        val centerY = height * 0.58f
        val origin = position
        if (origin != null) {
            val angle = heading ?: 0.0
            val sine = sin(angle)
            val cosine = cos(angle)
            fun project(point: MapPoint): PointF {
                val east = point.eastFrom(origin)
                val north = point.northFrom(origin)
                return PointF(
                    centerX + ((east * cosine - north * sine) * scale).toFloat(),
                    centerY - ((east * sine + north * cosine) * scale).toFloat(),
                )
            }
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeJoin = Paint.Join.ROUND
            paint.pathEffect = DashPathEffect(floatArrayOf(3f * unit, 6f * unit), 0f)
            drawLines(canvas, route, 0xffd4dfd8.toInt(), 4.5f * unit, ::project)
            paint.pathEffect = null
            drawLines(canvas, track, lime, 5.5f * unit, ::project)
            ghost?.let {
                val point = project(it)
                drawMarker(canvas, point.x, point.y, 6 * unit, violet, unit)
                drawDisc(canvas, point.x, point.y, 2 * unit, backgroundColor)
            }
            drawMarker(canvas, centerX, centerY, 8 * unit, lime, unit)
            if (heading != null) {
                path.reset()
                path.moveTo(centerX, centerY - 4 * unit)
                path.lineTo(centerX + 3.5f * unit, centerY + 3 * unit)
                path.lineTo(centerX, centerY + unit)
                path.lineTo(centerX - 3.5f * unit, centerY + 3 * unit)
                path.close()
                paint.color = backgroundColor
                canvas.drawPath(path, paint)
            }
        }
        drawScale(canvas, unit, scale)
    }

    private fun drawLines(
        canvas: Canvas, segments: List<List<MapPoint>>, color: Int, width: Float,
        project: (MapPoint) -> PointF,
    ) {
        paint.style = Paint.Style.STROKE
        paint.color = color
        paint.strokeWidth = width
        for (segment in segments) {
            if (segment.size < 2) continue
            path.reset()
            val first = project(segment.first())
            path.moveTo(first.x, first.y)
            for (i in 1 until segment.size) {
                val point = project(segment[i])
                path.lineTo(point.x, point.y)
            }
            canvas.drawPath(path, paint)
        }
    }

    private fun drawMarker(canvas: Canvas, x: Float, y: Float, radius: Float, color: Int, unit: Float) {
        drawDisc(canvas, x, y, radius + 2 * unit, backgroundColor)
        drawDisc(canvas, x, y, radius, color)
    }

    private fun drawDisc(canvas: Canvas, x: Float, y: Float, radius: Float, color: Int) {
        paint.style = Paint.Style.FILL
        paint.color = color
        canvas.drawCircle(x, y, radius, paint)
    }

    private fun drawScale(canvas: Canvas, unit: Float, scale: Float) {
        val left = 19 * unit
        val right = left + 100 * scale
        val y = height - 12 * unit
        paint.style = Paint.Style.FILL
        paint.color = backgroundColor
        canvas.drawRoundRect(left - 3 * unit, y - 13 * unit, right + 3 * unit, y + 5 * unit,
            3 * unit, 3 * unit, paint)
        paint.color = muted
        paint.strokeWidth = unit
        canvas.drawLine(left, y, right, y, paint)
        canvas.drawLine(left, y, left, y + 3 * unit, paint)
        canvas.drawLine(right, y, right, y + 3 * unit, paint)
        paint.textSize = 8 * unit
        canvas.drawText("100 m", left, y - 4 * unit, paint)
    }
}
