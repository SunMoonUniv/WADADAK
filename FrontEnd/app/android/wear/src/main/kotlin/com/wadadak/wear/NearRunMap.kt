package com.wadadak.wear

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.location.Location
import android.view.View
import org.json.JSONArray
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

private data class MapPoint(val lat: Double, val lon: Double) {
    fun measureTo(target: MapPoint, result: FloatArray) {
        Location.distanceBetween(lat, lon, target.lat, target.lon, result)
    }

    companion object {

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
    private val rangeClip = Path()
    private val measurement = FloatArray(2)
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
        contentDescription = if (position == null) "현재 위치 확인 중" else "내 위치 중심 반경 100 m 지도"
        invalidate()
    }

    private fun updateHeading() {
        val current = position ?: return
        val segment = track.lastOrNull() ?: return
        val latest = segment.last()
        current.measureTo(latest, measurement)
        if (measurement[0] > 30) return
        // Use recent movement in one recorded segment, with enough displacement to ignore jitter.
        for (i in segment.lastIndex - 1 downTo 0) {
            segment[i].measureTo(latest, measurement)
            val meters = measurement[0]
            if (meters > 60) return
            if (meters >= 8) {
                heading = Math.toRadians(measurement[1].toDouble())
                return
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val unit = width / 188f
        val centerX = width / 2f
        val centerY = height / 2f
        val radius = minOf(centerX, centerY) - unit
        if (radius <= 0f) return
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = unit
        paint.color = 0xff34463e.toInt()
        canvas.drawCircle(centerX, centerY, radius, paint)

        val origin = position
        if (origin != null) {
            val angle = heading ?: 0.0
            val pixelsPerMeter = radius / RADIUS_METERS
            fun project(point: MapPoint): PointF {
                origin.measureTo(point, measurement)
                val distance = measurement[0] * pixelsPerMeter
                val bearing = Math.toRadians(measurement[1].toDouble()) - angle
                return PointF(
                    centerX + (sin(bearing) * distance).toFloat(),
                    centerY - (cos(bearing) * distance).toFloat(),
                )
            }

            rangeClip.rewind()
            rangeClip.addCircle(centerX, centerY, radius, Path.Direction.CW)
            val saved = canvas.save()
            canvas.clipPath(rangeClip)
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeJoin = Paint.Join.ROUND
            drawLines(canvas, route, 0xffd4dfd8.toInt(), 4.5f * unit, ::project)
            drawLines(canvas, track, lime, 5.5f * unit, ::project)
            ghost?.let {
                val point = project(it)
                if (hypot(point.x - centerX, point.y - centerY) <= radius) {
                    drawMarker(canvas, point.x, point.y, 6 * unit, violet, unit)
                    drawDisc(canvas, point.x, point.y, 2 * unit, backgroundColor)
                }
            }
            canvas.restoreToCount(saved)

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
        paint.style = Paint.Style.FILL
        paint.color = muted
        paint.textSize = 8 * unit
        canvas.drawText("반경 100 m", 12 * unit, height - 14 * unit, paint)
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

    private companion object {
        const val RADIUS_METERS = 100f
    }
}
