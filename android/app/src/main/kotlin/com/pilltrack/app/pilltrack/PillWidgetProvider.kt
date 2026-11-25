package com.pilltrack.app.pilltrack

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home-screen widget showing up to three of today's pending doses.
 *
 * Data is written by the Dart WidgetService (all values as strings). This side
 * only renders it, but it does two things on its own each redraw so the widget
 * stays honest while the app is closed:
 *  - marks a dose "Due" once its scheduled time has passed, and
 *  - treats data saved on an earlier day as stale instead of showing it.
 */
class PillWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context, widgetData))
        }
    }

    private fun buildViews(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.pill_widget)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )

        val now = Date()
        val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)
        val hasData = data.contains("date_key")
        val stale = data.getString("date_key", null) != todayKey

        views.setTextViewText(
            R.id.widget_date,
            if (stale) SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(now)
            else data.getString("date_label", ""),
        )

        val count = if (stale) 0 else data.intValue("dose_count")
        ROWS.forEachIndexed { i, row ->
            if (i >= count) {
                views.setViewVisibility(row.container, View.GONE)
                return@forEachIndexed
            }
            val timeMs = data.getString("dose_${i}_time_ms", null)?.toLongOrNull() ?: 0L
            val due = timeMs <= now.time
            val time = data.getString("dose_${i}_time", "") ?: ""
            val dose = data.getString("dose_${i}_dose", "") ?: ""

            views.setViewVisibility(row.container, View.VISIBLE)
            views.setTextViewText(row.name, data.getString("dose_${i}_name", ""))
            views.setTextViewText(row.time, time)
            // "Due" is spelled out, not just signalled by the dot's color.
            views.setTextViewText(
                row.detail,
                if (due) context.getString(R.string.widget_due, dose) else dose,
            )
            views.setTextColor(
                row.dot,
                context.getColor(if (due) R.color.widget_due else R.color.widget_upcoming),
            )
        }

        val more = if (stale) 0 else data.intValue("more_count")
        views.setViewVisibility(R.id.widget_more, if (more > 0) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.widget_more, context.getString(R.string.widget_more, more))

        val emptyText = when {
            !hasData -> context.getString(R.string.widget_get_started)
            stale -> context.getString(R.string.widget_open_app)
            count == 0 -> data.getString("empty_label", null)
                ?: context.getString(R.string.widget_open_app)
            else -> null
        }
        views.setViewVisibility(R.id.widget_empty, if (emptyText != null) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.widget_empty, emptyText ?: "")

        return views
    }

    private fun SharedPreferences.intValue(key: String): Int =
        getString(key, null)?.toIntOrNull() ?: 0

    private data class Row(
        val container: Int,
        val dot: Int,
        val name: Int,
        val time: Int,
        val detail: Int,
    )

    companion object {
        private val ROWS = listOf(
            Row(R.id.row_0, R.id.row_0_dot, R.id.row_0_name, R.id.row_0_time, R.id.row_0_detail),
            Row(R.id.row_1, R.id.row_1_dot, R.id.row_1_name, R.id.row_1_time, R.id.row_1_detail),
            Row(R.id.row_2, R.id.row_2_dot, R.id.row_2_name, R.id.row_2_time, R.id.row_2_detail),
        )
    }
}
