package com.anticraft.anticount

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Anticount 桌面卡片 Provider
 *
 * 读取 HomeWidget 共享的月度收支数据，并更新 RemoteViews 显示。
 */
class AnticountWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetPlugin.getData(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.anticount_widget)

            views.setTextViewText(
                R.id.widget_month_label,
                data.getString("widget_month_label", "本月账单")
            )
            views.setTextViewText(
                R.id.widget_total_amount,
                data.getString("widget_total_amount", "0.00")
            )
            views.setTextViewText(
                R.id.widget_bill_count,
                data.getString("widget_bill_count", "0")
            )
            views.setTextViewText(
                R.id.widget_average_amount,
                data.getString("widget_average_amount", "0.00")
            )

            // 点击小部件打开应用
            val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
