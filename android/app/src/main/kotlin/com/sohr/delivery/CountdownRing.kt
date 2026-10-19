package com.sohr.delivery

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator

/**
 * The smooth green countdown arc drawn directly on the white circular ring of the bell badge.
 */
class CountdownRing @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {

    private val density = resources.displayMetrics.density
    private val strokeWidth = 3.5f * density

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = this@CountdownRing.strokeWidth
        color = 0xFFFFFFFF.toInt() // Solid crisp white ring
    }

    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = this@CountdownRing.strokeWidth
        strokeCap = Paint.Cap.ROUND
        color = 0xFF1EBE5D.toInt() // Vibrant green countdown arc
    }

    private val bounds = RectF()
    private var animator: ValueAnimator? = null

    var progress: Float = 1f
        set(value) {
            val clamped = value.coerceIn(0f, 1f)
            if (field == clamped) return
            field = clamped
            postInvalidateOnAnimation()
        }

    fun start(durationMs: Long) {
        stop()
        progress = 1f
        if (durationMs <= 0) {
            progress = 0f
            return
        }
        animator = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = durationMs
            interpolator = LinearInterpolator()
            addUpdateListener { progress = it.animatedValue as Float }
            start()
        }
    }

    fun stop() {
        animator?.cancel()
        animator = null
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val inset = strokeWidth / 2f + (0.5f * density)
        bounds.set(inset, inset, width - inset, height - inset)

        // 1. Base white circular ring
        canvas.drawOval(bounds, trackPaint)

        // 2. Green countdown arc sweeping clockwise from 12 o'clock (-90°)
        if (progress > 0f) {
            val sweep = progress * 360f
            canvas.drawArc(bounds, -90f, sweep, false, progressPaint)
        }
    }
}
