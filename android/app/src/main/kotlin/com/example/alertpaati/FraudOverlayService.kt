package com.example.alertpaati

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Draws a system-level overlay banner during an active call showing the
 * current fraud risk level from Gemma.
 *
 * Requires [Settings.canDrawOverlays] == true (SYSTEM_ALERT_WINDOW permission).
 * The user is directed to grant this in Settings the first time.
 */
class FraudOverlayService(private val context: Context) {

    companion object {
        private const val TAG = "FraudOverlay"
    }

    private val windowManager by lazy {
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    private var overlayView: View? = null

    // ── Public API ────────────────────────────────────────────────────────────

    fun show(fraudData: Map<String, Any>) {
        if (!Settings.canDrawOverlays(context)) {
            Log.w(TAG, "SYSTEM_ALERT_WINDOW not granted — skipping overlay")
            return
        }

        val level = fraudData["level"] as? String ?: "safe"
        val explanation = fraudData["explanation"] as? String ?: ""
        val score = (fraudData["score"] as? Number)?.toFloat() ?: 0f

        if (level == "safe") {
            hide()
            return
        }

        hide() // remove any existing overlay first

        val view = buildOverlayView(level, explanation, score)
        overlayView = view

        val params = buildLayoutParams()
        try {
            windowManager.addView(view, params)
            Log.d(TAG, "Overlay shown: $level (score=$score)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add overlay view", e)
        }
    }

    fun hide() {
        val view = overlayView ?: return
        try {
            windowManager.removeView(view)
        } catch (_: Exception) { /* already removed */ }
        overlayView = null
    }

    // ── View construction ─────────────────────────────────────────────────────

    private fun buildOverlayView(
        level: String,
        explanation: String,
        score: Float,
    ): View {
        val bgColor = when (level) {
            "danger"     -> Color.argb(230, 183, 28, 28)   // deep red
            "suspicious" -> Color.argb(230, 230, 81, 0)    // deep orange
            else         -> Color.argb(230, 27, 94, 32)    // green
        }

        val iconRes = when (level) {
            "danger"     -> android.R.drawable.ic_dialog_alert
            "suspicious" -> android.R.drawable.ic_dialog_info
            else         -> android.R.drawable.ic_dialog_info
        }

        val title = when (level) {
            "danger"     -> "⚠ FRAUD DETECTED"
            "suspicious" -> "ℹ SUSPICIOUS CALL"
            else         -> "✓ SAFE"
        }

        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(bgColor)
            setPadding(24, 16, 24, 16)
            gravity = Gravity.CENTER_VERTICAL

            // Icon
            addView(ImageView(context).apply {
                setImageResource(iconRes)
                setColorFilter(Color.WHITE)
                layoutParams = LinearLayout.LayoutParams(48, 48).also {
                    it.marginEnd = 12
                }
            })

            // Text column
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
                )

                addView(TextView(context).apply {
                    text = "$title  ${(score * 100).toInt()}%"
                    setTextColor(Color.WHITE)
                    textSize = 13f
                    setTypeface(null, android.graphics.Typeface.BOLD)
                })

                if (explanation.isNotEmpty()) {
                    addView(TextView(context).apply {
                        text = explanation
                        setTextColor(Color.parseColor("#CCFFFFFF"))
                        textSize = 11f
                        maxLines = 2
                    })
                }
            })

            // Dismiss button
            addView(TextView(context).apply {
                text = "✕"
                setTextColor(Color.WHITE)
                textSize = 16f
                setPadding(12, 0, 0, 0)
                setOnClickListener { hide() }
            })
        }
    }

    private fun buildLayoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
        }
    }
}
